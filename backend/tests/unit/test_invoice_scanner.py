import pytest
from unittest.mock import patch, MagicMock
from src.domains.scanning.invoice_scanner import InvoiceScanner, _clean_json_string, _robust_json_loads
from src.core.config import settings

def test_clean_json_string():
    # Test invalid escapes are cleaned
    raw_json = '{"address": "Flat B-8\\B-9", "name": "Test\\nNewline", "path": "C:\\\\Windows\\\\System32", "bad_unicode": "\\u12z4"}'
    cleaned = _clean_json_string(raw_json)
    # The double backslashes in path and the newline escape should be preserved,
    # but the single backslash in Flat B-8\B-9 and \u12z4 (since z is not hex) should be escaped.
    assert 'Flat B-8\\\\B-9' in cleaned
    assert 'Test\\nNewline' in cleaned
    assert 'C:\\\\Windows\\\\System32' in cleaned
    assert '\\\\u12z4' in cleaned

def test_robust_json_loads():
    # 1. Single quotes on keys, standard json boolean
    raw1 = '{"vendor_name": "Test", "active": true, \'items\': [1, 2,]}'
    parsed1 = _robust_json_loads(raw1)
    assert parsed1 == {"vendor_name": "Test", "active": True, "items": [1, 2]}

    # 2. All single quotes
    raw2 = "{'vendor_name': 'Test', 'active': true}"
    parsed2 = _robust_json_loads(raw2)
    assert parsed2 == {"vendor_name": "Test", "active": True}

    # 3. Trailing commas in nested structures
    raw3 = '{"line_items": [{"name": "A",}, {"name": "B",},],}'
    parsed3 = _robust_json_loads(raw3)
    assert parsed3 == {"line_items": [{"name": "A"}, {"name": "B"}]}

@patch("requests.post")
def test_scan_with_nvidia_nim_success(mock_post):
    # Mock settings
    with patch.object(settings, "NVIDIA_NIM_API_KEY", "mock_key"), \
         patch.object(settings, "NVIDIA_NIM_MODEL", "mock_model"):
        
        # Mock API response with some invalid JSON escape sequences, single quotes, and trailing commas
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "choices": [
                {
                    "message": {
                        "content": "{'vendor_name': 'Test Vendor', 'vendor_address': 'Street \\\\ road', 'line_items': [{'product_name': 'Item 1', 'quantity': 2, 'rate': 50,},],}"
                    }
                }
            ]
        }
        mock_post.return_value = mock_response

        scanner = InvoiceScanner()
        # Mock _pdf_to_image_bytes to do nothing
        with patch("src.domains.scanning.invoice_scanner._pdf_to_image_bytes", return_value=b"image_bytes"):
            result = scanner.scan(b"pdf_bytes", "test.pdf")

        # Verify requests.post was called with correct parameters
        mock_post.assert_called_once()
        args, kwargs = mock_post.call_args
        assert kwargs["headers"]["Authorization"] == "Bearer mock_key"
        assert kwargs["json"]["model"] == "mock_model"

        # Verify returned structure
        assert result["vendor_name"] == "Test Vendor"
        assert result["vendor_address"] == "Street \\ road"
        assert len(result["line_items"]) == 1
        assert result["line_items"][0]["product_name"] == "Item 1"
        assert result["line_items"][0]["quantity"] == 2.0
        assert result["line_items"][0]["rate"] == 50.0
        assert result["line_items"][0]["amount"] == 100.0

@patch("requests.post")
def test_scan_nvidia_nim_standalone_fails_without_fallback(mock_post):
    # Mock settings with NIM API key
    with patch.object(settings, "NVIDIA_NIM_API_KEY", "mock_key"):
        # Mock requests.post to raise an error
        mock_post.side_effect = Exception("NIM Connection Timeout")

        scanner = InvoiceScanner()
        # Verify that the exception propagates and does NOT fall back to PaddleOCR
        with pytest.raises(Exception, match="NIM Connection Timeout"):
            scanner.scan(b"file_bytes", "invoice.png")

@patch("requests.post")
def test_scan_with_nvidia_nim_fallback(mock_post):
    with patch.object(settings, "NVIDIA_NIM_API_KEY", "mock_key"), \
         patch.object(settings, "NVIDIA_NIM_MODEL", "mock_model"):
        
        # Test content matching the real-world markdown response that failed
        failing_markdown = (
            "The invoice is for a projector screen, with a total amount of 10,847.46 Indian Rupees. "
            "The invoice number is MC2025-26/7164, and the date is March 27, 2026. The vendor's name is "
            "Mahaveer Computers, and their GSTIN is 36BFAPM4787A1ZJ. The vendor's address is Flat No 404, "
            "B-B&B-9, 4th Floor, Millenium Arcade, Khapra, Hyderabad, 3rd Cross Road, Medchal Malkajgiri, "
            "Telangana, Code : 36.\n\n"
            "**Invoice Details:**\n\n"
            "* **Invoice Number:** MC2025-26/7164\n"
            "* **Date:** 27-Mar-26\n"
            "* **Vendor Name:** Mahaveer Computers\n"
            "* **Vendor GSTIN:** 36BFAPM4787A1ZJ\n"
            "* **Vendor Address:** Flat No 404, B-B&B-9, 4th Floor, Millenium Arcade, Khapra, Hyderabad, "
            "3rd Cross Road, Medchal Malkajgiri, Telangana, Code : 36\n\n"
            "**Line Items:**\n\n"
            "* **Product Name:** Projector Screen\n"
            "* **HSN/SAC:** 85286900\n"
            "* **Quantity:** 1 pcs\n"
            "* **Rate:** 12,800.00\n"
            "* **GST Rate:** 9%\n"
            "* **Amount:** 10,847.46\n\n"
            "**Tax Details:**\n\n"
            "* **CGST:** 9%\n"
            "* **SGST:** 9%\n"
            "* **IGST:** 0%\n\n"
            "**Total Amount:** 10,847.46"
        )
        
        mock_response = MagicMock()
        mock_response.raise_for_status = MagicMock()
        mock_response.json.return_value = {
            "choices": [
                {
                    "message": {
                        "content": failing_markdown
                    }
                }
            ]
        }
        mock_post.return_value = mock_response

        scanner = InvoiceScanner()
        with patch("src.domains.scanning.invoice_scanner._pdf_to_image_bytes", return_value=b"image_bytes"):
            result = scanner.scan(b"pdf_bytes", "test.pdf")

        assert result["vendor_name"] == "Mahaveer Computers"
        assert result["vendor_gstin"] == "36BFAPM4787A1ZJ"
        assert result["vendor_address"].startswith("Flat No 404")
        assert result["bill_number"] == "MC2025-26/7164"
        assert result["bill_date"] == "2026-03-27"
        assert result["total"] == 10847.46
        assert len(result["line_items"]) == 1
        assert result["line_items"][0]["product_name"] == "Projector Screen"
        assert result["line_items"][0]["quantity"] == 1.0
        assert result["line_items"][0]["rate"] == 12800.00
        assert result["line_items"][0]["amount"] == 10847.46
        assert result["line_items"][0]["hsn_sac"] == "85286900"
        assert result["line_items"][0]["gst_rate"] == 9.0

