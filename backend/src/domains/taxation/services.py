import sys
from decimal import Decimal, ROUND_CEILING, ROUND_HALF_UP
from typing import NamedTuple, Optional, Set

class TaxSplit(NamedTuple):
    cgst_rate: Decimal
    cgst_amount: Decimal
    sgst_rate: Decimal
    sgst_amount: Decimal
    igst_rate: Decimal
    igst_amount: Decimal
    utgst_rate: Decimal
    utgst_amount: Decimal
    cess_rate: Decimal
    cess_amount: Decimal
    total_tax: Decimal
    base_amount: Decimal
    total_amount: Decimal

# Union Territory State Codes in India
UNION_TERRITORIES: Set[str] = {
    "31",  # Lakshadweep
    "25",  # Daman and Diu (part of DNHDD)
    "26",  # Dadra and Nagar Haveli and Daman and Diu (DNHDD)
    "04",  # Chandigarh
    "35",  # Andaman and Nicobar Islands
    "38",  # Ladakh — UT without legislature, UTGST applies
    # Note: Delhi (07), Puducherry (34), and Jammu & Kashmir (01) have their own legislatures
    # and apply SGST. UTGST applies to Union Territories without a legislature.
}

def quantize_decimal(value: Decimal) -> Decimal:
    """Rounds values to 4 decimal places for intermediate values, then 2 for reporting."""
    return value.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)

def quantize_reporting(value: Decimal) -> Decimal:
    """Rounds values to 2 decimal places for billing and ledger reporting."""
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

def split_intrastate_gst_amount(gst_amount: Decimal) -> tuple[Decimal, Decimal]:
    """Splits GST into CGST and SGST/UTGST equally, with round_off absorbing odd paise."""
    gst_amount_q = quantize_reporting(gst_amount)
    half = (gst_amount_q / Decimal("2.00"))
    cgst = quantize_reporting(half)
    state_tax = quantize_reporting(gst_amount_q - cgst)
    return cgst, state_tax


_PAISE = Decimal("0.01")


def _fix_largest(rows: list, key: str, target: Decimal) -> None:
    """Adjust the largest row so the per-line sum equals the target exactly."""
    total = sum((r[key] or Decimal("0")) for r in rows)
    diff = Decimal(str(target)) - total
    if diff and rows:
        idx = max(range(len(rows)), key=lambda i: rows[i][key] or Decimal("0"))
        rows[idx][key] = (rows[idx][key] or Decimal("0")) + diff


def allocate_and_recompute_lines(
    *,
    line_subtotals: list,
    line_gst_rates: list,
    line_force_igst: list,
    line_cess_rates: list,
    subtotal: Decimal,
    discount_amount: Decimal,
    shipping_charges: Decimal,
    origin_state_code,
    place_of_supply_state_code,
    is_rcm: bool,
    is_gst_inclusive: bool,
) -> dict:
    """Single compiler for document line math after header adjustments.

    Header discounts and freight are stored only on the document header; this
    allocates them across lines (subtotal-weighted), recomputes each line's
    tax with GSTEngine on its allocated base, and returns header taxes that
    are the exact sum of the recomputed line taxes. The result is that the
    persisted line values (taxable + tax) agree with the header to the paise,
    so HSN summaries, GSTN JSON and PDFs reading lines cannot diverge from the
    totals — the header-discount overstatement bug.

    Freight is taxed (added to the taxable base) rather than appended after
    tax; for GST-inclusive documents each line's freight share is extracted at
    that line's own rate so the payable does not double-charge GST.
    """
    n = len(line_subtotals)
    if n == 0:
        return {"lines": [], "taxes": {}, "taxable_total": Decimal("0"), "shipping_added": Decimal("0"), "round_off": Decimal("0")}

    adjusted_subtotal = Decimal(str(subtotal)) - Decimal(str(discount_amount or 0))
    shipping = Decimal(str(shipping_charges or 0))

    # Split freight across lines proportionally to their pre-discount subtotal.
    total_sub = Decimal(str(subtotal)) or Decimal("1")
    shipping_rows = [{"share": shipping * (Decimal(str(s)) / total_sub)} for s in line_subtotals]
    if shipping:
        _fix_largest(shipping_rows, "share", shipping)
    shipping_shares = [r["share"] for r in shipping_rows]

    # GST-inclusive documents: the entered prices already contain GST, so the
    # freight is kept untaxed (added after tax) and is NOT folded into the
    # taxable base — otherwise the payable would double-charge GST. For
    # exclusive documents the freight is part of the supply value and taxed
    # at each line's own rate (audit H4).
    shipping_bases = [Decimal("0")] * n
    shipping_added = Decimal("0")
    if is_gst_inclusive:
        shipping_added = shipping
    else:
        shipping_bases = shipping_shares
        shipping_added = Decimal("0")
    shipping_base_total = sum(shipping_bases, Decimal("0"))

    # Discounted line bases (incl. freight), residual-fixed to the header total.
    factor = adjusted_subtotal / total_sub
    rows = []
    for i, s in enumerate(line_subtotals):
        base = (Decimal(str(s)) * factor) + shipping_bases[i]
        rows.append({"taxable": base, "idx": i})
    _fix_largest(rows, "taxable", adjusted_subtotal + shipping_base_total)

    # Recompute each line's tax with GSTEngine on its allocated base.
    result_lines = []
    tax_totals = {"cgst": Decimal("0"), "sgst": Decimal("0"), "igst": Decimal("0"), "utgst": Decimal("0"), "cess": Decimal("0")}
    for row in rows:
        i = row["idx"]
        split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=place_of_supply_state_code,
            base_amount=row["taxable"],
            gst_rate=line_gst_rates[i],
            cess_rate=line_cess_rates[i],
            is_rcm=is_rcm,
            force_igst=line_force_igst[i],
        )
        result_lines.append({
            "taxable": quantize_reporting(row["taxable"]),
            "cgst": split.cgst_amount,
            "sgst": split.sgst_amount,
            "igst": split.igst_amount,
            "utgst": split.utgst_amount,
            "cess": split.cess_amount,
            "total": split.total_amount,
        })
        if not is_rcm:
            for k in tax_totals:
                tax_totals[k] += getattr(split, f"{k}_amount")

    return {
        "lines": result_lines,
        "taxes": tax_totals,
        "taxable_total": adjusted_subtotal + shipping_base_total,
        "shipping_added": shipping_added,
    }

