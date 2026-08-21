"""Invoice and Document PDF generation using reportlab with multiple templates."""
from decimal import Decimal
from typing import Optional, Any
import uuid
import os
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, KeepTogether
from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_LEFT
from reportlab.graphics.shapes import Drawing
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import io

# ── Register Inter font (supports ₹ Unicode rupee sign U+20B9) ────────────────
_FONT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))), 'assets', 'fonts')
_INTER_REG  = os.path.join(_FONT_DIR, 'Inter-Regular.ttf')
_INTER_BOLD = os.path.join(_FONT_DIR, 'Inter-Bold.ttf')
_INTER_MED  = os.path.join(_FONT_DIR, 'Inter-Medium.ttf')

_INTER_LOADED = False
try:
    if os.path.exists(_INTER_REG) and os.path.exists(_INTER_BOLD):
        pdfmetrics.registerFont(TTFont('Inter',     _INTER_REG))
        pdfmetrics.registerFont(TTFont('Inter-Bold', _INTER_BOLD))
        if os.path.exists(_INTER_MED):
            pdfmetrics.registerFont(TTFont('Inter-Medium', _INTER_MED))
        from reportlab.lib.fonts import addMapping
        addMapping('Inter', 0, 0, 'Inter')
        addMapping('Inter', 1, 0, 'Inter-Bold')
        _INTER_LOADED = True
except Exception as _e:
    pass  # fall back to Helvetica if font files missing

FONT_NORMAL = 'Inter'      if _INTER_LOADED else 'Helvetica'
FONT_BOLD   = 'Inter-Bold' if _INTER_LOADED else 'Helvetica-Bold'
RUPEE       = '\u20b9'     if _INTER_LOADED else 'Rs.'  # ₹ or Rs.

STATE_CODES = {
    "01": "Jammu & Kashmir", "02": "Himachal Pradesh", "03": "Punjab", "04": "Chandigarh",
    "05": "Uttarakhand", "06": "Haryana", "07": "Delhi", "08": "Rajasthan", "09": "Uttar Pradesh",
    "10": "Bihar", "11": "Sikkim", "12": "Arunachal Pradesh", "13": "Nagaland", "14": "Manipur",
    "15": "Mizoram", "16": "Tripura", "17": "Meghalaya", "18": "Assam", "19": "West Bengal",
    "20": "Jharkhand", "21": "Odisha", "22": "Chhattisgarh", "23": "Madhya Pradesh", "24": "Gujarat",
    "25": "Daman & Diu", "26": "Dadra & Nagar Haveli and Daman & Diu", "27": "Maharashtra", "28": "Andhra Pradesh (Old)",
    "29": "Karnataka", "30": "Goa", "31": "Lakshadweep", "32": "Kerala", "33": "Tamil Nadu",
    "34": "Puducherry", "35": "Andaman & Nicobar Islands", "36": "Telangana", "37": "Andhra Pradesh",
    "38": "Ladakh", "97": "Other Territory"
}

