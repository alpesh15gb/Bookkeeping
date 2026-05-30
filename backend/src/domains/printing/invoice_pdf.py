"""Invoice PDF generation using reportlab."""
from decimal import Decimal
from typing import Optional
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.enums import TA_CENTER, TA_RIGHT
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
) -> bytes:
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, topMargin=20*mm, bottomMargin=20*mm)
    styles = getSampleStyleSheet()
    elements = []

    title_style = ParagraphStyle('Title2', parent=styles['Title'], fontSize=18, spaceAfter=6)
    elements.append(Paragraph(f"INVOICE", title_style))
    elements.append(Paragraph(f"#{invoice_number}", styles['Normal']))
    elements.append(Spacer(1, 10*mm))

    info_data = [
        ["Date:", str(issue_date), "Due:", str(due_date)],
        ["Customer:", customer_name, "GSTIN:", customer_gstin or "N/A"],
    ]
    info_table = Table(info_data, colWidths=[60, 150, 50, 150])
    info_table.setStyle(TableStyle([
        ('FONTNAME', (0, 0), (-1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTNAME', (2, 0), (2, -1), 'Helvetica-Bold'),
    ]))
    elements.append(info_table)
    elements.append(Spacer(1, 10*mm))

    header = ['#', 'Description', 'Qty', 'Rate', 'Amount']
    table_data = [header]
    for i, item in enumerate(items, 1):
        table_data.append([
            str(i),
            item.get('description', item.get('product_name', '')),
            str(item.get('quantity', 0)),
            f"Rs.{item.get('rate', 0):.2f}",
            f"Rs.{item.get('total', 0):.2f}",
        ])

    items_table = Table(table_data, colWidths=[30, 200, 50, 80, 80])
    items_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0F1B3D')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('ALIGN', (2, 0), (-1, -1), 'RIGHT'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F8F9FC')]),
    ]))
    elements.append(items_table)
    elements.append(Spacer(1, 10*mm))

    total_data = [
        ["Subtotal:", f"Rs.{subtotal:.2f}"],
        ["CGST:", f"Rs.{cgst:.2f}"],
        ["SGST:", f"Rs.{sgst:.2f}"],
        ["IGST:", f"Rs.{igst:.2f}"],
        ["Round Off:", f"Rs.{round_off:.2f}"],
        ["TOTAL:", f"Rs.{total:.2f}"],
    ]
    total_table = Table(total_data, colWidths=[350, 90])
    total_table.setStyle(TableStyle([
        ('FONTNAME', (0, -1), (-1, -1), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('ALIGN', (1, 0), (1, -1), 'RIGHT'),
        ('LINEABOVE', (0, -1), (-1, -1), 1, colors.black),
    ]))
    elements.append(total_table)

    doc.build(elements)
    return buffer.getvalue()
