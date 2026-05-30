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
            [Paragraph("Subtotal:", normal_style), Paragraph(f"₹{subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"₹{cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"₹{sgst:.2f}", right_style)],
            [Paragraph("Total:", bold_style), Paragraph(f"₹{total:.2f}", bold_right)],
        ]
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
            [Paragraph("Subtotal:", normal_style), Paragraph(f"₹{subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"₹{cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"₹{sgst:.2f}", right_style)],
            [Paragraph("IGST:", normal_style), Paragraph(f"₹{igst:.2f}", right_style)],
            [Paragraph("Round Off:", normal_style), Paragraph(f"₹{round_off:.2f}", right_style)],
            [Paragraph("<b>TOTAL:</b>", bold_style), Paragraph(f"<b>₹{total:.2f}</b>", bold_right)],
        ]
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
            [Paragraph("Subtotal:", normal_style), Paragraph(f"₹{subtotal:.2f}", right_style)],
            [Paragraph("CGST:", normal_style), Paragraph(f"₹{cgst:.2f}", right_style)],
            [Paragraph("SGST:", normal_style), Paragraph(f"₹{sgst:.2f}", right_style)],
            [Paragraph("Total Amount:", bold_style), Paragraph(f"₹{total:.2f}", bold_right)],
        ]
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