def generate_invoice_pdf(
    invoice_number: str,
    issue_date,
    due_date,
    customer_name: str,
    customer_gstin: Optional[str],
    items: list,
    subtotal: Decimal,
    total: Decimal,
    cgst: Decimal = Decimal("0"),
    sgst: Decimal = Decimal("0"),
    igst: Decimal = Decimal("0"),
    utgst: Decimal = Decimal("0"),
    cess: Decimal = Decimal("0"),
    round_off: Decimal = Decimal("0"),
    company_name: str = "ApexBooks",
    template: str = "professional",
    doc_type: str = "INVOICE",
    tenant_id: Optional[uuid.UUID] = None,
    db = None,
    amount_paid: Decimal = Decimal("0.00"),
    customer_address: Optional[Any] = None,
    company_address: Optional[Any] = None,
    terms_and_conditions: Optional[str] = None,
    place_of_supply_state_code: Optional[str] = None,
    is_gst_inclusive: bool = False,
) -> bytes:
    buffer = io.BytesIO()

    def _fmt_addr(addr):
        if not addr:
            return ""
        if isinstance(addr, str):
            return addr
        if isinstance(addr, dict):
            parts = [
                addr.get("street"),
                addr.get("city"),
                f"{addr.get('state')} - {addr.get('pincode')}" if addr.get("pincode") else addr.get("state"),
                addr.get("country")
            ]
            return ", ".join([str(p) for p in parts if p])
        return str(addr)
    
    # --- Load Company Details from Database ---
    company_gstin = None
    company_pan = None
    company_address_db = None
    company_phone = None
    company_email = None
    company_website = None
    bank_name = None
    bank_account_no = None
    bank_ifsc = None
    bank_branch = None
    terms = terms_and_conditions
    origin_state_code = None
    show_bank_details = True
    show_upi_qr = True
    signee_name = None
    signee_designation = None
    upi_id = None

    if db and tenant_id:
        from src.infrastructure.database.models import Tenant, TenantSetting, BankingProfile
        tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
        if tenant:
            company_name = tenant.legal_name
            company_gstin = tenant.gstin
            company_pan = tenant.pan
            
        setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
        if setting:
            origin_state_code = setting.origin_state_code
            upi_id = setting.upi_id
            extra = setting.extra_settings or {}
            company_address_db = extra.get("company_address")
            company_phone = extra.get("company_phone")
            company_email = extra.get("company_email")
            company_website = extra.get("company_website")
            if not terms:
                terms = extra.get("terms")
            show_bank_details = extra.get("show_bank_details", True) is not False
            show_upi_qr = extra.get("show_upi_qr", True) is not False
            signee_name = extra.get("signee_name")
            signee_designation = extra.get("signee_designation")

        bank = db.query(BankingProfile).filter(
            BankingProfile.tenant_id == tenant_id,
            BankingProfile.is_primary == True,
            BankingProfile.is_active == True,
        ).first()
        if not bank:
            bank = db.query(BankingProfile).filter(
                BankingProfile.tenant_id == tenant_id,
                BankingProfile.is_active == True,
            ).order_by(BankingProfile.created_at.asc()).first()
        if bank:
            bank_name = bank.bank_name
            bank_account_no = bank.account_number
            bank_ifsc = bank.ifsc_code
            bank_branch = bank.branch_name

    # Clean fallbacks for rendering
    company_address = _fmt_addr(company_address or company_address_db)
    customer_address = _fmt_addr(customer_address)
    company_phone = company_phone or ""
    company_email = company_email or ""
    company_website = company_website or ""
    display_pos_code = place_of_supply_state_code or origin_state_code
    rate_header = (
        "Rate incl. GST" if is_gst_inclusive else "Rate excl. GST"
    )
    
    # 1. Page settings based on template format
    if template == "thermal":
        page_width = 80 * mm
        page_height = 200 * mm
        doc = SimpleDocTemplate(
            buffer,
            pagesize=(page_width, page_height),
            leftMargin=3*mm,
            rightMargin=3*mm,
            topMargin=5*mm,
            bottomMargin=5*mm
        )
    else:
        doc = SimpleDocTemplate(
            buffer,
            pagesize=A4,
            leftMargin=12*mm,
            rightMargin=12*mm,
            topMargin=12*mm,
            bottomMargin=12*mm
        )
        
    styles = getSampleStyleSheet()
    elements = []

    # Calculate balance due for payment summary
    balance_due = total - (amount_paid or Decimal("0.00"))
    has_payments = (amount_paid or Decimal("0.00")) > 0

    # 2. Design System Themes
    if template == "modern":
        primary_color = colors.HexColor('#4F46E5')  # Elegant Indigo
        text_color = colors.HexColor('#1F2937')
        muted_color = colors.HexColor('#4B5563')
        table_header_bg = colors.HexColor('#F3F4F6')
        border_color = colors.HexColor('#D1D5DB')
    elif template == "thermal":
        primary_color = colors.black
        text_color = colors.black
        muted_color = colors.black
        table_header_bg = colors.white
        border_color = colors.black
    elif template == "minimal":
        primary_color = colors.HexColor('#111827')  # Near black
        text_color = colors.HexColor('#374151')
        muted_color = colors.HexColor('#6B7280')
        table_header_bg = colors.white
        border_color = colors.HexColor('#E5E7EB')
    elif template == "elegant":
        primary_color = colors.HexColor('#1B4332')  # Forest green
        text_color = colors.HexColor('#1E293B')
        muted_color = colors.HexColor('#52796F')
        table_header_bg = colors.HexColor('#E8F5E9')
        border_color = colors.HexColor('#A5D6A7')
    else:  # professional (default / Format 1 & 3 layout style)
        primary_color = colors.HexColor('#0F1B3D')  # Deep Navy Blue
        text_color = colors.HexColor('#1E293B')
        muted_color = colors.HexColor('#475569')
        table_header_bg = colors.HexColor('#E2E8F0')
        border_color = colors.HexColor('#94A3B8')

    font_multiplier = 0.8 if template == "thermal" else 1.0
    
    # Typographic definitions
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Heading1'],
        fontName=FONT_BOLD,
        fontSize=15 * font_multiplier,
        leading=18 * font_multiplier,
        textColor=primary_color,
        alignment=TA_CENTER
    )
    
    company_title = ParagraphStyle(
        'CompanyTitle',
        parent=styles['Normal'],
        fontName=FONT_BOLD,
        fontSize=16 * font_multiplier,
        leading=20 * font_multiplier,
        textColor=primary_color if template != "thermal" else colors.black,
        alignment=TA_CENTER
    )
    
    normal_style = ParagraphStyle(
        'DocNormal',
        parent=styles['Normal'],
        fontName=FONT_NORMAL,
        fontSize=9 * font_multiplier,
        leading=12 * font_multiplier,
        textColor=text_color
    )
    
    bold_style = ParagraphStyle(
        'DocBold',
        parent=styles['Normal'],
        fontName=FONT_BOLD,
        fontSize=9 * font_multiplier,
        leading=12 * font_multiplier,
        textColor=text_color
    )
    
    center_style = ParagraphStyle(
        'DocCenter',
        parent=normal_style,
        alignment=TA_CENTER
    )

    right_style = ParagraphStyle(
        'DocRight',
        parent=normal_style,
        alignment=TA_RIGHT
    )

    bold_right = ParagraphStyle(
        'DocBoldRight',
        parent=bold_style,
        alignment=TA_RIGHT
    )

    caption_style = ParagraphStyle(
        'DocCaption',
        parent=styles['Normal'],
        fontName=FONT_NORMAL,
        fontSize=8 * font_multiplier,
        leading=10 * font_multiplier,
        textColor=muted_color
    )

    # QR Code builder
    def build_qr_code(data_str: str, size: float = 65.0) -> Drawing:
        qr = QrCodeWidget(data_str)
        qr.barWidth = size
        qr.barHeight = size
        qr.qrVersion = 3
        d = Drawing(size, size)
        d.add(qr)
        return d

    # UPI Payload String
    upi_payload = (
        f"upi://pay?pa={upi_id}&pn={company_name}&am={total}&cu=INR"
        if upi_id else None
    )
    qr_drawing = (
        build_qr_code(upi_payload, size=65.0)
        if show_upi_qr and upi_payload else Paragraph("", normal_style)
    )

    # Render Thermal / POS Layout
    if template == "thermal":
        elements.append(Paragraph(company_name.upper(), company_title))
        if company_address:
            elements.append(Paragraph(company_address, center_style))
        if company_phone:
            elements.append(Paragraph(f"Ph: {company_phone}", center_style))
        elements.append(Spacer(1, 2*mm))
        elements.append(Paragraph(f"<b>{doc_type}</b>", title_style))
        elements.append(Paragraph(f"No: {invoice_number}", normal_style))
        elements.append(Paragraph(f"Date: {issue_date}", normal_style))
        elements.append(Paragraph(f"Client: {customer_name}", normal_style))
        if customer_address:
            elements.append(Paragraph(f"Address: {customer_address}", normal_style))
        if customer_gstin:
            elements.append(Paragraph(f"GSTIN: {customer_gstin}", normal_style))
        elements.append(Spacer(1, 2*mm))
        
        # Table columns
        table_data = [[
            Paragraph("<b>Item</b>", normal_style),
            Paragraph("<b>Qty</b>", right_style),
            Paragraph(f"<b>{rate_header}</b>", right_style),
            Paragraph("<b>Amt</b>", right_style)
        ]]
        for item in items:
            desc = item.get('description') or item.get('product_name') or 'N/A'
            qty = float(item.get('quantity', 0))
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            table_data.append([
                Paragraph(desc, normal_style),
                Paragraph(f"{qty:.0f}", right_style),
                Paragraph(f"{rate:.2f}", right_style),
                Paragraph(f"{amt:.2f}", right_style),
            ])
            
        t = Table(table_data, colWidths=[34*mm, 10*mm, 15*mm, 15*mm])
        t.setStyle(TableStyle([
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('BOTTOMPADDING', (0,0), (-1,-1), 1),
            ('TOPPADDING', (0,0), (-1,-1), 1),
            ('LINEBELOW', (0,0), (-1,0), 0.5, colors.black),
            ('LINEBELOW', (0,-1), (-1,-1), 0.5, colors.black),
        ]))
        elements.append(t)
        elements.append(Spacer(1, 2*mm))
        
        total_data = [
            [Paragraph("Subtotal:", normal_style), Paragraph(f"Rs. {subtotal:.2f}", right_style)],
        ]
        if cgst and cgst > 0:
            total_data.append([Paragraph("CGST:", normal_style), Paragraph(f"Rs. {cgst:.2f}", right_style)])
        if sgst and sgst > 0:
            total_data.append([Paragraph("SGST:", normal_style), Paragraph(f"Rs. {sgst:.2f}", right_style)])
        if igst and igst > 0:
            total_data.append([Paragraph("IGST:", normal_style), Paragraph(f"Rs. {igst:.2f}", right_style)])
        total_data.append([Paragraph("Total:", bold_style), Paragraph(f"Rs. {total:.2f}", bold_right)])
        if has_payments:
            total_data.append([Paragraph("Amount Paid:", normal_style), Paragraph(f"Rs. {amount_paid:.2f}", right_style)])
            total_data.append([Paragraph("<b>Balance Due:</b>", bold_style), Paragraph(f"<b>Rs. {balance_due:.2f}</b>", bold_right)])
        t_total = Table(total_data, colWidths=[40*mm, 34*mm])
        t_total.setStyle(TableStyle([
            ('BOTTOMPADDING', (0,0), (-1,-1), 1),
            ('TOPPADDING', (0,0), (-1,-1), 1),
        ]))
        elements.append(t_total)
        elements.append(Spacer(1, 4*mm))
        elements.append(Paragraph("Thank you for your business!", center_style))

    # Render A4 Professional Layout (Navy / Shree Krishna Layout)
    elif template == "professional":
        header_text = f"<b>{doc_type}</b>"
        if company_gstin:
            elements.append(Table([[Paragraph(f"GSTIN: {company_gstin}", normal_style), Paragraph(header_text, ParagraphStyle('HRight', parent=title_style, alignment=TA_RIGHT))]], colWidths=[90*mm, 96*mm], style=[('VALIGN', (0,0), (-1,-1), 'BOTTOM')]))
        else:
            elements.append(Paragraph(header_text, title_style))
        
        # Company Info Box
        company_details_str = f"<b>{company_name}</b><br/>"
        if company_address:
            company_details_str += f"{company_address}<br/>"
        contact_line = ""
        if company_phone:
            contact_line += f"Contact: {company_phone}"
        if company_email:
            contact_line += f", E-Mail: {company_email}"
        if contact_line:
            company_details_str += f"{contact_line}<br/>"
        if company_website:
            company_details_str += f"Website: {company_website}"
            
        elements.append(Spacer(1, 2*mm))
        elements.append(Table([[Paragraph(company_details_str, center_style)]], colWidths=[186*mm], style=[
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F1F5F9')),
            ('PADDING', (0,0), (-1,-1), 8),
            ('ALIGN', (0,0), (-1,-1), 'CENTER'),
            ('BOX', (0,0), (-1,-1), 1, border_color)
        ]))
        elements.append(Spacer(1, 4*mm))

        # Metadata Details Row
        meta_data = [
            [Paragraph(f"<b>Document No:</b> {invoice_number}", normal_style), Paragraph(f"<b>Place of Supply:</b> {display_pos_code or 'N/A'}", normal_style)],
            [Paragraph(f"<b>Issue Date:</b> {issue_date}", normal_style), Paragraph(f"<b>Due Date:</b> {due_date}", normal_style)],
            [Paragraph(f"<b>PAN:</b> {company_pan or 'N/A'}", normal_style), ""]
        ]
        meta_table = Table(meta_data, colWidths=[93*mm, 93*mm], style=[
            ('BOX', (0,0), (-1,-1), 0.5, border_color),
            ('INNERGRID', (0,0), (-1,-1), 0.5, border_color),
            ('PADDING', (0,0), (-1,-1), 4),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE')
        ])
        elements.append(meta_table)
        elements.append(Spacer(1, 4*mm))

        # Billing Party Section
        billing_box = [
            [Paragraph("<b>Billed to:</b>", bold_style)],
            [Paragraph(f"<b>{customer_name}</b>", normal_style)],
        ]
        if customer_address:
            billing_box.append([Paragraph(customer_address, normal_style)])
        billing_box.append([Paragraph(f"GSTIN: {customer_gstin or 'Unregistered'}", normal_style)])

        billing_table = Table(billing_box, colWidths=[186*mm], style=[
            ('BOX', (0,0), (-1,-1), 0.5, border_color),
            ('PADDING', (0,0), (-1,-1), 6),
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F8FAFC'))
        ])
        elements.append(billing_table)
        elements.append(Spacer(1, 4*mm))

        # Items Table
        table_headers = ['S.No.', 'Description of Goods', 'Qty', rate_header, 'Amount']
        grid_data = [[Paragraph(f"<b>{h}</b>", bold_style) for h in table_headers]]
        for i, item in enumerate(items, 1):
            desc = item.get('description') or item.get('product_name') or 'N/A'
            qty = float(item.get('quantity', 0))
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            grid_data.append([
                Paragraph(str(i), normal_style),
                Paragraph(desc, normal_style),
                Paragraph(f"{qty:.0f}", normal_style),
                Paragraph(f"{rate:.2f}", normal_style),
                Paragraph(f"{amt:.2f}", normal_style)
            ])
            
        items_table = Table(grid_data, colWidths=[15*mm, 101*mm, 20*mm, 25*mm, 25*mm], style=[
            ('BACKGROUND', (0,0), (-1,0), table_header_bg),
            ('BOX', (0,0), (-1,-1), 0.5, border_color),
            ('INNERGRID', (0,0), (-1,-1), 0.5, border_color),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('PADDING', (0,0), (-1,-1), 4),
        ])
        elements.append(items_table)
        elements.append(Spacer(1, 4*mm))

        # Summary Block (Bank Details, Scan to Pay, Totals)
        if show_bank_details:
            bank_details_str = f"<b>Company's Bank Details:</b><br/>Bank: {bank_name or 'N/A'}<br/>A/c No: {bank_account_no or 'N/A'}<br/>IFSC: {bank_ifsc or 'N/A'}<br/>Branch: {bank_branch or 'N/A'}"
        else:
            bank_details_str = ""
        
        totals_col = [
            [Paragraph("Subtotal:", normal_style), Paragraph(f"Rs. {subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"Rs. {cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"Rs. {sgst:.2f}", right_style)],
            [Paragraph("IGST:", normal_style), Paragraph(f"Rs. {igst:.2f}", right_style)],
            [Paragraph("Round Off:", normal_style), Paragraph(f"Rs. {round_off:.2f}", right_style)],
            [Paragraph("<b>TOTAL:</b>", bold_style), Paragraph(f"<b>Rs. {total:.2f}</b>", bold_right)],
        ]
        if has_payments:
            totals_col.append([Paragraph("Amount Paid:", normal_style), Paragraph(f"Rs. {amount_paid:.2f}", right_style)])
            totals_col.append([Paragraph("<b>Balance Due:</b>", bold_style), Paragraph(f"<b>Rs. {balance_due:.2f}</b>", bold_right)])
        totals_table = Table(totals_col, colWidths=[38*mm, 32*mm], style=[
            ('PADDING', (0,0), (-1,-1), 2),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE')
        ])

        summary_row = [
            [Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]
        ]
        
        summary_table = Table(summary_row, colWidths=[78*mm, 32*mm, 76*mm], style=[
            ('BOX', (0,0), (-1,-1), 0.5, border_color),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6),
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F8FAFC'))
        ])
        elements.append(summary_table)
        
        # Terms and signatory
        elements.append(Spacer(1, 4*mm))
        terms_str = f"<b>Terms & Conditions:</b><br/>{terms or '1. Goods once sold will not be taken back.'}"
        sign_label = signee_name if (signee_name and signee_name.strip()) else f"for <b>{company_name}</b>"
        sign_desig = signee_designation if (signee_designation and signee_designation.strip()) else "Authorised Signatory"
        sign_block = f"<br/><br/><br/>{sign_label}<br/><br/>{sign_desig}"
        
        bottom_table = Table([[Paragraph(terms_str, caption_style), Paragraph(sign_block, center_style)]], colWidths=[120*mm, 66*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 0),
        ])
        elements.append(bottom_table)
     # Render A4 Tally GST Layout (Format 2 - Tata Motors Style Boxy Layout)
    elif template == "tally_gst":
        tally_primary = colors.HexColor('#000000')
        tally_border = colors.HexColor('#000000')
        
        # Header banner
        title_p = Paragraph(f"<b>Tax Invoice</b>", ParagraphStyle('TallyTitle', parent=styles['Normal'], fontName=FONT_BOLD, fontSize=12, alignment=TA_CENTER, textColor=colors.black))
        orig_p = Paragraph(f"<font size=8 color='#555555'>ORIGINAL FOR RECIPIENT</font>", ParagraphStyle('OrigR', parent=styles['Normal'], alignment=TA_RIGHT))
        elements.append(Table([[title_p, orig_p]], colWidths=[110*mm, 76*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'BOTTOM'),
            ('PADDING', (0,0), (-1,-1), 2)
        ]))
        elements.append(Spacer(1, 1*mm))
        
        # Header main grid (Left: Company Name, logo placeholder, address, GSTIN, State. Right: Invoice No, Date, POS)
        state_code_str = origin_state_code or (company_gstin[:2] if company_gstin and len(company_gstin) >= 2 and company_gstin[:2].isdigit() else "36")
        state_name = STATE_CODES.get(state_code_str, "Telangana")
        formatted_state = f"{state_code_str}-{state_name}"
        pos_name = STATE_CODES.get(display_pos_code, "")
        formatted_pos_state = (
            f"{display_pos_code}-{pos_name}" if display_pos_code else "N/A"
        )

        co_str = f"<b><font size=12>{company_name}</font></b><br/>"
        if company_address:
            co_str += f"<font size=8>{company_address}</font><br/>"
        if company_phone:
            co_str += f"<font size=8>Phone no.: {company_phone}</font><br/>"
        if company_email:
            co_str += f"<font size=8>Email: {company_email}</font><br/>"
        if company_gstin:
            co_str += f"<font size=8>GSTIN: {company_gstin}</font><br/>"
        co_str += f"<font size=8>State: {formatted_state}</font>"
        
        company_p = Paragraph(co_str, normal_style)
        
        meta_table_data = [
            [Paragraph("Invoice No.", ParagraphStyle('MetaH', parent=normal_style, fontSize=7, textColor=colors.HexColor('#555555'))),
             Paragraph("Date", ParagraphStyle('MetaH2', parent=normal_style, fontSize=7, textColor=colors.HexColor('#555555')))],
            [Paragraph(f"<b>{invoice_number}</b>", ParagraphStyle('MetaVal', parent=normal_style, fontName=FONT_BOLD, fontSize=9)),
             Paragraph(f"<b>{issue_date}</b>", ParagraphStyle('MetaVal2', parent=normal_style, fontName=FONT_BOLD, fontSize=9))],
            [Paragraph("Place of supply", ParagraphStyle('MetaH3', parent=normal_style, fontSize=7, textColor=colors.HexColor('#555555'))), ""],
            [Paragraph(f"<b>{formatted_pos_state}</b>", ParagraphStyle('MetaVal3', parent=normal_style, fontName=FONT_BOLD, fontSize=9)), ""]
        ]
        meta_table = Table(meta_table_data, colWidths=[38*mm, 38*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 3),
            ('SPAN', (0,2), (1,2)),
            ('SPAN', (0,3), (1,3)),
            ('LINEBELOW', (0,1), (1,1), 0.5, tally_border),
            ('LINEBELOW', (0,3), (1,3), 0.5, tally_border),
            ('LINEAFTER', (0,0), (0,1), 0.5, tally_border),
        ])
        
        header_grid = Table([[company_p, meta_table]], colWidths=[110*mm, 76*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, tally_border),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 4)
        ])
        elements.append(header_grid)
        
        # Billing details box (Bill To)
        bill_to_str = f"Bill To<br/><b>{customer_name}</b><br/>"
        if customer_address:
            bill_to_str += f"{customer_address}<br/>"
        if customer_gstin:
            bill_to_str += f"GSTIN : {customer_gstin}<br/>"
        
        cust_state_code = customer_gstin[:2] if customer_gstin and len(customer_gstin) >= 2 and customer_gstin[:2].isdigit() else "36"
        cust_state_name = STATE_CODES.get(cust_state_code, "Telangana")
        formatted_cust_state = f"{cust_state_code}-{cust_state_name}"
        bill_to_str += f"State: {formatted_cust_state}"
        
        bill_to_table = Table([[Paragraph(bill_to_str, normal_style)]], colWidths=[186*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('PADDING', (0,0), (-1,-1), 5)
        ])
        elements.append(bill_to_table)
        
        # Items Table (Columns: #, Item name, HSN/SAC, Quantity, Price/Unit, GST, Amount)
        table_headers = [
            Paragraph("<b>#</b>", ParagraphStyle('ColH', parent=bold_style, fontSize=8)),
            Paragraph("<b>Item name</b>", ParagraphStyle('ColH2', parent=bold_style, fontSize=8)),
            Paragraph("<b>HSN/SAC</b>", ParagraphStyle('ColH3', parent=bold_style, fontSize=8)),
            Paragraph("<b>Quantity</b>", ParagraphStyle('ColH4', parent=bold_style, fontSize=8, alignment=TA_RIGHT)),
            Paragraph(f"<b>{rate_header}</b>", ParagraphStyle('ColH5', parent=bold_style, fontSize=8, alignment=TA_RIGHT)),
            Paragraph("<b>GST</b>", ParagraphStyle('ColH6', parent=bold_style, fontSize=8, alignment=TA_RIGHT)),
            Paragraph("<b>Amount</b>", ParagraphStyle('ColH7', parent=bold_style, fontSize=8, alignment=TA_RIGHT))
        ]
        grid_data = [table_headers]
        
        tot_qty = 0.0
        tot_gst_tax = 0.0
        for idx, item in enumerate(items, 1):
            desc = item.get('description') or item.get('product_name') or 'N/A'
            hsn = item.get('hsn_sac') or ''
            qty = float(item.get('quantity', 0))
            tot_qty += qty
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            
            # calculate tax amount for display
            gst_rate = float(item.get('gst_rate', 0))
            cgst_amt = float(item.get('cgst_amount', 0))
            sgst_amt = float(item.get('sgst_amount', 0))
            igst_amt = float(item.get('igst_amount', 0))
            tax_amt = cgst_amt + sgst_amt + igst_amt
            tot_gst_tax += tax_amt
            
            grid_data.append([
                Paragraph(str(idx), normal_style),
                Paragraph(desc, normal_style),
                Paragraph(hsn, normal_style),
                Paragraph(f"{qty:.0f}", right_style),
                Paragraph(f"{RUPEE} {rate:,.2f}", right_style),
                Paragraph(f"{RUPEE} {tax_amt:,.2f} ({gst_rate:.0f}%)", right_style),
                Paragraph(f"{RUPEE} {amt:,.2f}", right_style)
            ])
            
        # Add empty rows to match height if list is short
        target_rows = 4
        if len(items) < target_rows:
            for _ in range(target_rows - len(items)):
                grid_data.append([Paragraph("", normal_style), Paragraph("", normal_style), Paragraph("", normal_style), Paragraph("", normal_style), Paragraph("", normal_style), Paragraph("", normal_style), Paragraph("", normal_style)])
                
        # Total line in table
        grid_data.append([
            Paragraph("", bold_style),
            Paragraph("<b>Total</b>", bold_style),
            Paragraph("", bold_style),
            Paragraph(f"<b>{tot_qty:.0f}</b>", bold_right),
            Paragraph("", bold_style),
            Paragraph(f"<b>{RUPEE} {tot_gst_tax:,.2f}</b>", bold_right),
            Paragraph(f"<b>{RUPEE} {float(total):,.2f}</b>", bold_right)
        ])
        
        items_table = Table(grid_data, colWidths=[10*mm, 68*mm, 20*mm, 20*mm, 22*mm, 24*mm, 22*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor('#CCCCCC')),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('PADDING', (0,0), (-1,-1), 3),
            ('LINEBELOW', (0,0), (-1,0), 1, tally_border),
            ('LINEABOVE', (0,-1), (-1,-1), 1, tally_border),
        ])
        elements.append(items_table)
        
        # Invoice Amount in words and Amount summaries
        # Convert total to words or use a default string
        try:
            from src.common.utils import num2words
        except ImportError:
            num2words = lambda n: ""
        try:
            words_str = f"<b>Invoice Amount in Words</b><br/>{num2words(int(total)).title()} Rupees Only"
        except Exception:
            words_str = "<b>Invoice Amount in Words</b><br/>Amount calculated"
            
        amounts_col = [
            [Paragraph("Sub Total", normal_style), Paragraph(f"{RUPEE} {float(subtotal):,.2f}", right_style)],
            [Paragraph("Round off", normal_style), Paragraph(f"{RUPEE} {float(round_off):,.2f}", right_style)],
            [Paragraph("<b>Total</b>", bold_style), Paragraph(f"<b>{RUPEE} {float(total):,.2f}</b>", bold_right)],
            [Paragraph("Received", normal_style), Paragraph(f"{RUPEE} {float(amount_paid):,.2f}", right_style)],
            [Paragraph("Balance", bold_style), Paragraph(f"<b>{RUPEE} {float(balance_due):,.2f}</b>", bold_right)]
        ]
        amounts_table = Table(amounts_col, colWidths=[38*mm, 32*mm], style=[
            ('PADDING', (0,0), (-1,-1), 2),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('LINEBELOW', (0,0), (-1,-2), 0.5, colors.HexColor('#E2E8F0')),
            ('LINEABOVE', (0,-1), (-1,-1), 0.5, tally_border)
        ])
        
        summary_grid = Table([
            [Paragraph(words_str, normal_style), amounts_table],
            [Paragraph(f"Payment mode<br/><b>Credit</b>", normal_style), ""]
        ], colWidths=[116*mm, 70*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, tally_border),
            ('SPAN', (0,0), (0,0)),
            ('SPAN', (1,0), (1,1)),
            ('PADDING', (0,0), (-1,-1), 4),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ])
        elements.append(summary_grid)
        
        # GST Tax Analysis Breakdown (Double Columns CGST/SGST/IGST breakdown)
        hsn_summary = {}
        for item in items:
            hsn = item.get('hsn_sac') or 'N/A'
            taxable = float(item.get('total', 0)) - float(item.get('cgst_amount', 0)) - float(item.get('sgst_amount', 0)) - float(item.get('igst_amount', 0))
            cgst_amt = float(item.get('cgst_amount', 0))
            sgst_amt = float(item.get('sgst_amount', 0))
            igst_amt = float(item.get('igst_amount', 0))
            cgst_r = float(item.get('cgst_rate', 0))
            sgst_r = float(item.get('sgst_rate', 0))
            igst_r = float(item.get('igst_rate', 0))
            
            if hsn not in hsn_summary:
                hsn_summary[hsn] = {'taxable': 0.0, 'cgst': 0.0, 'sgst': 0.0, 'igst': 0.0, 'cgst_rate': cgst_r, 'sgst_rate': sgst_r, 'igst_rate': igst_r}
            hsn_summary[hsn]['taxable'] += taxable
            hsn_summary[hsn]['cgst'] += cgst_amt
            hsn_summary[hsn]['sgst'] += sgst_amt
            hsn_summary[hsn]['igst'] += igst_amt
            
            gst_analysis_headers = [
            [Paragraph("<b>HSN/ SAC</b>", bold_style), Paragraph("<b>Taxable amount</b>", bold_style), Paragraph("<b>CGST</b>", bold_style), "", Paragraph("<b>SGST</b>", bold_style), "", Paragraph("<b>Total Tax Amount</b>", bold_style)],
            ["", "", Paragraph("Rate", normal_style), Paragraph("Amount", normal_style), Paragraph("Rate", normal_style), Paragraph("Amount", normal_style), ""]
        ]
        
        for hsn, val in hsn_summary.items():
            tot_tax = val['cgst'] + val['sgst'] + val['igst']
            gst_analysis_headers.append([
                Paragraph(hsn, normal_style),
                Paragraph(f"{RUPEE} {val['taxable']:,.2f}", right_style),
                Paragraph(f"{val['cgst_rate']:.0f}%", right_style),
                Paragraph(f"{RUPEE} {val['cgst']:,.2f}", right_style),
                Paragraph(f"{val['sgst_rate']:.0f}%", right_style),
                Paragraph(f"{RUPEE} {val['sgst']:,.2f}", right_style),
                Paragraph(f"{RUPEE} {tot_tax:,.2f}", right_style),
            ])
            
        gst_analysis_headers.append([
            Paragraph("<b>Total</b>", bold_style),
            Paragraph(f"<b>{RUPEE} {float(subtotal):,.2f}</b>", bold_right),
            "",
            Paragraph(f"<b>{RUPEE} {float(cgst):,.2f}</b>", bold_right),
            "",
            Paragraph(f"<b>{RUPEE} {float(sgst):,.2f}</b>", bold_right),
            Paragraph(f"<b>{RUPEE} {float(cgst + sgst):,.2f}</b>", bold_right)
        ])
        
        gst_analysis_table = Table(gst_analysis_headers, colWidths=[30*mm, 34*mm, 18*mm, 24*mm, 18*mm, 24*mm, 38*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, colors.HexColor('#CCCCCC')),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('SPAN', (0,0), (0,1)),
            ('SPAN', (1,0), (1,1)),
            ('SPAN', (2,0), (3,0)),
            ('SPAN', (4,0), (5,0)),
            ('SPAN', (6,0), (6,1)),
            ('PADDING', (0,0), (-1,-1), 3),
        ])
        elements.append(Spacer(1, 1*mm))
        elements.append(gst_analysis_table)
        
        # Bank Details, Terms & Conditions, Authorized Signatory Block
        if show_bank_details:
            bank_details_str = f"<b>Bank Details</b><br/>Name : {bank_name or 'N/A'}<br/>Account No. : {bank_account_no or 'N/A'}<br/>IFSC code : {bank_ifsc or 'N/A'}<br/>Account holder's name : {company_name}"
        else:
            bank_details_str = ""
        terms_str = f"<b>Terms and conditions</b><br/>{terms or 'Thanks for doing business with us!'}"
        
        sign_label = signee_name if (signee_name and signee_name.strip()) else f"For : {company_name}"
        sign_desig = signee_designation if (signee_designation and signee_designation.strip()) else "Authorized Signatory"
        sign_block = f"{sign_label}<br/><br/><br/><br/><b>{sign_desig}</b>"
        
        bottom_grid = Table([
            [Paragraph(bank_details_str, normal_style), Paragraph(terms_str, normal_style), Paragraph(sign_block, center_style)]
        ], colWidths=[66*mm, 56*mm, 64*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, tally_border),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6)
        ])
        elements.append(Spacer(1, 1*mm))
        elements.append(bottom_grid)

    # Render A4 Classic Blue Grid Layout (Format 3 - JOT Style with continuous vertical lines)
    elif template == "classic_blue":
        classic_primary = colors.HexColor('#0088CC')
        classic_border = colors.HexColor('#99CCFF')
        
        # Center company header
        elements.append(Paragraph(f"<font size=16 color='{classic_primary.hexval()}'><b>{company_name}</b></font>", center_style))
        if company_address:
            elements.append(Paragraph(company_address, center_style))
        elements.append(Paragraph(f"Tel: {company_phone} | Email: {company_email} | GSTIN: {company_gstin or 'N/A'}", center_style))
        elements.append(Spacer(1, 2*mm))
        
        # Header bar
        title_p = Paragraph(f"<b>{doc_type.upper()}</b>", ParagraphStyle('ClassicTitle', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=12, alignment=TA_CENTER, textColor=colors.white))
        elements.append(Table([[title_p]], colWidths=[186*mm], style=[
            ('BACKGROUND', (0,0), (-1,-1), classic_primary),
            ('ALIGN', (0,0), (-1,-1), 'CENTER'),
            ('PADDING', (0,0), (-1,-1), 4)
        ]))
        
        # Metadata and party info in grid
        meta_grid_data = [
            [Paragraph(f"<b>Invoice No:</b> {invoice_number}", normal_style), Paragraph(f"<b>Billed To:</b> {customer_name}", normal_style)],
            [Paragraph(f"<b>Date:</b> {issue_date}", normal_style), Paragraph(f"<b>Address:</b> {customer_address or 'N/A'}", normal_style)],
            [Paragraph(f"<b>Due Date:</b> {due_date}", normal_style), Paragraph(f"<b>GSTIN:</b> {customer_gstin or 'Unregistered'}", normal_style)],
        ]
        elements.append(Table(meta_grid_data, colWidths=[93*mm, 93*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, classic_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, classic_border),
            ('PADDING', (0,0), (-1,-1), 4)
        ]))
        elements.append(Spacer(1, 4*mm))
        
        # Classic Items Table. To make the vertical lines run all the way down, we pad the table with empty lines if needed.
        table_headers = ['S.No.', 'Description', 'Qty', rate_header, 'Amount']
        grid_data = [[Paragraph(f"<b>{h}</b>", bold_style) for h in table_headers]]
        for i, item in enumerate(items, 1):
            desc = item.get('description') or item.get('product_name') or 'N/A'
            qty = float(item.get('quantity', 0))
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            grid_data.append([
                Paragraph(str(i), normal_style),
                Paragraph(desc, normal_style),
                Paragraph(f"{qty:.0f}", normal_style),
                Paragraph(f"{rate:.2f}", normal_style),
                Paragraph(f"{amt:.2f}", normal_style)
            ])
        
        # Padding rows to ensure classic Tally / Vyapar look where grid lines run to the bottom
        target_rows = 8
        if len(items) < target_rows:
            for _ in range(target_rows - len(items)):
                grid_data.append([Paragraph("", normal_style), Paragraph("", normal_style), Paragraph("", normal_style), Paragraph("", normal_style), Paragraph("", normal_style)])
                
        items_table = Table(grid_data, colWidths=[15*mm, 101*mm, 20*mm, 25*mm, 25*mm], style=[
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#EBF5FB')),
            ('BOX', (0,0), (-1,-1), 1, classic_primary),
            ('INNERGRID', (0,0), (-1,-1), 0.5, classic_border),
            ('PADDING', (0,0), (-1,-1), 6),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ])
        elements.append(items_table)
        elements.append(Spacer(1, 4*mm))
        
        # Totals and bank
        bank_details_str = f"<b>Bank Details:</b><br/>Bank: {bank_name or 'N/A'}<br/>A/c No: {bank_account_no or 'N/A'}<br/>IFSC: {bank_ifsc or 'N/A'}"
        totals_col = [
            [Paragraph("Subtotal:", normal_style), Paragraph(f"Rs. {subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"Rs. {cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"Rs. {sgst:.2f}", right_style)],
            [Paragraph("<b>Grand Total:</b>", bold_style), Paragraph(f"<b>Rs. {total:.2f}</b>", bold_right)],
        ]
        if has_payments:
            totals_col.append([Paragraph("Amount Paid:", normal_style), Paragraph(f"Rs. {amount_paid:.2f}", right_style)])
            totals_col.append([Paragraph("<b>Balance Due:</b>", bold_style), Paragraph(f"<b>Rs. {balance_due:.2f}</b>", bold_right)])
        totals_table = Table(totals_col, colWidths=[38*mm, 32*mm], style=[('PADDING', (0,0), (-1,-1), 2)])
        
        summary_table = Table([[Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]], colWidths=[78*mm, 32*mm, 76*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, classic_primary),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6)
        ])
        elements.append(summary_table)
        
        elements.append(Spacer(1, 4*mm))
        terms_str = f"<b>Terms & Conditions:</b><br/>{terms or 'Goods once sold are not returnable.'}"
        sign_block = f"<br/>For <b>{company_name}</b><br/><br/>Authorised Signatory"
        bottom_table = Table([[Paragraph(terms_str, caption_style), Paragraph(sign_block, center_style)]], colWidths=[120*mm, 66*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 0),
        ])
        elements.append(bottom_table)

    # Render A4 Sleek Modern Layout (Format 4 - Sleek Bill Style Minimalist Layout)
    elif template == "sleek_modern":
        sleek_primary = colors.HexColor('#0F1B3D')
        sleek_accent = colors.HexColor('#DCA035')
        
        # Elegant header banner
        co_banner = f"<b><font size=16 color='white'>{company_name.upper()}</font></b><br/>"
        if company_address:
            co_banner += f"<font size=9 color='white'>{company_address}</font><br/>"
        co_banner += f"<font size=9 color='white'>GSTIN: {company_gstin or 'N/A'}</font>"
        header_p = Paragraph(co_banner, normal_style)
        title_p = Paragraph(f"<b><font size=16 color='white'>{doc_type.upper()}</font></b><br/><font size=11 color='white'>#{invoice_number}</font>", ParagraphStyle('SleekTitle', parent=styles['Normal'], alignment=TA_RIGHT))
        
        banner_table = Table([[header_p, title_p]], colWidths=[100*mm, 86*mm], style=[
            ('BACKGROUND', (0,0), (-1,-1), sleek_primary),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('PADDING', (0,0), (-1,-1), 12)
        ])
        elements.append(banner_table)
        elements.append(Spacer(1, 6*mm))
        
        # Metadata
        meta_left = f"<b>Date:</b> {issue_date}<br/><b>Due Date:</b> {due_date}<br/><b>Place of Supply:</b> {display_pos_code or 'N/A'}"
        addr_str = f"<br/>{customer_address}" if customer_address else ""
        meta_right = f"<b>Billed To:</b><br/>{customer_name}{addr_str}<br/>GSTIN: {customer_gstin or 'Unregistered'}"
        
        meta_table = Table([[Paragraph(meta_left, normal_style), Paragraph(meta_right, normal_style)]], colWidths=[93*mm, 93*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 0)
        ])
        elements.append(meta_table)
        elements.append(Spacer(1, 6*mm))
        
        # Clean items table (alternating rows, no vertical borders)
        table_headers = ['Description', 'Qty', 'Rate', 'Amount']
        grid_data = [[Paragraph(f"<b>{h}</b>", bold_style) for h in table_headers]]
        for i, item in enumerate(items, 1):
            desc = item.get('description') or item.get('product_name') or 'N/A'
            qty = float(item.get('quantity', 0))
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            grid_data.append([
                Paragraph(desc, normal_style),
                Paragraph(f"{qty:.0f}", normal_style),
                Paragraph(f"{rate:.2f}", normal_style),
                Paragraph(f"{amt:.2f}", normal_style)
            ])
            
        t_style = [
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#F8FAFC')),
            ('LINEBELOW', (0,0), (-1,0), 2, sleek_accent),
            ('LINEBELOW', (0,1), (-1,-1), 0.5, colors.HexColor('#E2E8F0')),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('PADDING', (0,0), (-1,-1), 6),
        ]
        
        # Zebra striping
        for r in range(1, len(grid_data)):
            if r % 2 == 0:
                t_style.append(('BACKGROUND', (0,r), (-1,r), colors.HexColor('#F8FAFC')))
                
        items_table = Table(grid_data, colWidths=[116*mm, 20*mm, 25*mm, 25*mm], style=t_style)
        elements.append(items_table)
        elements.append(Spacer(1, 6*mm))
        
        # Totals alignment
        bank_details_str = f"<b>Payment Details:</b><br/>Bank: {bank_name or 'N/A'}<br/>A/c No: {bank_account_no or 'N/A'}<br/>IFSC: {bank_ifsc or 'N/A'}"
        totals_col = [
            [Paragraph("Subtotal:", normal_style), Paragraph(f"Rs. {subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"Rs. {cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"Rs. {sgst:.2f}", right_style)],
            [Paragraph("<font size=11><b>Amount Due:</b></font>", bold_style), Paragraph(f"<font size=11><b>Rs. {total:.2f}</b></font>", bold_right)],
        ]
        if has_payments:
            totals_col.append([Paragraph("Amount Paid:", normal_style), Paragraph(f"Rs. {amount_paid:.2f}", right_style)])
            totals_col.append([Paragraph("<b>Balance Due:</b>", bold_style), Paragraph(f"<b>Rs. {balance_due:.2f}</b>", bold_right)])
        totals_table = Table(totals_col, colWidths=[38*mm, 32*mm], style=[
            ('PADDING', (0,0), (-1,-1), 2),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE')
        ])
        
        summary_table = Table([[Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]], colWidths=[78*mm, 32*mm, 76*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6)
        ])
        elements.append(summary_table)
        elements.append(Spacer(1, 6*mm))
        
        # Footer
        terms_str = f"<b>Terms & Conditions:</b><br/>{terms or 'Thank you for your business!'}"
        sign_block = f"<br/><br/><b>{company_name.upper()}</b><br/><br/>Authorized Signature"
        bottom_table = Table([[Paragraph(terms_str, caption_style), Paragraph(sign_block, right_style)]], colWidths=[120*mm, 66*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ])
        elements.append(bottom_table)

    # Render Minimal Layout (clean, black & white, no borders)
    elif template == "minimal":
        elements.append(Paragraph(company_name, company_title))
        if company_address:
            elements.append(Paragraph(company_address, center_style))
        elements.append(Spacer(1, 4*mm))

        # Simple meta
        cust_str = f"Customer: {customer_name}"
        if customer_address:
            cust_str += f"<br/>{customer_address}"
        meta = [
            [Paragraph(f"<b>{doc_type}:</b> {invoice_number}", bold_style), Paragraph(f"Date: {issue_date}", normal_style)],
            [Paragraph(cust_str, normal_style), Paragraph(f"Due: {due_date}", normal_style)],
        ]
        if customer_gstin:
            meta.append([Paragraph(f"GSTIN: {customer_gstin}", normal_style), ""])
        meta_table = Table(meta, colWidths=[93*mm, 93*mm], style=[('PADDING', (0,0), (-1,-1), 3)])
        elements.append(meta_table)
        elements.append(Spacer(1, 6*mm))

        # Minimal items table — no vertical borders, only horizontal lines
        grid_data = [[Paragraph(f"<b>{h}</b>", bold_style) for h in ['Description', 'Qty', 'Rate', 'Amount']]]
        for item in items:
            desc = item.get('description') or item.get('product_name') or 'N/A'
            qty = float(item.get('quantity', 0))
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            grid_data.append([
                Paragraph(desc, normal_style),
                Paragraph(f"{qty:.0f}", normal_style),
                Paragraph(f"{rate:.2f}", normal_style),
                Paragraph(f"{amt:.2f}", normal_style),
            ])
        items_table = Table(grid_data, colWidths=[106*mm, 20*mm, 25*mm, 25*mm], style=[
            ('LINEBELOW', (0,0), (-1,0), 1, primary_color),
            ('LINEBELOW', (0,1), (-1,-1), 0.5, border_color),
            ('PADDING', (0,0), (-1,-1), 4),
        ])
        elements.append(items_table)
        elements.append(Spacer(1, 6*mm))

        # Totals right-aligned
        totals_col = [
            [Paragraph("Subtotal:", normal_style), Paragraph(f"₹{subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"₹{cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"₹{sgst:.2f}", right_style)],
            [Paragraph("<b>Total:</b>", bold_style), Paragraph(f"<b>₹{total:.2f}</b>", bold_right)],
        ]
        if has_payments:
            totals_col.append([Paragraph("Amount Paid:", normal_style), Paragraph(f"₹{amount_paid:.2f}", right_style)])
            totals_col.append([Paragraph("<b>Balance Due:</b>", bold_style), Paragraph(f"<b>₹{balance_due:.2f}</b>", bold_right)])
        totals_table = Table(totals_col, colWidths=[40*mm, 35*mm], style=[('PADDING', (0,0), (-1,-1), 2)])
        elements.append(Table([["", totals_table]], colWidths=[111*mm, 75*mm], style=[('ALIGN', (1,0), (1,0), 'RIGHT')]))
        elements.append(Spacer(1, 8*mm))
        elements.append(Paragraph("Thank you.", center_style))

    # Render Elegant Layout (green accent, softer)
    elif template == "elegant":
        # Header with green accent line
        elements.append(Table([[""]], colWidths=[186*mm], style=[
            ('BACKGROUND', (0,0), (-1,-1), primary_color),
            ('PADDING', (0,0), (-1,-1), 3),
        ]))
        elements.append(Spacer(1, 2*mm))
        elements.append(Paragraph(company_name, company_title))
        if company_address:
            elements.append(Paragraph(company_address, center_style))
        if company_gstin:
            elements.append(Paragraph(f"GSTIN: {company_gstin}", center_style))
        elements.append(Spacer(1, 4*mm))

        # Two-column info
        cust_addr_str = f"<br/>{customer_address}" if customer_address else ""
        info_row = [
            [
                Paragraph(f"<b>Billed To</b><br/>{customer_name}{cust_addr_str}<br/>GSTIN: {customer_gstin or 'Unregistered'}", normal_style),
                Paragraph(f"<b>{doc_type}</b><br/>No: {invoice_number}<br/>Date: {issue_date}<br/>Due: {due_date}", normal_style),
            ]
        ]
        info_table = Table(info_row, colWidths=[93*mm, 93*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6),
        ])
        elements.append(info_table)
        elements.append(Spacer(1, 4*mm))

        # Items
        grid_data = [[Paragraph(f"<b>{h}</b>", bold_style) for h in ['S.No.', 'Description', 'Qty', 'Rate', 'Amount']]]
        for i, item in enumerate(items, 1):
            desc = item.get('description') or item.get('product_name') or 'N/A'
            qty = float(item.get('quantity', 0))
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            grid_data.append([
                Paragraph(str(i), normal_style),
                Paragraph(desc, normal_style),
                Paragraph(f"{qty:.0f}", normal_style),
                Paragraph(f"{rate:.2f}", normal_style),
                Paragraph(f"{amt:.2f}", normal_style),
            ])
        items_table = Table(grid_data, colWidths=[15*mm, 101*mm, 20*mm, 25*mm, 25*mm], style=[
            ('BACKGROUND', (0,0), (-1,0), table_header_bg),
            ('LINEBELOW', (0,0), (-1,0), 1.5, primary_color),
            ('LINEBELOW', (0,1), (-1,-1), 0.5, border_color),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('PADDING', (0,0), (-1,-1), 4),
        ])
        elements.append(items_table)
        elements.append(Spacer(1, 4*mm))

        # Totals
        totals_col = [
            [Paragraph("Subtotal:", normal_style), Paragraph(f"₹{subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"₹{cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"₹{sgst:.2f}", right_style)],
            [Paragraph("<b>Total:</b>", bold_style), Paragraph(f"<b>₹{total:.2f}</b>", bold_right)],
        ]
        if has_payments:
            totals_col.append([Paragraph("Amount Paid:", normal_style), Paragraph(f"₹{amount_paid:.2f}", right_style)])
            totals_col.append([Paragraph("<b>Balance Due:</b>", bold_style), Paragraph(f"<b>₹{balance_due:.2f}</b>", bold_right)])
        totals_table = Table(totals_col, colWidths=[40*mm, 35*mm])
        elements.append(Table([["", totals_table]], colWidths=[111*mm, 75*mm], style=[('ALIGN', (1,0), (1,0), 'RIGHT')]))
        elements.append(Spacer(1, 6*mm))
        sign_block = f"<br/><br/>For <b>{company_name}</b><br/><br/>Authorised Signatory"
        elements.append(Paragraph(sign_block, right_style))

    # Render A4 Modern Layout (Self Learning Indigo Layout)
    else:
        # Side-by-side header
        header_table_data = [
            [
                Paragraph(company_name.upper(), company_title),
                Paragraph(f"<b>{doc_type.upper()}</b><br/>No: {invoice_number}<br/>Date: {issue_date}", normal_style)
            ]
        ]
        header_table = Table(header_table_data, colWidths=[110*mm, 76*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6),
        ])
        elements.append(header_table)
        elements.append(Spacer(1, 2*mm))

        # Double column meta details
        cust_addr_str = f"<br/>{customer_address}" if customer_address else ""
        metadata_row = [
            [
                Paragraph(f"<b>Bill To:</b><br/>{customer_name}{cust_addr_str}<br/>GSTIN: {customer_gstin or 'N/A'}", normal_style),
                Paragraph(f"<b>Company Details:</b><br/>GSTIN: {company_gstin or 'N/A'}<br/>PAN: {company_pan or 'N/A'}<br/>{company_address}", normal_style)
            ]
        ]
        meta_grid = Table(metadata_row, colWidths=[93*mm, 93*mm], style=[
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#EEF2F6')),
            ('BOX', (0,0), (-1,-1), 0.5, border_color),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6),
        ])
        elements.append(meta_grid)
        elements.append(Spacer(1, 4*mm))

        # Items Table
        table_headers = ['S.No.', 'Description', 'Qty', 'Rate', 'Amount']
        grid_data = [[Paragraph(f"<b>{h}</b>", bold_style) for h in table_headers]]
        for i, item in enumerate(items, 1):
            desc = item.get('description') or item.get('product_name') or 'N/A'
            qty = float(item.get('quantity', 0))
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            grid_data.append([
                Paragraph(str(i), normal_style),
                Paragraph(desc, normal_style),
                Paragraph(f"{qty:.0f}", normal_style),
                Paragraph(f"{rate:.2f}", normal_style),
                Paragraph(f"{amt:.2f}", normal_style)
            ])
            
        items_table = Table(grid_data, colWidths=[15*mm, 101*mm, 20*mm, 25*mm, 25*mm], style=[
            ('BACKGROUND', (0,0), (-1,0), table_header_bg),
            ('LINEBELOW', (0,0), (-1,0), 1.5, primary_color),
            ('LINEBELOW', (0,1), (-1,-1), 0.5, border_color),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('PADDING', (0,0), (-1,-1), 5),
        ])
        elements.append(items_table)
        elements.append(Spacer(1, 4*mm))

        # Bank, QR and Totals
        bank_details_str = f"<b>Bank Details:</b><br/>Bank: {bank_name or 'N/A'}<br/>A/c No: {bank_account_no or 'N/A'}<br/>IFSC: {bank_ifsc or 'N/A'}"
        totals_col = [
            [Paragraph("Subtotal:", normal_style), Paragraph(f"Rs. {subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"Rs. {cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"Rs. {sgst:.2f}", right_style)],
            [Paragraph("Total Amount:", bold_style), Paragraph(f"Rs. {total:.2f}", bold_right)],
        ]
        if has_payments:
            totals_col.append([Paragraph("Amount Paid:", normal_style), Paragraph(f"Rs. {amount_paid:.2f}", right_style)])
            totals_col.append([Paragraph("<b>Balance Due:</b>", bold_style), Paragraph(f"<b>Rs. {balance_due:.2f}</b>", bold_right)])
        totals_table = Table(totals_col, colWidths=[38*mm, 32*mm], style=[
            ('PADDING', (0,0), (-1,-1), 2),
        ])

        summary_row = [
            [Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]
        ]
        summary_table = Table(summary_row, colWidths=[78*mm, 32*mm, 76*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6),
        ])
        elements.append(summary_table)

        elements.append(Spacer(1, 4*mm))
        terms_str = f"<b>Terms & Conditions:</b><br/>{terms or 'Please pay invoice by due date.'}"
        sign_block = f"<br/><br/>For <b>{company_name}</b><br/><br/>Authorised Signatory"
        bottom_table = Table([[Paragraph(terms_str, caption_style), Paragraph(sign_block, center_style)]], colWidths=[120*mm, 66*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ])
        elements.append(bottom_table)
    doc.build(elements)
    return buffer.getvalue()


