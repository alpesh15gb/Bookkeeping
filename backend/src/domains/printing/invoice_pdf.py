"""Invoice and Document PDF generation using reportlab with multiple templates."""
from decimal import Decimal
from typing import Optional
import uuid
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, KeepTogether
from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_LEFT
from reportlab.graphics.shapes import Drawing
from reportlab.graphics.barcode.qr import QrCodeWidget
import io

def generate_invoice_pdf(
    invoice_number: str,
    issue_date,
    due_date,
    customer_name: str,
    customer_gstin: Optional[str],
    items: list,
    subtotal: Decimal,
    cgst: Decimal,
    sgst: Decimal,
    igst: Decimal,
    round_off: Decimal,
    total: Decimal,
    company_name: str = "ApexBooks",
    template: str = "professional",
    doc_type: str = "INVOICE",
    tenant_id: Optional[uuid.UUID] = None,
    db = None,
    amount_paid: Decimal = Decimal("0.00"),
) -> bytes:
    buffer = io.BytesIO()
    
    # --- Load Company Details from Database ---
    company_gstin = None
    company_pan = None
    company_address = None
    company_phone = None
    company_email = None
    company_website = None
    bank_name = None
    bank_account_no = None
    bank_ifsc = None
    bank_branch = None
    terms = None
    origin_state_code = None

    if db and tenant_id:
        from src.infrastructure.database.models import Tenant, TenantSetting
        tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
        if tenant:
            company_name = tenant.legal_name
            company_gstin = tenant.gstin
            company_pan = tenant.pan
            
        setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
        if setting:
            origin_state_code = setting.origin_state_code
            extra = setting.extra_settings or {}
            company_address = extra.get("company_address")
            company_phone = extra.get("company_phone")
            company_email = extra.get("company_email")
            company_website = extra.get("company_website")
            bank_name = extra.get("bank_name")
            bank_account_no = extra.get("bank_account_no")
            bank_ifsc = extra.get("bank_ifsc")
            bank_branch = extra.get("bank_branch")
            terms = extra.get("terms")

    # Clean fallbacks for rendering
    company_address = company_address or ""
    company_phone = company_phone or ""
    company_email = company_email or ""
    company_website = company_website or ""
    
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
        fontName='Helvetica-Bold',
        fontSize=15 * font_multiplier,
        leading=18 * font_multiplier,
        textColor=primary_color,
        alignment=TA_CENTER
    )
    
    company_title = ParagraphStyle(
        'CompanyTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=16 * font_multiplier,
        leading=20 * font_multiplier,
        textColor=primary_color if template != "thermal" else colors.black,
        alignment=TA_CENTER
    )
    
    normal_style = ParagraphStyle(
        'DocNormal',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9 * font_multiplier,
        leading=12 * font_multiplier,
        textColor=text_color
    )
    
    bold_style = ParagraphStyle(
        'DocBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
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
        fontName='Helvetica',
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
    upi_payload = f"upi://pay?pa={bank_ifsc or 'ICIC0006525'}@icici&pn={company_name}&am={total}&cu=INR"
    qr_drawing = build_qr_code(upi_payload, size=65.0)

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
        if customer_gstin:
            elements.append(Paragraph(f"GSTIN: {customer_gstin}", normal_style))
        elements.append(Spacer(1, 2*mm))
        
        # Table columns
        table_data = [[
            Paragraph("<b>Item</b>", normal_style),
            Paragraph("<b>Qty</b>", right_style),
            Paragraph("<b>Rate</b>", right_style),
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
            [Paragraph("CGST:", normal_style), Paragraph(f"Rs. {cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"Rs. {sgst:.2f}", right_style)],
            [Paragraph("Total:", bold_style), Paragraph(f"Rs. {total:.2f}", bold_right)],
        ]
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
            [Paragraph(f"<b>Document No:</b> {invoice_number}", normal_style), Paragraph(f"<b>Place of Supply:</b> {origin_state_code or 'N/A'}", normal_style)],
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
            [Paragraph(f"GSTIN: {customer_gstin or 'Unregistered'}", normal_style)]
        ]
        billing_table = Table(billing_box, colWidths=[186*mm], style=[
            ('BOX', (0,0), (-1,-1), 0.5, border_color),
            ('PADDING', (0,0), (-1,-1), 6),
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F8FAFC'))
        ])
        elements.append(billing_table)
        elements.append(Spacer(1, 4*mm))

        # Items Table
        table_headers = ['S.No.', 'Description of Goods', 'Qty', 'Rate', 'Amount']
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
        bank_details_str = f"<b>Company's Bank Details:</b><br/>Bank: {bank_name or 'N/A'}<br/>A/c No: {bank_account_no or 'N/A'}<br/>IFSC: {bank_ifsc or 'N/A'}<br/>Branch: {bank_branch or 'N/A'}"
        
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
        totals_table = Table(totals_col, colWidths=[40*mm, 35*mm], style=[
            ('PADDING', (0,0), (-1,-1), 2),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE')
        ])

        summary_row = [
            [Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]
        ]
        
        summary_table = Table(summary_row, colWidths=[80*mm, 31*mm, 75*mm], style=[
            ('BOX', (0,0), (-1,-1), 0.5, border_color),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6),
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#F8FAFC'))
        ])
        elements.append(summary_table)
        
        # Terms and signatory
        elements.append(Spacer(1, 4*mm))
        terms_str = f"<b>Terms & Conditions:</b><br/>{terms or '1. Goods once sold will not be taken back.'}"
        sign_block = f"<br/><br/><br/>for <b>{company_name}</b><br/><br/>Authorised Signatory"
        
        bottom_table = Table([[Paragraph(terms_str, caption_style), Paragraph(sign_block, center_style)]], colWidths=[120*mm, 66*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 0),
        ])
        elements.append(bottom_table)

    # Render Minimal Layout (clean, black & white, no borders)
    elif template == "minimal":
        elements.append(Paragraph(company_name, company_title))
        if company_address:
            elements.append(Paragraph(company_address, center_style))
        elements.append(Spacer(1, 4*mm))

        # Simple meta
        meta = [
            [Paragraph(f"<b>{doc_type}:</b> {invoice_number}", bold_style), Paragraph(f"Date: {issue_date}", normal_style)],
            [Paragraph(f"Customer: {customer_name}", normal_style), Paragraph(f"Due: {due_date}", normal_style)],
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
        if company_gstin:
            elements.append(Paragraph(f"GSTIN: {company_gstin}", center_style))
        elements.append(Spacer(1, 4*mm))

        # Two-column info
        info_row = [
            [
                Paragraph(f"<b>Billed To</b><br/>{customer_name}<br/>{customer_gstin or 'Unregistered'}", normal_style),
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
        metadata_row = [
            [
                Paragraph(f"<b>Bill To:</b><br/>{customer_name}<br/>GSTIN: {customer_gstin or 'N/A'}", normal_style),
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
        totals_table = Table(totals_col, colWidths=[40*mm, 35*mm], style=[
            ('PADDING', (0,0), (-1,-1), 2),
        ])

        summary_row = [
            [Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]
        ]
        summary_table = Table(summary_row, colWidths=[80*mm, 31*mm, 75*mm], style=[
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

    doc.build(elements)
    return buffer.getvalue()

