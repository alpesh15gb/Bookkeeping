from src.api.v1.gstr2a import extract_portal_purchase_items


def test_extracts_current_gstr2b_document_envelope_and_item_taxes():
    payload = {
        "data": {
            "docdata": {
                "b2b": [{
                    "ctin": "27ABCDE1234F1Z5",
                    "trdnm": "Sample Supplier",
                    "inv": [{
                        "inum": "INV-42",
                        "idt": "14-07-2026",
                        "val": 1180,
                        "items": [{
                            "txval": 1000,
                            "iamt": 180,
                            "camt": 0,
                            "samt": 0,
                            "csamt": 0,
                        }],
                    }],
                }],
            },
        },
    }

    items = extract_portal_purchase_items(payload)

    assert len(items) == 1
    assert items[0].supplier_gstin == "27ABCDE1234F1Z5"
    assert items[0].invoice_number == "INV-42"
    assert items[0].taxable_value == 1000
    assert items[0].igst == 180


def test_extracts_legacy_gstr2a_shape():
    payload = {
        "b2b": [{
            "gstin": "29ABCDE1234F1Z3",
            "tradeName": "Legacy Supplier",
            "invoices": [{
                "inum": "A-9",
                "idt": "01-07-2026",
                "val": 590,
                "txval": 500,
                "cgst": 45,
                "sgst": 45,
            }],
        }],
    }

    items = extract_portal_purchase_items(payload)

    assert len(items) == 1
    assert items[0].supplier_name == "Legacy Supplier"
    assert items[0].cgst == 45
    assert items[0].sgst == 45