class GSTEngine:
    """
    Core Domain Service for calculating Indian Goods and Services Tax (GST).
    Resolves tax splits based on:
    - Business Origin State Code
    - Place of Supply (POS) State Code
    - Base Taxable Value
    - GST Rate Percentage (e.g. 5.0, 12.0, 18.0, 28.0)
    - Cess Rate Percentage (optional)
    - RCM applicability
    """

    @staticmethod
    def resolve_gst_rate(
        db,
        tenant_id,
        requested_rate: Decimal,
        supply_type: str = "DOMESTIC",
    ) -> Decimal:
        """Apply the company's explicit tax mode to an outward tax rate.

        A retained GSTIN is identification/history data and must not silently
        override NON_GST mode. Composition and non-GST businesses cannot
        collect GST from customers, so both modes force the rate to zero.
        """
        from src.infrastructure.database.models import Tenant
        tenant = db.query(Tenant).filter(Tenant.id == tenant_id, Tenant.deleted_at == None).first()
        if tenant:
            if tenant.tax_mode in ("NON_GST", "GST_COMPOSITION"):
                return Decimal("0.00")
        if supply_type in ("EXPORT_WITHOUT_TAX", "SEZ_WITHOUT_TAX"):
            return Decimal("0.00")
        return requested_rate

    @staticmethod
    def resolve_inward_gst_rate(db, tenant_id, requested_rate: Decimal) -> Decimal:
        """Return GST charged by a supplier on an inward supply.

        The buyer's registration mode controls whether input tax credit can be
        claimed; it does not erase tax legally charged by a regular supplier.
        Composition and non-GST businesses therefore retain the supplier tax
        on the purchase document and account for it as cost.
        """
        rate = Decimal(str(requested_rate))
        if rate < Decimal("0.00") or rate > Decimal("100.00"):
            raise ValueError("GST rate must be between 0 and 100.")
        return rate

    @staticmethod
    def can_claim_itc(db, tenant_id, requested_eligibility: bool = True) -> bool:
        """Resolve ITC eligibility against the buyer's registration mode."""
        from src.infrastructure.database.models import Tenant
        tenant = db.query(Tenant).filter(
            Tenant.id == tenant_id, Tenant.deleted_at == None
        ).first()
        return bool(
            requested_eligibility
            and tenant
            and tenant.tax_mode == "GST_REGULAR"
        )

    @staticmethod
    def is_gst_enabled(db, tenant_id) -> bool:
        """Check if the tenant has GST enabled."""
        from src.infrastructure.database.models import Tenant
        tenant = db.query(Tenant).filter(Tenant.id == tenant_id, Tenant.deleted_at == None).first()
        return tenant.gst_enabled if tenant else False

    @staticmethod
    def calculate_tax(
        origin_state_code: Optional[str],
        place_of_supply_state_code: Optional[str],
        base_amount: Decimal,
        gst_rate: Decimal,
        cess_rate: Decimal = Decimal("0.00"),
        is_rcm: bool = False,
        force_igst: bool = False
    ) -> TaxSplit:
        if base_amount < Decimal("0.00"):
            raise ValueError("Base taxable amount cannot be negative.")
        if gst_rate < Decimal("0.00") or gst_rate > Decimal("100.00"):
            raise ValueError("GST rate must be between 0 and 100.")
        if cess_rate < Decimal("0.00") or cess_rate > Decimal("100.00"):
            raise ValueError("Cess rate must be between 0 and 100.")

        base_amount_q = quantize_decimal(base_amount)
        gst_rate_q = quantize_decimal(gst_rate)
        cess_rate_q = quantize_decimal(cess_rate)

        # Standard GST is computed, then split or combined
        total_tax_percentage = gst_rate_q / Decimal("100.00")
        cess_percentage = cess_rate_q / Decimal("100.00")

        # Core Tax Amount Calculations
        calculated_gst_amount = quantize_decimal(base_amount_q * total_tax_percentage)
        calculated_cess_amount = quantize_decimal(base_amount_q * cess_percentage)

        # Output properties
        cgst_rate = Decimal("0.00")
        cgst_amount = Decimal("0.00")
        sgst_rate = Decimal("0.00")
        sgst_amount = Decimal("0.00")
        igst_rate = Decimal("0.00")
        igst_amount = Decimal("0.00")
        utgst_rate = Decimal("0.00")
        utgst_amount = Decimal("0.00")

        # Determine Intra-state vs Inter-state. Missing origin or POS is never
        # treated as intra-state (empty == empty would otherwise split CGST/SGST).
        origin = (origin_state_code or "").strip()
        pos = (place_of_supply_state_code or "").strip()
        is_intra_state = bool(origin) and bool(pos) and origin == pos and not force_igst

        if is_intra_state:
            # Intra-state: CGST + SGST/UTGST
            split_rate = gst_rate_q / Decimal("2.00")
            cgst_amount, state_tax_amount = split_intrastate_gst_amount(calculated_gst_amount)

            # Check if Place of Supply is a Union Territory without legislature
            if place_of_supply_state_code in UNION_TERRITORIES:
                utgst_rate = split_rate
                utgst_amount = state_tax_amount
            else:
                sgst_rate = split_rate
                sgst_amount = state_tax_amount

            cgst_rate = split_rate
        else:
            # Inter-state: IGST
            igst_rate = gst_rate_q
            igst_amount = calculated_gst_amount

        # Round every component to reporting precision FIRST, then derive the
        # totals from the rounded components. Rounding an independent total
        # (4-dp tax) and then summing independently-rounded components can
        # disagree by a paise; the invoice header stores the sum of the
        # rounded line components, so GSTEngine's totals must match that.
        cgst_amount = quantize_reporting(cgst_amount)
        sgst_amount = quantize_reporting(sgst_amount)
        igst_amount = quantize_reporting(igst_amount)
        utgst_amount = quantize_reporting(utgst_amount)
        cess_amount = quantize_reporting(calculated_cess_amount)
        total_tax = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount

        # If Reverse Charge applies, the buyer owes the tax.
        # The document itself has the tax split calculated for reporting,
        # but the net tax added to invoice subtotal is zero.
        if is_rcm:
            total_amount = quantize_reporting(base_amount_q)
        else:
            total_amount = quantize_reporting(base_amount_q) + total_tax

        return TaxSplit(
            cgst_rate=quantize_reporting(cgst_rate),
            cgst_amount=cgst_amount,
            sgst_rate=quantize_reporting(sgst_rate),
            sgst_amount=sgst_amount,
            igst_rate=quantize_reporting(igst_rate),
            igst_amount=igst_amount,
            utgst_rate=quantize_reporting(utgst_rate),
            utgst_amount=utgst_amount,
            cess_rate=quantize_reporting(cess_rate_q),
            cess_amount=cess_amount,
            total_tax=total_tax,
            base_amount=quantize_reporting(base_amount_q),
            total_amount=total_amount
        )
