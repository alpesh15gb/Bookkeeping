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
        from src.infrastructure.database.models import Tenant, TenantSetting, BankingProfile
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
            terms = extra.get("terms")

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

    # Render A4 Tally GST Layout (Format 2 - Tata Motors Style Boxy Layout)
    elif template == "tally_gst":
        tally_primary = colors.HexColor('#0F1B3D')
        tally_border = colors.HexColor('#475569')
        
        # Header banner
        title_p = Paragraph(f"<b>TAX INVOICE</b>", ParagraphStyle('TallyTitle', parent=styles['Normal'], fontName='Helvetica-Bold', fontSize=12, alignment=TA_CENTER, textColor=tally_primary))
        elements.append(Table([[title_p]], colWidths=[186*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('PADDING', (0,0), (-1,-1), 3),
            ('BACKGROUND', (0,0), (-1,-1), colors.HexColor('#E2E8F0'))
        ]))
        
        # Header main grid
        company_p = Paragraph(f"<b>{company_name}</b><br/>{company_address}<br/>GSTIN: {company_gstin or 'N/A'}<br/>PAN: {company_pan or 'N/A'}<br/>Mobile: {company_phone} | Email: {company_email}", normal_style)
        invoice_meta_p = Paragraph(f"<b>Invoice No:</b> {invoice_number}<br/><b>Date:</b> {issue_date}<br/><b>Due Date:</b> {due_date}<br/><b>Place of Supply:</b> {origin_state_code or 'N/A'}", normal_style)
        
        header_grid = Table([[company_p, invoice_meta_p]], colWidths=[110*mm, 76*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, tally_border),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6)
        ])
        elements.append(header_grid)
        
        # Billing & Shipping info side-by-side
        bill_to_p = Paragraph(f"<b>Consignee (Ship To):</b><br/>{customer_name}<br/>GSTIN: {customer_gstin or 'Unregistered'}", normal_style)
        ship_to_p = Paragraph(f"<b>Buyer (Bill To):</b><br/>{customer_name}<br/>GSTIN: {customer_gstin or 'Unregistered'}", normal_style)
        
        party_grid = Table([[bill_to_p, ship_to_p]], colWidths=[93*mm, 93*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, tally_border),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6)
        ])
        elements.append(party_grid)

        # Items Table (Tally style columns: S.No., Description, HSN/SAC, GST Rate, Qty, Rate, Amount)
        table_headers = ['S.No.', 'Description of Goods', 'HSN/SAC', 'GST Rate', 'Qty', 'Rate', 'Amount']
        grid_data = [[Paragraph(f"<b>{h}</b>", bold_style) for h in table_headers]]
        for i, item in enumerate(items, 1):
            desc = item.get('description') or item.get('product_name') or 'N/A'
            hsn = item.get('hsn_sac') or ''
            gst_r = f"{item.get('gst_rate', 0):.0f}%"
            qty = float(item.get('quantity', 0))
            rate = float(item.get('rate', 0))
            amt = float(item.get('total', item.get('amount', 0)))
            grid_data.append([
                Paragraph(str(i), normal_style),
                Paragraph(desc, normal_style),
                Paragraph(hsn, normal_style),
                Paragraph(gst_r, normal_style),
                Paragraph(f"{qty:.0f}", normal_style),
                Paragraph(f"{rate:.2f}", normal_style),
                Paragraph(f"{amt:.2f}", normal_style)
            ])
            
        items_table = Table(grid_data, colWidths=[12*mm, 84*mm, 20*mm, 18*mm, 16*mm, 18*mm, 18*mm], style=[
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#F8FAFC')),
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, tally_border),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('PADDING', (0,0), (-1,-1), 4),
        ])
        elements.append(items_table)
        
        # Totals and GST analysis
        # 1. Summarize GST by HSN/SAC
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

        gst_analysis_headers = ['HSN/SAC', 'Taxable Value', 'Central Tax (Rate/Amt)', 'State Tax (Rate/Amt)', 'Total Tax']
        gst_analysis_rows = [[Paragraph(f"<b>{h}</b>", bold_style) for h in gst_analysis_headers]]
        for hsn, val in hsn_summary.items():
            tot_tax = val['cgst'] + val['sgst'] + val['igst']
            gst_analysis_rows.append([
                Paragraph(hsn, normal_style),
                Paragraph(f"{val['taxable']:.2f}", normal_style),
                Paragraph(f"{val['cgst_rate']:.0f}% / {val['cgst']:.2f}", normal_style),
                Paragraph(f"{val['sgst_rate']:.0f}% / {val['sgst']:.2f}", normal_style),
                Paragraph(f"{tot_tax:.2f}", normal_style),
            ])
            
        gst_analysis_table = Table(gst_analysis_rows, colWidths=[26*mm, 35*mm, 45*mm, 45*mm, 35*mm], style=[
            ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#F1F5F9')),
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, tally_border),
            ('PADDING', (0,0), (-1,-1), 4),
        ])
        
        # Bank & Summary layout
        bank_details_str = f"<b>Bank Details:</b><br/>Bank: {bank_name or 'N/A'}<br/>A/c No: {bank_account_no or 'N/A'}<br/>IFSC: {bank_ifsc or 'N/A'}<br/>Branch: {bank_branch or 'N/A'}"
        totals_col = [
            [Paragraph("Taxable Amount:", normal_style), Paragraph(f"Rs. {subtotal:.2f}", right_style)],
            [Paragraph("Total CGST:", normal_style), Paragraph(f"Rs. {cgst:.2f}", right_style)],
            [Paragraph("Total SGST:", normal_style), Paragraph(f"Rs. {sgst:.2f}", right_style)],
            [Paragraph("Total IGST:", normal_style), Paragraph(f"Rs. {igst:.2f}", right_style)],
            [Paragraph("<b>Grand Total:</b>", bold_style), Paragraph(f"<b>Rs. {total:.2f}</b>", bold_right)],
        ]
        totals_table = Table(totals_col, colWidths=[40*mm, 35*mm], style=[('PADDING', (0,0), (-1,-1), 2)])
        
        bottom_summary_grid = Table([[Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]], colWidths=[80*mm, 31*mm, 75*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, tally_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, tally_border),
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 6)
        ])
        
        elements.append(Spacer(1, 2*mm))
        elements.append(Paragraph("<b>GST Tax Analysis Breakdown</b>", bold_style))
        elements.append(Spacer(1, 1*mm))
        elements.append(gst_analysis_table)
        elements.append(Spacer(1, 2*mm))
        elements.append(bottom_summary_grid)
        
        elements.append(Spacer(1, 2*mm))
        terms_str = f"<b>Terms & Conditions:</b><br/>{terms or 'Goods once sold will not be taken back.'}"
        sign_block = f"<br/>for <b>{company_name}</b><br/><br/><br/>Authorised Signatory"
        bottom_table = Table([[Paragraph(terms_str, caption_style), Paragraph(sign_block, center_style)]], colWidths=[120*mm, 66*mm], style=[
            ('VALIGN', (0,0), (-1,-1), 'TOP'),
            ('PADDING', (0,0), (-1,-1), 0),
        ])
        elements.append(bottom_table)

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
            [Paragraph(f"<b>Date:</b> {issue_date}", normal_style), Paragraph(f"<b>Address:</b> {company_address}", normal_style)],
            [Paragraph(f"<b>Due Date:</b> {due_date}", normal_style), Paragraph(f"<b>GSTIN:</b> {customer_gstin or 'Unregistered'}", normal_style)],
        ]
        elements.append(Table(meta_grid_data, colWidths=[93*mm, 93*mm], style=[
            ('BOX', (0,0), (-1,-1), 1, classic_border),
            ('INNERGRID', (0,0), (-1,-1), 0.5, classic_border),
            ('PADDING', (0,0), (-1,-1), 4)
        ]))
        elements.append(Spacer(1, 4*mm))
        
        # Classic Items Table. To make the vertical lines run all the way down, we pad the table with empty lines if needed.
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
        totals_table = Table(totals_col, colWidths=[40*mm, 35*mm], style=[('PADDING', (0,0), (-1,-1), 2)])
        
        summary_table = Table([[Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]], colWidths=[80*mm, 31*mm, 75*mm], style=[
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
        header_p = Paragraph(f"<b><font size=16 color='white'>{company_name.upper()}</font></b><br/><font size=9 color='white'>GSTIN: {company_gstin or 'N/A'}</font>", normal_style)
        title_p = Paragraph(f"<b><font size=16 color='white'>{doc_type.upper()}</font></b><br/><font size=11 color='white'>#{invoice_number}</font>", ParagraphStyle('SleekTitle', parent=styles['Normal'], alignment=TA_RIGHT))
        
        banner_table = Table([[header_p, title_p]], colWidths=[100*mm, 86*mm], style=[
            ('BACKGROUND', (0,0), (-1,-1), sleek_primary),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
            ('PADDING', (0,0), (-1,-1), 12)
        ])
        elements.append(banner_table)
        elements.append(Spacer(1, 6*mm))
        
        # Metadata
        meta_left = f"<b>Date:</b> {issue_date}<br/><b>Due Date:</b> {due_date}<br/><b>Place of Supply:</b> {origin_state_code or 'N/A'}"
        meta_right = f"<b>Billed To:</b><br/>{customer_name}<br/>GSTIN: {customer_gstin or 'Unregistered'}"
        
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
        totals_table = Table(totals_col, colWidths=[40*mm, 35*mm], style=[
            ('PADDING', (0,0), (-1,-1), 2),
            ('VALIGN', (0,0), (-1,-1), 'MIDDLE')
        ])
        
        summary_table = Table([[Paragraph(bank_details_str, normal_style), qr_drawing, totals_table]], colWidths=[80*mm, 31*mm, 75*mm], style=[
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

    sections = [
        ("ASSETS", data.get("assets", {}).get("items", []) or data.get("assets", []), float(data.get("total_assets", 0))),
        ("LIABILITIES", data.get("liabilities", {}).get("items", []) or data.get("liabilities", []), float(data.get("total_liabilities", 0))),
        ("EQUITY", data.get("equity", {}).get("items", []) or data.get("equity", []), float(data.get("total_equity", 0)))
    ]

    for title, items, total in sections:
        table_data = [[Paragraph(f"<b>{title}</b>", bold_style), ""]]
        for item in items:
            name = item.get("account_name") or item.account_name
            code = item.get("account_code") or item.account_code
            bal = float(item.get("balance") or item.balance)
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

