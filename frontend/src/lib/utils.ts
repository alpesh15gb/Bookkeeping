// ── Internal helpers ──

/** Coerce any numeric-compatible value to a proper number */
function toNum(v: number | string | any): number {
  if (typeof v === "number") return v;
  const n = Number(v);
  return isNaN(n) ? 0 : n;
}

// ── Currency & Number Formatting ──

/**
 * Format a number using Indian numbering system.
 * 100000  → "1,00,000"
 * 5000000 → "50,00,000"
 */
export function formatIndianNumber(num: number | string): string {
  const n = toNum(num);
  const sign = n < 0 ? "-" : "";
  const abs = Math.abs(n);
  const [integerPart, decimalPart] = abs.toFixed(2).split(".");

  const lastThree = integerPart.slice(-3);
  const otherNumbers = integerPart.slice(0, -3);
  const formatted =
    otherNumbers.replace(/\B(?=(\d{2})+(?!\d))/g, ",") +
    (otherNumbers.length > 0 ? "," : "") +
    lastThree;

  return sign + formatted + "." + decimalPart;
}

/**
 * Format amount in Indian Rupee format with ₹ symbol.
 * @param amount numeric amount (handles both number and string)
 * @param compact if true, show in Lakhs/Crores for large values
 * @param showSymbol if false, omit ₹ symbol
 */
export function formatIndianCurrency(
  amount: number | string,
  compact: boolean = false,
  showSymbol: boolean = true,
): string {
  const n = toNum(amount);
  const symbol = showSymbol ? "₹" : "";
  const sign = n < 0 ? "-" : "";
  const abs = Math.abs(n);

  if (compact && abs >= 10_000_000) {
    return `${sign}${symbol}${(abs / 10_000_000).toFixed(2)}Cr`;
  }
  if (compact && abs >= 100_000) {
    return `${sign}${symbol}${(abs / 100_000).toFixed(2)}L`;
  }

  const [integerPart, decimalPart] = abs.toFixed(2).split(".");
  const lastThree = integerPart.slice(-3);
  const otherNumbers = integerPart.slice(0, -3);
  const formatted =
    otherNumbers.replace(/\B(?=(\d{2})+(?!\d))/g, ",") +
    (otherNumbers.length > 0 ? "," : "") +
    lastThree;

  return `${sign}${symbol}${formatted}.${decimalPart}`;
}

/**
 * Format amount for display in MetricCards.
 * Shows compact (L/Cr) with label for large amounts,
 * or precise with Indian commas for smaller.
 */
export function formatMetricAmount(amount: number | string): {
  value: string;
  suffix: string;
} {
  const n = toNum(amount);
  const abs = Math.abs(n);
  if (abs >= 10_000_000) return { value: (n / 10_000_000).toFixed(2), suffix: "Cr" };
  if (abs >= 100_000) return { value: (n / 100_000).toFixed(2), suffix: "L" };
  if (abs >= 1_000) return { value: formatIndianNumber(n).replace(/\.00$/, ""), suffix: "" };
  return { value: n.toFixed(2), suffix: "" };
}

// ── Date Formatting ──

/**
 * Format ISO date string to Indian locale: "28 May 2026"
 */
export function formatDate(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleDateString("en-IN", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/**
 * Format ISO date to short DD/MM/YYYY (Indian format)
 */
export function formatDateShort(dateStr: string): string {
  const d = new Date(dateStr);
  const day = String(d.getDate()).padStart(2, "0");
  const month = String(d.getMonth() + 1).padStart(2, "0");
  return `${day}/${month}/${d.getFullYear()}`;
}

/**
 * Get today's date as YYYY-MM-DD string
 */
export function todayISO(): string {
  return new Date().toISOString().split("T")[0];
}

/**
 * Add days to a date and return ISO string
 */
export function addDays(isoDate: string, days: number): string {
  const d = new Date(isoDate);
  d.setDate(d.getDate() + days);
  return d.toISOString().split("T")[0];
}

// ── GST & Indian Business Validators ──

/** Validates a 15-character GSTIN */
export function validateGSTIN(gstin: string): boolean {
  const clean = gstin.replace(/\s/g, "").toUpperCase();
  return /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}[Z]{1}[0-9A-Z]{1}$/.test(clean);
}

/** Validates a 10-character PAN */
export function validatePAN(pan: string): boolean {
  const clean = pan.replace(/\s/g, "").toUpperCase();
  return /^[A-Z]{5}[0-9]{4}[A-Z]{1}$/.test(clean);
}

/** Extract state code from GSTIN (first 2 characters) */
export function gstinStateCode(gstin: string): string {
  return gstin.replace(/\s/g, "").substring(0, 2);
}

/** Check if two state codes represent the same state → intrastate */
export function isIntrastate(stateCode1: string, stateCode2: string): boolean {
  return stateCode1 === stateCode2;
}

/** Validates Indian mobile number (10 digits, starting with 6-9) */
export function validateIndianMobile(mobile: string): boolean {
  const clean = mobile.replace(/\D/g, "");
  return /^[6-9]\d{9}$/.test(clean);
}

/** Validates IFSC code */
export function validateIFSC(ifsc: string): boolean {
  return /^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifsc.toUpperCase());
}

/** Validates UPI ID */
export function validateUPI(upi: string): boolean {
  return /^[\w.]+@[\w]+$/.test(upi);
}

// ── HSN / SAC ──

/** Validates 4-8 digit HSN/SAC code */
export function validateHSN(hsn: string): boolean {
  return /^\d{4,8}$/.test(hsn);
}

// ── Format helpers for display ──

/** Format GST rate as "18%" */
export function formatGSTRate(rate: number): string {
  return `${rate}%`;
}

/** Truncate UUID to short display form */
export function shortId(uuid: string): string {
  return uuid.substring(0, 8).toUpperCase();
}

/** Capitalize first letter */
export function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
}

/** WhatsApp share URL builder */
export function whatsAppShareURL(message: string): string {
  return `https://wa.me/?text=${encodeURIComponent(message)}`;
}

// ── Tax calculation helper ──

export interface TaxBreakdown {
  taxableAmount: number;
  cgstRate: number;
  cgstAmount: number;
  sgstRate: number;
  sgstAmount: number;
  igstRate: number;
  igstAmount: number;
  totalTax: number;
  total: number;
}

/**
 * Calculate GST for a single line item.
 * @param amount taxable amount
 * @param gstRate GST rate percentage (e.g., 18)
 * @param isInterstate if true → IGST only; if false → CGST + SGST
 */
export function calculateLineGST(
  amount: number,
  gstRate: number,
  isInterstate: boolean,
): TaxBreakdown {
  const taxAmount = (amount * gstRate) / 100;

  if (isInterstate) {
    return {
      taxableAmount: amount,
      cgstRate: 0,
      cgstAmount: 0,
      sgstRate: 0,
      sgstAmount: 0,
      igstRate: gstRate,
      igstAmount: taxAmount,
      totalTax: taxAmount,
      total: amount + taxAmount,
    };
  }

  const half = taxAmount / 2;
  return {
    taxableAmount: amount,
    cgstRate: gstRate / 2,
    cgstAmount: half,
    sgstRate: gstRate / 2,
    sgstAmount: half,
    igstRate: 0,
    igstAmount: 0,
    totalTax: taxAmount,
    total: amount + taxAmount,
  };
}

/** Round to nearest rupee (for round-off calculation) */
export function roundToNearestRupee(amount: number): number {
  return Math.round(amount);
}