def generate_party_statement_pdf(
    statement,  # PartyStatementResponse model or dict
    company_name: str,
    company_address: Optional[str] = None,
    company_gstin: Optional[str] = None,
    company_phone: Optional[str] = None,
) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=12*mm,
        rightMargin=12*mm,
        topMargin=12*mm,
        bottomMargin=12*mm
    )

    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')  # Deep Navy Blue
    text_color = colors.HexColor('#1E293B')
    muted_color = colors.HexColor('#475569')
    table_header_bg = colors.HexColor('#E2E8F0')
    border_color = colors.HexColor('#94A3B8')

    title_style = ParagraphStyle(
        'RepTitle',
        parent=styles['Heading1'],
        fontName='Helvetica-Bold',
        fontSize=18,
        leading=22,
        textColor=primary_color,
        alignment=TA_CENTER
    )

    bold_style = ParagraphStyle(
        'RepBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=9,
        leading=11,
        textColor=text_color
    )

    normal_style = ParagraphStyle(
        'RepNormal',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9,
        leading=11,
        textColor=text_color
    )

    right_style = ParagraphStyle(
        'RepRight',
        parent=normal_style,
        alignment=TA_RIGHT
    )

    right_bold_style = ParagraphStyle(
        'RepRightBold',
        parent=bold_style,
        alignment=TA_RIGHT
    )

    center_style = ParagraphStyle(
        'RepCenter',
        parent=normal_style,
        alignment=TA_CENTER
    )

    # 1. Header Title
    elements.append(Paragraph("Party Statement", title_style))
    elements.append(Spacer(1, 6*mm))

    # 2. Company & Party Details Table
    co_addr = company_address or "N/A"
    co_gst = f"GSTIN: {company_gstin}" if company_gstin else "GSTIN: N/A"
    co_ph = f"Mobile: {company_phone}" if company_phone else ""

    party_name = statement.contact_name
    party_addr = statement.address or "N/A"
    party_gst = f"GSTIN: {statement.gstin}" if statement.gstin else "GSTIN: N/A"
    party_ph = f"Mobile: {statement.phone}" if statement.phone else "Mobile: N/A"

    details_data = [
        [
            Paragraph(f"<b>From:</b><br/>{company_name}<br/>{co_addr}<br/>{co_gst}<br/>{co_ph}", normal_style),
            Paragraph(f"<b>To (Party Details):</b><br/>{party_name}<br/>{party_addr}<br/>{party_gst}<br/>{party_ph}", normal_style)
        ]
    ]
    details_table = Table(details_data, colWidths=[93*mm, 93*mm], style=[
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ('PADDING', (0,0), (-1,-1), 0),
    ])
    elements.append(details_table)
    elements.append(Spacer(1, 4*mm))

    # Period
    start_str = statement.start_date.strftime("%d-%b-%Y")
    end_str = statement.end_date.strftime("%d-%b-%Y")
    elements.append(Paragraph(f"<b>Statement Period:</b> {start_str} to {end_str}", normal_style))
    elements.append(Spacer(1, 4*mm))

    # 3. Ledger Table
    ledger_header = [
        Paragraph("<b>Date</b>", normal_style),
        Paragraph("<b>Particulars</b>", normal_style),
        Paragraph("<b>Voucher Type</b>", normal_style),
        Paragraph("<b>Voucher No.</b>", normal_style),
        Paragraph("<b>Debit (₹)</b>", right_style),
        Paragraph("<b>Credit (₹)</b>", right_style),
        Paragraph("<b>Balance (₹)</b>", right_style),
    ]

    ledger_data = [ledger_header]
    for row in statement.ledger:
        date_str = row.date.strftime("%d-%b-%Y")
        deb_val = f"{row.debit:,.2f}" if row.debit is not None else "-"
        cred_val = f"{row.credit:,.2f}" if row.credit is not None else "-"
        
        ledger_data.append([
            Paragraph(date_str, normal_style),
            Paragraph(row.particulars, normal_style),
            Paragraph(row.voucher_type, normal_style),
            Paragraph(row.voucher_no, normal_style),
            Paragraph(deb_val, right_style),
            Paragraph(cred_val, right_style),
            Paragraph(row.balance, right_style),
        ])

    ledger_table = Table(ledger_data, colWidths=[24*mm, 36*mm, 24*mm, 26*mm, 24*mm, 24*mm, 28*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.2, primary_color),
        ('LINEBELOW', (0,1), (-1,-1), 0.5, border_color),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('PADDING', (0,0), (-1,-1), 4),
    ])
    elements.append(ledger_table)
    elements.append(Spacer(1, 6*mm))

    # 4. Summary section
    elements.append(Paragraph("<b>Summary</b>", bold_style))
    elements.append(Spacer(1, 2*mm))

    summary = statement.summary
    summary_data = [
        [Paragraph("<b>Particulars</b>", normal_style), Paragraph("<b>Amount (₹)</b>", right_style)],
        [Paragraph("Opening Balance", normal_style), Paragraph(f"{summary.opening_balance:,.2f}", right_style)],
    ]
    
    # Conditionally add sales/receipts or purchases/payments based on contact type/non-zero values
    if statement.contact_type in ["CUSTOMER", "BOTH"] or summary.total_sales > 0 or summary.total_receipts > 0:
        summary_data.append([Paragraph("Total Sales", normal_style), Paragraph(f"{summary.total_sales:,.2f}", right_style)])
        summary_data.append([Paragraph("Total Receipts", normal_style), Paragraph(f"{summary.total_receipts:,.2f}", right_style)])

    if statement.contact_type in ["VENDOR", "BOTH"] or summary.total_purchases > 0 or summary.total_payments > 0:
        summary_data.append([Paragraph("Total Purchases", normal_style), Paragraph(f"{summary.total_purchases:,.2f}", right_style)])
        summary_data.append([Paragraph("Total Payments", normal_style), Paragraph(f"{summary.total_payments:,.2f}", right_style)])

    summary_data.append([Paragraph("<b>Closing Outstanding</b>", bold_style), Paragraph(f"<b>{summary.closing_outstanding:,.2f}</b>", right_bold_style)])

    summary_table = Table(summary_data, colWidths=[80*mm, 40*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.0, primary_color),
        ('LINEBELOW', (0,1), (-1,-1), 0.5, border_color),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('PADDING', (0,0), (-1,-1), 4),
    ])
    elements.append(summary_table)

    summary_data.append([Paragraph("<b>Closing Outstanding</b>", bold_style), Paragraph(f"<b>{summary.closing_outstanding:,.2f}</b>", right_bold_style)])

    summary_table = Table(summary_data, colWidths=[80*mm, 40*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.0, primary_color),
        ('LINEBELOW', (0,1), (-1,-1), 0.5, border_color),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('PADDING', (0,0), (-1,-1), 4),
    ])
    elements.append(summary_table)

    doc.build(elements)
    return buffer.getvalue()


