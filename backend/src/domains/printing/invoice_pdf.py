"""Invoice and Document PDF generation using reportlab with multiple templates."""
from decimal import Decimal
from typing import Optional
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_LEFT
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
) -> bytes:
    buffer = io.BytesIO()
    
    # 1. Page settings based on template format
    if template == "thermal":
        # 80mm width, dynamic height
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
            leftMargin=15*mm,
            rightMargin=15*mm,
            topMargin=15*mm,
            bottomMargin=15*mm
        )
        
    styles = getSampleStyleSheet()
    elements = []

    # 2. Design system style configuration based on selected template
    if template == "modern":
        primary_color = colors.HexColor('#4F46E5')  # Elegant Indigo
        text_color = colors.HexColor('#1F2937')
        muted_color = colors.HexColor('#6B7280')
        table_header_bg = colors.HexColor('#EEF2F6')
        alternate_row_bg = colors.HexColor('#FAFAFA')
        border_color = colors.HexColor('#E5E7EB')
    elif template == "thermal":
        primary_color = colors.black
        text_color = colors.black
        muted_color = colors.black
        table_header_bg = colors.white
        alternate_row_bg = colors.white
        border_color = colors.black
    else:  # professional (default)
        primary_color = colors.HexColor('#0F1B3D')  # Deep Navy Blue
        text_color = colors.HexColor('#1E293B')
        muted_color = colors.HexColor('#64748B')
        table_header_bg = colors.HexColor('#0F1B3D')
        alternate_row_bg = colors.HexColor('#F8FAFC')
        border_color = colors.HexColor('#E2E8F0')

    # Typography styles
    font_multiplier = 0.8 if template == "thermal" else 1.0
    
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Heading1'],
        fontName='Helvetica-Bold',
        fontSize=18 * font_multiplier,
        leading=22 * font_multiplier,
        textColor=primary_color,
        spaceAfter=2
    )
    
    number_style = ParagraphStyle(
        'DocNumber',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=11 * font_multiplier,
        leading=14 * font_multiplier,
        textColor=muted_color,
        spaceAfter=10
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

    # 3. Header Section
    elements.append(Paragraph(doc_type.upper(), title_style))
    elements.append(Paragraph(f"#{invoice_number}", number_style))
    elements.append(Spacer(1, 4*mm))

    # 4. Details / Metadata Grid
    party_label = "Vendor:" if doc_type.upper() in ("BILL", "PURCHASE ORDER", "DEBIT NOTE") else "Customer:"
    
    if template == "thermal":
        # Stack vertically for thermal
        elements.append(Paragraph(f"<b>Date:</b> {issue_date}", normal_style))
        elements.append(Paragraph(f"<b>Due:</b> {due_date}", normal_style))
        elements.append(Paragraph(f"<b>{party_label}</b> {customer_name}", normal_style))
        if customer_gstin:
            elements.append(Paragraph(f"<b>GSTIN:</b> {customer_gstin}", normal_style))
        elements.append(Spacer(1, 3*mm))
    else:
        # Side-by-side table for A4 templates
        info_data = [
            [Paragraph("<b>Date:</b>", normal_style), Paragraph(str(issue_date), normal_style), Paragraph(f"<b>{party_label}</b>", normal_style), Paragraph(customer_name, normal_style)],
            [Paragraph("<b>Due Date:</b>", normal_style), Paragraph(str(due_date), normal_style), Paragraph("<b>GSTIN:</b>", normal_style), Paragraph(customer_gstin or "N/A", normal_style)],
            [Paragraph("<b>Issuer:</b>", normal_style), Paragraph(company_name, normal_style), "", ""]
        ]
        info_table = Table(info_data, colWidths=[60*mm, 50*mm, 25*mm, 45*mm])
        info_table.setStyle(TableStyle([
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 2),
            ('TOPPADDING', (0, 0), (-1, -1), 2),
        ]))
        elements.append(info_table)
        elements.append(Spacer(1, 6*mm))

    # 5. Line Items Table
    header_cols = ['#', 'Description', 'Qty', 'Rate', 'Amount']
    table_data = [[Paragraph(f"<b>{col}</b>", ParagraphStyle('HeaderStyle', parent=normal_style, textColor=colors.white if template == "professional" else text_color, fontName='Helvetica-Bold')) for col in header_cols]]
    
    for i, item in enumerate(items, 1):
        desc = item.get('description') or item.get('product_name') or 'N/A'
        table_data.append([
            Paragraph(str(i), normal_style),
            Paragraph(desc, normal_style),
            Paragraph(str(item.get('quantity', 0)), normal_style),
            Paragraph(f"₹{float(item.get('rate', 0)):.2f}", normal_style),
            Paragraph(f"₹{float(item.get('total', item.get('amount', 0))):.2f}", normal_style),
        ])

    # Table styles based on formats
    if template == "thermal":
        col_widths = [8*mm, 32*mm, 8*mm, 13*mm, 13*mm]
        t_style = TableStyle([
            ('FONTSIZE', (0, 0), (-1, -1), 7),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
            ('TOPPADDING', (0, 0), (-1, -1), 1),
            ('ALIGN', (2, 0), (-1, -1), 'RIGHT'),
            ('LINEBELOW', (0, 0), (-1, 0), 1, colors.black),
            ('LINEBELOW', (0, -1), (-1, -1), 1, colors.black),
        ])
    elif template == "modern":
        col_widths = [10*mm, 90*mm, 20*mm, 30*mm, 30*mm]
        t_style = TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), table_header_bg),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
            ('TOPPADDING', (0, 0), (-1, -1), 6),
            ('ALIGN', (2, 0), (-1, -1), 'RIGHT'),
            ('LINEBELOW', (0, 0), (-1, 0), 2, primary_color),
            ('LINEBELOW', (0, 1), (-1, -1), 0.5, border_color),
        ])
    else:  # professional
        col_widths = [12*mm, 88*mm, 20*mm, 30*mm, 30*mm]
        t_style = TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), table_header_bg),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
            ('TOPPADDING', (0, 0), (-1, -1), 5),
            ('ALIGN', (2, 0), (-1, -1), 'RIGHT'),
            ('GRID', (0, 0), (-1, -1), 0.5, border_color),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, alternate_row_bg]),
        ])

    items_table = Table(table_data, colWidths=col_widths)
    items_table.setStyle(t_style)
    elements.append(items_table)
    elements.append(Spacer(1, 4*mm))

    # 6. Summary Block
    total_data = [
        [Paragraph("Subtotal:", normal_style), Paragraph(f"₹{subtotal:.2f}", normal_style)],
        [Paragraph("CGST:", normal_style), Paragraph(f"₹{cgst:.2f}", normal_style)],
        [Paragraph("SGST:", normal_style), Paragraph(f"₹{sgst:.2f}", normal_style)],
        [Paragraph("IGST:", normal_style), Paragraph(f"₹{igst:.2f}", normal_style)],
        [Paragraph("Round Off:", normal_style), Paragraph(f"₹{round_off:.2f}", normal_style)],
        [Paragraph("<b>TOTAL:</b>", bold_style), Paragraph(f"<b>₹{total:.2f}</b>", bold_style)],
    ]

    if template == "thermal":
        sum_table = Table(total_data, colWidths=[44*mm, 30*mm])
        sum_table.setStyle(TableStyle([
            ('ALIGN', (1, 0), (1, -1), 'RIGHT'),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
            ('TOPPADDING', (0, 0), (-1, -1), 1),
        ]))
    else:
        sum_table = Table(total_data, colWidths=[130*mm, 50*mm])
        sum_table.setStyle(TableStyle([
            ('ALIGN', (1, 0), (1, -1), 'RIGHT'),
            ('LINEABOVE', (0, -1), (-1, -1), 1, border_color),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
            ('TOPPADDING', (0, 0), (-1, -1), 4),
        ]))

    elements.append(sum_table)

    doc.build(elements)
    return buffer.getvalue()
