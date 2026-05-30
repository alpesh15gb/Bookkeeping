import sys
from decimal import Decimal, ROUND_CEILING, ROUND_HALF_UP
from typing import NamedTuple, Set

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
    "19",  # Lakshadweep
    "25",  # Daman and Diu (part of DNHDD)
    "26",  # Dadra and Nagar Haveli and Daman and Diu (DNHDD)
    "04",  # Chandigarh
    "35",  # Andaman and Nicobar Islands
    # Ladakh (38) has its own legislature and applies SGST, not UTGST
    # Note: Delhi (07), Puducherry (34), Ladakh (38), and Jammu & Kashmir (01) have their own legislatures
    # and apply SGST, but UTGST applies to Union Territories without a legislature.
}

def quantize_decimal(value: Decimal) -> Decimal:
    """Rounds values to 4 decimal places for intermediate values, then 2 for reporting."""
    return value.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)

def quantize_reporting(value: Decimal) -> Decimal:
    """Rounds values to 2 decimal places for billing and ledger reporting."""
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

def split_intrastate_gst_amount(gst_amount: Decimal) -> tuple[Decimal, Decimal]:
    """Splits GST into CGST and SGST/UTGST without losing odd paise."""
    gst_amount_q = quantize_reporting(gst_amount)
    cgst = ((gst_amount_q / Decimal("2.00")) * Decimal("100")).to_integral_value(
        rounding=ROUND_CEILING
    ) / Decimal("100")
    cgst = quantize_reporting(cgst)
    state_tax = quantize_reporting(gst_amount_q - cgst)
    return cgst, state_tax

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
    def calculate_tax(
        origin_state_code: str,
        place_of_supply_state_code: str,
        base_amount: Decimal,
        gst_rate: Decimal,
        cess_rate: Decimal = Decimal("0.00"),
        is_rcm: bool = False
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

        # Determine Intra-state vs Inter-state
        is_intra_state = (origin_state_code == place_of_supply_state_code)

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

        # If Reverse Charge applies, the buyer owes the tax.
        # The document itself has the tax split calculated for reporting,
        # but the net tax added to invoice subtotal is zero.
        total_tax_added = calculated_gst_amount + calculated_cess_amount
        
        if is_rcm:
            # Under RCM, buyer pays tax directly. Tax is computed and displayed but not added to total payable.
            # RCM validation: if RCM is true, the caller must ensure tax amounts
            # are handled correctly (buyer self-accounts for tax)
            total_amount = base_amount_q
        else:
            total_amount = base_amount_q + total_tax_added

        return TaxSplit(
            cgst_rate=quantize_reporting(cgst_rate),
            cgst_amount=quantize_reporting(cgst_amount),
            sgst_rate=quantize_reporting(sgst_rate),
            sgst_amount=quantize_reporting(sgst_amount),
            igst_rate=quantize_reporting(igst_rate),
            igst_amount=quantize_reporting(igst_amount),
            utgst_rate=quantize_reporting(utgst_rate),
            utgst_amount=quantize_reporting(utgst_amount),
            cess_rate=quantize_reporting(cess_rate_q),
            cess_amount=quantize_reporting(calculated_cess_amount),
            total_tax=quantize_reporting(calculated_gst_amount + calculated_cess_amount),
            base_amount=quantize_reporting(base_amount_q),
            total_amount=quantize_reporting(total_amount)
        )