def generate_balance_sheet_pdf(data, company_name: str, cutoff: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    table_header_bg = colors.HexColor('#E2E8F0')
    border_color = colors.HexColor('#94A3B8')

    title_style = ParagraphStyle('BSTitle', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('BSSubtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('BSBold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=9, leading=11, textColor=text_color)
    normal_style = ParagraphStyle('BSNormal', parent=styles['Normal'], fontName='Helvetica', fontSize=9, leading=11, textColor=text_color)
    right_style = ParagraphStyle('BSRight', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('BSRightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph(f"Balance Sheet as on {cutoff}", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    # Equation
    elements.append(Table([[Paragraph("<b>Assets = Liabilities + Equity</b>", ParagraphStyle('BSEq', parent=bold_style, alignment=TA_CENTER))]], colWidths=[186*mm], style=[
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F1F5F9')),
        ('PADDING', (0,0), (-1,-1), 6),
        ('BOX', (0,0), (-1,-1), 1, border_color)
    ]))
    elements.append(Spacer(1, 4*mm))

    assets_data = data.get("assets", {})
    liabilities_data = data.get("liabilities", {})
    equity_data = data.get("equity", {})
    sections = [
        ("ASSETS", assets_data.get("items", []) if isinstance(assets_data, dict) else [], float(assets_data.get("total", 0) if isinstance(assets_data, dict) else 0)),
        ("LIABILITIES", liabilities_data.get("items", []) if isinstance(liabilities_data, dict) else [], float(liabilities_data.get("total", 0) if isinstance(liabilities_data, dict) else 0)),
        ("EQUITY", equity_data.get("items", []) if isinstance(equity_data, dict) else [], float(equity_data.get("total", 0) if isinstance(equity_data, dict) else 0))
    ]

    for title, items, total in sections:
        table_data = [[Paragraph(f"<b>{title}</b>", bold_style), ""]]
        for item in items:
            if isinstance(item, dict):
                name = item.get("account_name", "")
                code = item.get("account_code", "")
                bal = float(item.get("balance", 0))
            else:
                name = item.account_name
                code = item.account_code
                bal = float(item.balance)
            table_data.append([
                Paragraph(f"{name} ({code})" if code and code != "--" else name, normal_style),
                Paragraph(f"₹{bal:,.2f}", right_style)
            ])
        table_data.append([Paragraph(f"<b>Total {title.title()}</b>", bold_style), Paragraph(f"<b>₹{total:,.2f}</b>", right_bold_style)])

        t = Table(table_data, colWidths=[130*mm, 56*mm], style=[
            ('LINEBELOW', (0,0), (-1,0), 1.0, primary_color),
            ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
            ('LINEABOVE', (0,-1), (-1,-1), 1.0, primary_color),
            ('PADDING', (0,0), (-1,-1), 4),
        ])
        elements.append(t)
        elements.append(Spacer(1, 4*mm))

    doc.build(elements)
    return buffer.getvalue()


def generate_profit_loss_pdf(data, company_name: str, start: str, end: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    border_color = colors.HexColor('#94A3B8')

    title_style = ParagraphStyle('PLTitle', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('PLSubtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('PLBold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=9, leading=11, textColor=text_color)
    normal_style = ParagraphStyle('PLNormal', parent=styles['Normal'], fontName='Helvetica', fontSize=9, leading=11, textColor=text_color)
    right_style = ParagraphStyle('PLRight', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('PLRightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph(f"Profit & Loss Statement ({start} to {end})", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    # Revenue
    rev_data = [[Paragraph("<b>REVENUE</b>", bold_style), ""]]
    rev_items = data.get("revenue_lines") or []
    for item in rev_items:
        name = item.get("account_name") or item.account_name
        amt = float(item.get("amount") or item.amount)
        rev_data.append([Paragraph(name, normal_style), Paragraph(f"₹{amt:,.2f}", right_style)])
    rev_total = float(data.get("total_revenue", 0))
    rev_data.append([Paragraph("<b>Total Revenue</b>", bold_style), Paragraph(f"<b>₹{rev_total:,.2f}</b>", right_bold_style)])

    elements.append(Table(rev_data, colWidths=[130*mm, 56*mm], style=[
        ('LINEBELOW', (0,0), (-1,0), 1.0, primary_color),
        ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
        ('LINEABOVE', (0,-1), (-1,-1), 1.0, primary_color),
        ('PADDING', (0,0), (-1,-1), 4),
    ]))
    elements.append(Spacer(1, 6*mm))

    # Expenses
    exp_data = [[Paragraph("<b>EXPENSES</b>", bold_style), ""]]
    exp_items = data.get("expense_lines") or []
    for item in exp_items:
        name = item.get("account_name") or item.account_name
        amt = float(item.get("amount") or item.amount)
        exp_data.append([Paragraph(name, normal_style), Paragraph(f"₹{amt:,.2f}", right_style)])
    exp_total = float(data.get("total_expenses", 0))
    exp_data.append([Paragraph("<b>Total Expenses</b>", bold_style), Paragraph(f"<b>₹{exp_total:,.2f}</b>", right_bold_style)])

    elements.append(Table(exp_data, colWidths=[130*mm, 56*mm], style=[
        ('LINEBELOW', (0,0), (-1,0), 1.0, primary_color),
        ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
        ('LINEABOVE', (0,-1), (-1,-1), 1.0, primary_color),
        ('PADDING', (0,0), (-1,-1), 4),
    ]))
    elements.append(Spacer(1, 6*mm))

    # Net Profit
    net_profit = float(data.get("net_profit", 0))
    elements.append(Table([[Paragraph("<b>NET PROFIT / (LOSS)</b>", bold_style), Paragraph(f"<b>₹{net_profit:,.2f}</b>", right_bold_style)]], colWidths=[130*mm, 56*mm], style=[
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#ECFDF5') if net_profit >= 0 else colors.HexColor('#FEF2F2')),
        ('PADDING', (0,0), (-1,-1), 8),
        ('BOX', (0,0), (-1,-1), 1, primary_color)
    ]))

    doc.build(elements)
    return buffer.getvalue()


def generate_trial_balance_pdf(data, company_name: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    border_color = colors.HexColor('#94A3B8')
    table_header_bg = colors.HexColor('#E2E8F0')

    title_style = ParagraphStyle('TBTitle', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('TBSubtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('TBBold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=9, leading=11, textColor=text_color)
    normal_style = ParagraphStyle('TBNormal', parent=styles['Normal'], fontName='Helvetica', fontSize=9, leading=11, textColor=text_color)
    right_style = ParagraphStyle('TBRight', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('TBRightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph("Trial Balance", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    tb_headers = [
        Paragraph("<b>Account Code</b>", bold_style),
        Paragraph("<b>Account Name</b>", bold_style),
        Paragraph("<b>Opening (₹)</b>", right_bold_style),
        Paragraph("<b>Debits (₹)</b>", right_bold_style),
        Paragraph("<b>Credits (₹)</b>", right_bold_style),
        Paragraph("<b>Closing (₹)</b>", right_bold_style)
    ]
    tb_data = [tb_headers]
    for line in data.get("lines", []):
        code = line.get("account_code") or line.account_code or ""
        name = line.get("account_name") or line.account_name or ""
        op = float(line.get("opening_balance") or line.opening_balance or 0)
        deb = float(line.get("total_debits") or line.total_debits or 0)
        cred = float(line.get("total_credits") or line.total_credits or 0)
        cl = float(line.get("closing_balance") or line.closing_balance or 0)
        
        tb_data.append([
            Paragraph(code, normal_style),
            Paragraph(name, normal_style),
            Paragraph(f"{op:,.2f}", right_style),
            Paragraph(f"{deb:,.2f}", right_style),
            Paragraph(f"{cred:,.2f}", right_style),
            Paragraph(f"{cl:,.2f}", right_style)
        ])

    tb_data.append([
        "", Paragraph("<b>Total</b>", bold_style),
        Paragraph(f"<b>{float(data.get('total_opening_debits', 0)):,.2f} Dr</b>", right_bold_style),
        Paragraph(f"<b>{float(data.get('total_debits', 0)):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.get('total_credits', 0)):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.get('total_closing_debits', 0)):,.2f} Dr</b>", right_bold_style)
    ])

    elements.append(Table(tb_data, colWidths=[25*mm, 45*mm, 28*mm, 28*mm, 28*mm, 32*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.2, primary_color),
        ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
        ('LINEABOVE', (0,-1), (-1,-1), 1.2, primary_color),
        ('PADDING', (0,0), (-1,-1), 4),
    ]))

    doc.build(elements)
    return buffer.getvalue()


def generate_cash_flow_pdf(data, company_name: str, start: str, end: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    border_color = colors.HexColor('#94A3B8')

    title_style = ParagraphStyle('CFTitle', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('CFSubtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('CFBold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=9, leading=11, textColor=text_color)
    normal_style = ParagraphStyle('CFNormal', parent=styles['Normal'], fontName='Helvetica', fontSize=9, leading=11, textColor=text_color)
    right_style = ParagraphStyle('CFRight', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('CFRightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph(f"Cash Flow Statement ({start} to {end})", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    sections = ["operating_activities", "investing_activities", "financing_activities"]
    for s_key in sections:
        s_data = data.get(s_key, {})
        section_name = s_data.get("section") or s_key.replace("_", " ").title()
        table_data = [[Paragraph(f"<b>{section_name}</b>", bold_style), ""]]
        
        for item in s_data.get("items", []):
            label = item.get("label") or item.label
            amount = float(item.get("amount") or item.amount)
            table_data.append([Paragraph(label, normal_style), Paragraph(f"₹{amount:,.2f}", right_style)])
            
        net = float(s_data.get("net", 0))
        table_data.append([Paragraph(f"<b>Net Cash from {section_name}</b>", bold_style), Paragraph(f"<b>₹{net:,.2f}</b>", right_bold_style)])
        
        elements.append(Table(table_data, colWidths=[130*mm, 56*mm], style=[
            ('LINEBELOW', (0,0), (-1,0), 1.0, primary_color),
            ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
            ('LINEABOVE', (0,-1), (-1,-1), 1.0, primary_color),
            ('PADDING', (0,0), (-1,-1), 4),
        ]))
        elements.append(Spacer(1, 4*mm))

    # Final reconciliation
    reconcil = [
        [Paragraph("Net Change in Cash", bold_style), Paragraph(f"₹{float(data.get('net_change_in_cash', 0)):,.2f}", right_bold_style)],
        [Paragraph("Opening Cash Balance", normal_style), Paragraph(f"₹{float(data.get('opening_cash_balance', 0)):,.2f}", right_style)],
        [Paragraph("<b>Closing Cash Balance</b>", bold_style), Paragraph(f"<b>₹{float(data.get('closing_cash_balance', 0)):,.2f}</b>", right_bold_style)],
    ]
    elements.append(Table(reconcil, colWidths=[130*mm, 56*mm], style=[
        ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F8FAFC')),
        ('BOX', (0,0), (-1,-1), 1, border_color),
        ('LINEBELOW', (0,-1), (-1,-1), 1.5, primary_color),
        ('PADDING', (0,0), (-1,-1), 6),
    ]))

    doc.build(elements)
    return buffer.getvalue()


def generate_aging_pdf(data, company_name: str, as_of: str, report_type: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    border_color = colors.HexColor('#94A3B8')
    table_header_bg = colors.HexColor('#E2E8F0')

    title_style = ParagraphStyle('AGTitle', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('AGSubtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('AGBold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=8, leading=10, textColor=text_color)
    normal_style = ParagraphStyle('AGNormal', parent=styles['Normal'], fontName='Helvetica', fontSize=8, leading=10, textColor=text_color)
    right_style = ParagraphStyle('AGRight', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('AGRightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph(f"{report_type.title()} Aging Report as of {as_of}", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    tb_headers = [
        Paragraph("<b>Contact Name</b>", bold_style),
        Paragraph("<b>0-30 Days (₹)</b>", right_bold_style),
        Paragraph("<b>31-60 Days (₹)</b>", right_bold_style),
        Paragraph("<b>61-90 Days (₹)</b>", right_bold_style),
        Paragraph("<b>91+ Days (₹)</b>", right_bold_style),
        Paragraph("<b>Total (₹)</b>", right_bold_style)
    ]
    tb_data = [tb_headers]
    for line in data.get("lines", []):
        name = line.get("contact_name") or line.contact_name
        buckets = line.get("buckets") or line.buckets
        b_vals = [float(b.get("amount") if isinstance(b, dict) else b.amount) for b in buckets]
        total = float(line.get("total_outstanding") or line.total_outstanding)
        
        tb_data.append([
            Paragraph(name, normal_style),
            Paragraph(f"{b_vals[0]:,.2f}" if b_vals[0] > 0 else "-", right_style),
            Paragraph(f"{b_vals[1]:,.2f}" if b_vals[1] > 0 else "-", right_style),
            Paragraph(f"{b_vals[2]:,.2f}" if b_vals[2] > 0 else "-", right_style),
            Paragraph(f"{b_vals[3]:,.2f}" if b_vals[3] > 0 else "-", right_style),
            Paragraph(f"{total:,.2f}", right_bold_style)
        ])

    b_totals = [float(b.get("amount") if isinstance(b, dict) else b.amount) for b in data.get("bucket_totals", [])]
    grand_total = float(data.get("total_outstanding", 0))
    tb_data.append([
        Paragraph("<b>Total</b>", bold_style),
        Paragraph(f"<b>{b_totals[0]:,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{b_totals[1]:,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{b_totals[2]:,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{b_totals[3]:,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{grand_total:,.2f}</b>", right_bold_style)
    ])

    elements.append(Table(tb_data, colWidths=[56*mm, 26*mm, 26*mm, 26*mm, 26*mm, 26*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.2, primary_color),
        ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
        ('LINEABOVE', (0,-1), (-1,-1), 1.2, primary_color),
        ('PADDING', (0,0), (-1,-1), 4),
    ]))

    doc.build(elements)
    return buffer.getvalue()


def generate_outstanding_pdf(data, company_name: str, as_of: str, report_type: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    border_color = colors.HexColor('#94A3B8')
    table_header_bg = colors.HexColor('#E2E8F0')

    title_style = ParagraphStyle('OSTitle', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('OSSubtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('OSBold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=8, leading=10, textColor=text_color)
    normal_style = ParagraphStyle('OSNormal', parent=styles['Normal'], fontName='Helvetica', fontSize=8, leading=10, textColor=text_color)
    right_style = ParagraphStyle('OSRight', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('OSRightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph(f"Outstanding {report_type.title()} as of {as_of}", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    tb_headers = [
        Paragraph("<b>Ref No.</b>", bold_style),
        Paragraph("<b>Contact Name</b>", bold_style),
        Paragraph("<b>Date</b>", bold_style),
        Paragraph("<b>Due Date</b>", bold_style),
        Paragraph("<b>Total (₹)</b>", right_bold_style),
        Paragraph("<b>Paid (₹)</b>", right_bold_style),
        Paragraph("<b>Outstanding (₹)</b>", right_bold_style)
    ]
    tb_data = [tb_headers]
    items = data.get("invoices") or data.get("bills") or []
    for item in items:
        num = item.get("invoice_number") or item.get("bill_number") or item.invoice_number or item.bill_number
        name = item.get("contact_name") or item.contact_name
        dt = item.get("issue_date") or item.issue_date
        due = item.get("due_date") or item.due_date
        tot = float(item.get("total") or item.total)
        paid = float(item.get("amount_paid") or item.amount_paid)
        out = float(item.get("outstanding") or item.outstanding)
        
        tb_data.append([
            Paragraph(num, normal_style),
            Paragraph(name, normal_style),
            Paragraph(dt.strftime("%d-%b-%Y") if hasattr(dt, "strftime") else str(dt), normal_style),
            Paragraph(due.strftime("%d-%b-%Y") if hasattr(due, "strftime") else str(due), normal_style),
            Paragraph(f"{tot:,.2f}", right_style),
            Paragraph(f"{paid:,.2f}", right_style),
            Paragraph(f"{out:,.2f}", right_bold_style)
        ])

    grand_total = float(data.get("total_outstanding", 0))
    tb_data.append([
        Paragraph("<b>Total Outstanding</b>", bold_style), "", "", "", "", "",
        Paragraph(f"<b>{grand_total:,.2f}</b>", right_bold_style)
    ])

    elements.append(Table(tb_data, colWidths=[24*mm, 46*mm, 22*mm, 22*mm, 24*mm, 24*mm, 24*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.2, primary_color),
        ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
        ('LINEABOVE', (0,-1), (-1,-1), 1.2, primary_color),
        ('PADDING', (0,0), (-1,-1), 4),
    ]))

    doc.build(elements)
    return buffer.getvalue()


def generate_gstr1_pdf(data, company_name: str, start: str, end: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    border_color = colors.HexColor('#94A3B8')
    table_header_bg = colors.HexColor('#E2E8F0')

    title_style = ParagraphStyle('G1Title', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('G1Subtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('G1Bold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=8, leading=10, textColor=text_color)
    normal_style = ParagraphStyle('G1Normal', parent=styles['Normal'], fontName='Helvetica', fontSize=8, leading=10, textColor=text_color)
    right_style = ParagraphStyle('G1Right', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('G1RightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph(f"GSTR-1 Outward Supplies Summary ({start} to {end})", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    # We will print outward supplies total taxable value, cgst, sgst, igst and cess
    summary_table = [
        [Paragraph("<b>Particulars</b>", bold_style), Paragraph("<b>Taxable Value (₹)</b>", right_bold_style), Paragraph("<b>CGST (₹)</b>", right_bold_style), Paragraph("<b>SGST (₹)</b>", right_bold_style), Paragraph("<b>IGST (₹)</b>", right_bold_style), Paragraph("<b>Cess (₹)</b>", right_bold_style)]
    ]
    # Add B2B registered
    b2b_taxable = sum(float(x.taxable_value) for x in data.b2b)
    b2b_cgst = sum(float(x.cgst) for x in data.b2b)
    b2b_sgst = sum(float(x.sgst) for x in data.b2b)
    b2b_igst = sum(float(x.igst) for x in data.b2b)
    b2b_cess = sum(float(x.cess) for x in data.b2b)

    summary_table.append([
        Paragraph("B2B Registered Taxable Supplies", normal_style),
        Paragraph(f"{b2b_taxable:,.2f}", right_style),
        Paragraph(f"{b2b_cgst:,.2f}", right_style),
        Paragraph(f"{b2b_sgst:,.2f}", right_style),
        Paragraph(f"{b2b_igst:,.2f}", right_style),
        Paragraph(f"{b2b_cess:,.2f}", right_style)
    ])

    # Add B2CS small
    b2cs_taxable = sum(float(x.taxable_value) for x in data.b2cs)
    b2cs_cgst = sum(float(x.cgst) for x in data.b2cs)
    b2cs_sgst = sum(float(x.sgst) for x in data.b2cs)
    b2cs_igst = sum(float(x.igst) for x in data.b2cs)
    b2cs_cess = sum(float(x.cess) for x in data.b2cs)

    summary_table.append([
        Paragraph("B2CS Consumer Supplies", normal_style),
        Paragraph(f"{b2cs_taxable:,.2f}", right_style),
        Paragraph(f"{b2cs_cgst:,.2f}", right_style),
        Paragraph(f"{b2cs_sgst:,.2f}", right_style),
        Paragraph(f"{b2cs_igst:,.2f}", right_style),
        Paragraph(f"{b2cs_cess:,.2f}", right_style)
    ])

    # Grand Totals
    summary_table.append([
        Paragraph("<b>Total</b>", bold_style),
        Paragraph(f"<b>{float(data.total_taxable_value):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.total_cgst):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.total_sgst):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.total_igst):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.total_cess):,.2f}</b>", right_bold_style)
    ])

    elements.append(Table(summary_table, colWidths=[56*mm, 26*mm, 26*mm, 26*mm, 26*mm, 26*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.2, primary_color),
        ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
        ('LINEABOVE', (0,-1), (-1,-1), 1.2, primary_color),
        ('PADDING', (0,0), (-1,-1), 4),
    ]))

    doc.build(elements)
    return buffer.getvalue()


def generate_gstr3b_pdf(data, company_name: str, start: str, end: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    border_color = colors.HexColor('#94A3B8')
    table_header_bg = colors.HexColor('#E2E8F0')

    title_style = ParagraphStyle('G3Title', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('G3Subtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('G3Bold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=8, leading=10, textColor=text_color)
    normal_style = ParagraphStyle('G3Normal', parent=styles['Normal'], fontName='Helvetica', fontSize=8, leading=10, textColor=text_color)
    right_style = ParagraphStyle('G3Right', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('G3RightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph(f"GSTR-3B Monthly Consolidated Summary ({start} to {end})", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    # Outward Supplies Outward Section
    outward = data.outward_taxable_supplies
    itc = data.inward_supplies_itc

    summary_table = [
        [Paragraph("<b>Nature of Supplies</b>", bold_style), Paragraph("<b>Taxable Value (₹)</b>", right_bold_style), Paragraph("<b>CGST (₹)</b>", right_bold_style), Paragraph("<b>SGST (₹)</b>", right_bold_style), Paragraph("<b>IGST (₹)</b>", right_bold_style), Paragraph("<b>Cess (₹)</b>", right_bold_style)]
    ]
    summary_table.append([
        Paragraph("3.1 Outward Taxable Supplies", normal_style),
        Paragraph(f"{float(outward.taxable_value):,.2f}", right_style),
        Paragraph(f"{float(outward.central_tax):,.2f}", right_style),
        Paragraph(f"{float(outward.state_ut_tax):,.2f}", right_style),
        Paragraph(f"{float(outward.integrated_tax):,.2f}", right_style),
        Paragraph(f"{float(outward.cess):,.2f}", right_style)
    ])
    summary_table.append([
        Paragraph("4. Eligible Input Tax Credit (ITC)", normal_style),
        "-",
        Paragraph(f"{float(itc.central_tax):,.2f}", right_style),
        Paragraph(f"{float(itc.state_ut_tax):,.2f}", right_style),
        Paragraph(f"{float(itc.integrated_tax):,.2f}", right_style),
        Paragraph(f"{float(itc.cess):,.2f}", right_style)
    ])
    summary_table.append([
        Paragraph("<b>Net Tax Payable</b>", bold_style),
        "-",
        Paragraph(f"<b>{float(data.net_tax_payable_cgst):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.net_tax_payable_sgst):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.net_tax_payable_igst):,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{float(data.net_tax_payable_cess):,.2f}</b>", right_bold_style)
    ])

    elements.append(Table(summary_table, colWidths=[56*mm, 26*mm, 26*mm, 26*mm, 26*mm, 26*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.2, primary_color),
        ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
        ('LINEABOVE', (0,-1), (-1,-1), 1.2, primary_color),
        ('PADDING', (0,0), (-1,-1), 4),
    ]))

    doc.build(elements)
    return buffer.getvalue()


def generate_gstr2_pdf(data, company_name: str, start: str, end: str) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=12*mm, rightMargin=12*mm, topMargin=12*mm, bottomMargin=12*mm)
    styles = getSampleStyleSheet()
    elements = []

    primary_color = colors.HexColor('#0F1B3D')
    text_color = colors.HexColor('#1E293B')
    border_color = colors.HexColor('#94A3B8')
    table_header_bg = colors.HexColor('#E2E8F0')

    title_style = ParagraphStyle('G2Title', parent=styles['Heading1'], fontName='Helvetica-Bold', fontSize=18, leading=22, textColor=primary_color, alignment=TA_CENTER)
    subtitle_style = ParagraphStyle('G2Subtitle', parent=styles['Normal'], fontName='Helvetica', fontSize=10, textColor=colors.HexColor('#475569'), alignment=TA_CENTER)
    bold_style = ParagraphStyle('G2Bold', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=8, leading=10, textColor=text_color)
    normal_style = ParagraphStyle('G2Normal', parent=styles['Normal'], fontName='Helvetica', fontSize=8, leading=10, textColor=text_color)
    right_style = ParagraphStyle('G2Right', parent=normal_style, alignment=TA_RIGHT)
    right_bold_style = ParagraphStyle('G2RightBold', parent=bold_style, alignment=TA_RIGHT)

    elements.append(Paragraph(company_name, title_style))
    elements.append(Paragraph(f"GSTR-2 Inward Supplies (Purchases) Summary ({start} to {end})", subtitle_style))
    elements.append(Spacer(1, 6*mm))

    summary_table = [
        [Paragraph("<b>Particulars</b>", bold_style), Paragraph("<b>Taxable Value (₹)</b>", right_bold_style), Paragraph("<b>CGST (₹)</b>", right_bold_style), Paragraph("<b>SGST (₹)</b>", right_bold_style), Paragraph("<b>IGST (₹)</b>", right_bold_style), Paragraph("<b>Cess (₹)</b>", right_bold_style)]
    ]

    # B2B registered vendor purchases
    b2b = data.get("b2b_purchases", [])
    b2b_taxable = sum(float(x.get("taxable_value", 0)) for x in b2b)
    b2b_cgst = sum(float(x.get("cgst_amount", 0)) for x in b2b)
    b2b_sgst = sum(float(x.get("sgst_amount", 0)) for x in b2b)
    b2b_igst = sum(float(x.get("igst_amount", 0)) for x in b2b)
    b2b_cess = sum(float(x.get("cess_amount", 0)) for x in b2b)

    summary_table.append([
        Paragraph("B2B Inward Registered Supplies", normal_style),
        Paragraph(f"{b2b_taxable:,.2f}", right_style),
        Paragraph(f"{b2b_cgst:,.2f}", right_style),
        Paragraph(f"{b2b_sgst:,.2f}", right_style),
        Paragraph(f"{b2b_igst:,.2f}", right_style),
        Paragraph(f"{b2b_cess:,.2f}", right_style)
    ])

    # B2BUR unregistered reverse charge
    b2bur = data.get("b2bur_purchases", [])
    b2bur_taxable = sum(float(x.get("taxable_value", 0)) for x in b2bur)
    b2bur_cgst = sum(float(x.get("cgst_amount", 0)) for x in b2bur)
    b2bur_sgst = sum(float(x.get("sgst_amount", 0)) for x in b2bur)
    b2bur_igst = sum(float(x.get("igst_amount", 0)) for x in b2bur)
    b2bur_cess = sum(float(x.get("cess_amount", 0)) for x in b2bur)

    summary_table.append([
        Paragraph("B2BUR Unregistered Reverse Charge", normal_style),
        Paragraph(f"{b2bur_taxable:,.2f}", right_style),
        Paragraph(f"{b2bur_cgst:,.2f}", right_style),
        Paragraph(f"{b2bur_sgst:,.2f}", right_style),
        Paragraph(f"{b2bur_igst:,.2f}", right_style),
        Paragraph(f"{b2bur_cess:,.2f}", right_style)
    ])

    # Notes registered & unregistered
    cdnr = data.get("cdnr_purchases", [])
    cdnur = data.get("cdnur_purchases", [])
    notes_taxable = sum(float(x.get("taxable_value", 0)) * (-1 if x.get("note_type") == "CREDIT" else 1) for x in cdnr + cdnur)
    notes_cgst = sum(float(x.get("cgst_amount", 0)) * (-1 if x.get("note_type") == "CREDIT" else 1) for x in cdnr + cdnur)
    notes_sgst = sum(float(x.get("sgst_amount", 0)) * (-1 if x.get("note_type") == "CREDIT" else 1) for x in cdnr + cdnur)
    notes_igst = sum(float(x.get("igst_amount", 0)) * (-1 if x.get("note_type") == "CREDIT" else 1) for x in cdnr + cdnur)
    notes_cess = sum(float(x.get("cess_amount", 0)) * (-1 if x.get("note_type") == "CREDIT" else 1) for x in cdnr + cdnur)

    summary_table.append([
        Paragraph("Debit / Credit Notes (Net Adjustment)", normal_style),
        Paragraph(f"{notes_taxable:,.2f}", right_style),
        Paragraph(f"{notes_cgst:,.2f}", right_style),
        Paragraph(f"{notes_sgst:,.2f}", right_style),
        Paragraph(f"{notes_igst:,.2f}", right_style),
        Paragraph(f"{notes_cess:,.2f}", right_style)
    ])

    # Grand Totals
    tot_taxable = b2b_taxable + b2bur_taxable + notes_taxable
    tot_cgst = b2b_cgst + b2bur_cgst + notes_cgst
    tot_sgst = b2b_sgst + b2bur_sgst + notes_sgst
    tot_igst = b2b_igst + b2bur_igst + notes_igst
    tot_cess = b2b_cess + b2bur_cess + notes_cess

    summary_table.append([
        Paragraph("<b>Total Eligible Inward Supplies</b>", bold_style),
        Paragraph(f"<b>{tot_taxable:,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{tot_cgst:,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{tot_sgst:,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{tot_igst:,.2f}</b>", right_bold_style),
        Paragraph(f"<b>{tot_cess:,.2f}</b>", right_bold_style)
    ])

    elements.append(Table(summary_table, colWidths=[56*mm, 26*mm, 26*mm, 26*mm, 26*mm, 26*mm], style=[
        ('BACKGROUND', (0,0), (-1,0), table_header_bg),
        ('LINEBELOW', (0,0), (-1,0), 1.2, primary_color),
        ('LINEBELOW', (0,1), (-1,-2), 0.5, border_color),
        ('LINEABOVE', (0,-1), (-1,-1), 1.2, primary_color),
        ('PADDING', (0,0), (-1,-1), 4),
    ]))

    doc.build(elements)
    return buffer.getvalue()


