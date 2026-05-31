"""
Shared HTML email builder with embedded ApexBooks logo.
All outbound SMTP emails should go through helpers here so branding is consistent.
"""
import base64
import os
from pathlib import Path

_logo_b64: str | None = None


def _load_logo() -> str:
    """Lazy-load and cache the logo as a base64 data-URI."""
    global _logo_b64
    if _logo_b64 is not None:
        return _logo_b64

    # Search a few known locations
    candidates = [
        Path(__file__).resolve().parents[3] / "flutter_client" / "assets" / "logo.png",
        Path(__file__).resolve().parents[2] / "static" / "logo.png",
        Path(os.environ.get("LOGO_PATH", "")),
    ]
    for p in candidates:
        if p.is_file():
            raw = p.read_bytes()
            _logo_b64 = base64.b64encode(raw).decode("ascii")
            return _logo_b64

    # Fallback — return empty so emails still send without the image
    return ""


def _logo_data_uri() -> str:
    b64 = _load_logo()
    if not b64:
        return ""
    return f"data:image/png;base64,{b64}"


def _wrap(title: str, body_html: str) -> str:
    """Wrap body content in a full HTML email with ApexBooks branding."""
    logo_uri = _logo_data_uri()
    logo_img = f'<img src="{logo_uri}" alt="ApexBooks" style="height:60px;margin-bottom:24px;" />' if logo_uri else ""

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>{title}</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f6fa;font-family:Inter,Segoe UI,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f6fa;padding:40px 16px;">
<tr><td align="center">
<table width="480" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.06);">

  <!-- Header -->
  <tr>
    <td style="background-color:#0B1B3D;padding:28px 32px;text-align:center;">
      {logo_img}
      <div style="color:#ffffff;font-size:22px;font-weight:700;letter-spacing:-0.3px;">ApexBooks</div>
      <div style="color:#B0B8CC;font-size:11px;font-weight:500;letter-spacing:0.5px;margin-top:2px;">Accounting Suite</div>
    </td>
  </tr>

  <!-- Body -->
  <tr>
    <td style="padding:32px;">
      {body_html}
    </td>
  </tr>

  <!-- Footer -->
  <tr>
    <td style="padding:20px 32px;background-color:#f8f9fc;border-top:1px solid #e2e5ed;text-align:center;">
      <p style="margin:0;font-size:11px;color:#9CA1AB;">
        This email was sent by ApexBooks &mdash; Accounting Suite.<br/>
        If you did not request this, please ignore or contact your administrator.
      </p>
    </td>
  </tr>

</table>
</td></tr>
</table>
</body>
</html>"""


# ── Public helpers ──────────────────────────────────────────────

def password_reset_email(reset_link: str, user_name: str = "User") -> tuple[str, str]:
    """Returns (subject, html_body) for a password-reset email."""
    body = f"""
      <p style="margin:0 0 16px;font-size:14px;color:#1E293B;">
        Hi <strong>{user_name}</strong>,
      </p>
      <p style="margin:0 0 16px;font-size:14px;color:#1E293B;">
        We received a request to reset your password. Click the button below to set a new one:
      </p>
      <p style="margin:0 0 24px;text-align:center;">
        <a href="{reset_link}"
           style="display:inline-block;padding:12px 28px;background-color:#DCA035;color:#ffffff;font-size:14px;font-weight:600;text-decoration:none;border-radius:6px;">
          Reset Password
        </a>
      </p>
      <p style="margin:0 0 8px;font-size:13px;color:#5F6572;">
        This link expires in <strong>1 hour</strong>.
      </p>
      <p style="margin:0;font-size:13px;color:#5F6572;">
        If you did not request a password reset, you can safely ignore this email.
      </p>
    """
    return ("Password Reset - ApexBooks", _wrap("Password Reset", body))


def purge_otp_email(otp: str, tenant_id: str, user_name: str = "User") -> tuple[str, str]:
    """Returns (subject, html_body) for the company-data-purge OTP email."""
    body = f"""
      <p style="margin:0 0 16px;font-size:14px;color:#1E293B;">
        Hi <strong>{user_name}</strong>,
      </p>
      <p style="margin:0 0 16px;font-size:14px;color:#1E293B;">
        You have requested to purge all data for your company context
        <span style="color:#5F6572;">(Tenant&nbsp;ID: <code>{tenant_id}</code>)</span>.
      </p>
      <p style="margin:0 0 8px;font-size:14px;color:#1E293B;">Your verification OTP code is:</p>
      <p style="margin:0 0 24px;text-align:center;">
        <span style="display:inline-block;padding:12px 28px;background-color:#0B1B3D;color:#ffffff;font-size:22px;font-weight:700;letter-spacing:4px;border-radius:6px;">
          {otp}
        </span>
      </p>
      <p style="margin:0 0 8px;font-size:13px;color:#5F6572;">
        This OTP is valid for <strong>5 minutes</strong>.
      </p>
      <p style="margin:0;font-size:13px;color:#D92D20;font-weight:600;">
        Warning: Purging data will permanently delete all invoices, bills, payments,
        contacts, products, and expenses. This action cannot be undone.
      </p>
    """
    return ("Verify Company Data Purge - ApexBooks", _wrap("Data Purge Verification", body))


def invoice_email(invoice_number: str, company_name: str = "ApexBooks") -> tuple[str, str]:
    """Returns (subject, html_body) for an invoice-sent email."""
    body = f"""
      <p style="margin:0 0 16px;font-size:14px;color:#1E293B;">
        Please find your invoice attached.
      </p>
      <table width="100%" cellpadding="8" cellspacing="0" style="border:1px solid #e2e5ed;border-radius:8px;margin-bottom:24px;">
        <tr>
          <td style="font-size:13px;color:#5F6572;">Invoice</td>
          <td style="font-size:13px;font-weight:600;color:#1E293B;">#{invoice_number}</td>
        </tr>
        <tr>
          <td style="font-size:13px;color:#5F6572;">From</td>
          <td style="font-size:13px;font-weight:600;color:#1E293B;">{company_name}</td>
        </tr>
      </table>
      <p style="margin:0;font-size:13px;color:#5F6572;">
        If you have any questions, please reply to this email.
      </p>
    """
    return (f"Invoice #{invoice_number} - {company_name}", _wrap("Invoice", body))
