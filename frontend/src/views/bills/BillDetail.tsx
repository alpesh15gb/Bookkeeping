import React, { useState, useEffect } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Printer, ShieldCheck, Banknote, X, AlertTriangle, Download } from "lucide-react";

interface BillDetailProps {
  billId: string;
  onNavigate: (view: "bill_list" | "bill_create" | "bill_edit" | "bill_detail", billId?: string) => void;
}

export default function BillDetail({ billId, onNavigate }: BillDetailProps) {
  const queryClient = useQueryClient();
  const [showPaymentModal, setShowPaymentModal] = useState(false);
  const [showPrintModal, setShowPrintModal] = useState(false);

  // Payment form states
  const [paymentMode, setPaymentMode] = useState("BANK");
  const [paymentAmount, setPaymentAmount] = useState(0);
  const [referenceNum, setReferenceNum] = useState("");
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().split("T")[0]);
  const [paymentError, setPaymentError] = useState("");

  // Fetch Bill complete details
  const { data: bill, isLoading, error } = useQuery({
    queryKey: ["bill", billId],
    queryFn: async () => {
      const res = await apiClient.get(`/bills/${billId}`);
      return res.data;
    },
  });

  // Finalize Mutation
  const finalizeMutation = useMutation({
    mutationFn: async () => {
      return apiClient.post(`/bills/${billId}/finalize`);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["bill", billId] });
      queryClient.invalidateQueries({ queryKey: ["bills"] });
    },
  });

  // Record Payment Out Mutation
  const paymentMutation = useMutation({
    mutationFn: async () => {
      const randSeq = Math.floor(1000 + Math.random() * 9000);
      const payload = {
        contact_id: bill.contact_id,
        payment_number: `VPAY/2026-27/${randSeq}`,
        payment_date: paymentDate,
        payment_mode: paymentMode,
        amount: paymentAmount,
        reference_number: referenceNum,
        description: `Vendor payment for bill ${bill.bill_number}`,
        allocations: [
          {
            bill_id: billId,
            amount: paymentAmount,
          },
        ],
      };
      return apiClient.post(`/bills/${billId}/payment`, payload);
    },
    onSuccess: () => {
      setShowPaymentModal(false);
      setPaymentError("");
      queryClient.invalidateQueries({ queryKey: ["bill", billId] });
      queryClient.invalidateQueries({ queryKey: ["bills"] });
    },
    onError: (err: any) => {
      const msg = err.response?.data?.detail || "Failed to record payment out. Check parameters.";
      setPaymentError(msg);
    },
  });

  const { data: printData } = useQuery({
    queryKey: ["bill-print", billId],
    queryFn: async () => {
      const res = await apiClient.get(`/bills/${billId}/pdf-payload`);
      return res.data;
    },
    enabled: showPrintModal,
  });

  useEffect(() => {
    if (printData && showPrintModal) {
      const formatCurrency = (v: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(v);
      const docNumber = printData.bill?.invoice_number || printData.bill?.bill_number || "";
      const html = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<title>Bill ${docNumber}</title>
<style>
  body { font-family: Arial, sans-serif; margin: 40px; color: #333; }
  .header { display: flex; justify-content: space-between; border-bottom: 2px solid #333; padding-bottom: 20px; margin-bottom: 20px; }
  .company h1 { margin: 0; font-size: 24px; color: #1e40af; }
  .invoice-info { text-align: right; }
  .invoice-info h2 { font-size: 20px; margin: 0 0 5px 0; }
  table { width: 100%; border-collapse: collapse; margin: 20px 0; }
  th { background: #f1f5f9; padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
  td { padding: 10px; border-bottom: 1px solid #eee; }
  .text-right { text-align: right; }
  .totals { margin-top: 20px; }
  .totals tr td { border: none; padding: 4px 10px; }
  .totals .grand-total { font-size: 18px; font-weight: bold; border-top: 2px solid #333; }
  .bank-info { margin-top: 30px; background: #f8fafc; padding: 15px; border-radius: 8px; }
  @media print { body { margin: 20px; } }
</style>
</head>
<body>
<div class="header">
  <div class="company">
    <h1>${printData.company?.legal_name || ""}</h1>
    ${printData.company?.gstin ? `<p>GSTIN: ${printData.company.gstin}</p>` : ""}
    ${printData.bank_details?.bank_name ? `<p>Bank: ${printData.bank_details.bank_name}, A/C: ${printData.bank_details.account_number}, IFSC: ${printData.bank_details.ifsc_code}</p>` : ""}
  </div>
  <div class="invoice-info">
    <h2>Bill</h2>
    <p><strong>${docNumber}</strong></p>
    <p>Date: ${printData.bill?.issue_date ? new Date(printData.bill.issue_date).toLocaleDateString("en-IN") : ""}</p>
    <p>Due: ${printData.bill?.due_date ? new Date(printData.bill.due_date).toLocaleDateString("en-IN") : ""}</p>
  </div>
</div>

<div style="margin-bottom: 20px;">
  <strong>Bill From:</strong>
  <p>${printData.customer?.name || ""} ${printData.customer?.gstin ? "<br>GSTIN: " + printData.customer.gstin : ""}</p>
  ${printData.customer?.billing_address ? `<p>${printData.customer.billing_address.street || ""}<br>${printData.customer.billing_address.city || ""}, ${printData.customer.billing_address.state || ""} - ${printData.customer.billing_address.pincode || ""}</p>` : ""}
</div>

<table>
  <thead><tr>
    <th>#</th><th>Item</th><th>HSN</th><th class="text-right">Qty</th>
    <th class="text-right">Rate</th><th class="text-right">Discount</th>
    <th class="text-right">Tax</th><th class="text-right">Amount</th>
  </tr></thead>
  <tbody>
    ${(printData.lines || []).map((l: any, i: number) => `
    <tr>
      <td>${i + 1}</td>
      <td>${l.product_name || ""}</td>
      <td>${l.hsn_sac || ""}</td>
      <td class="text-right">${l.quantity}</td>
      <td class="text-right">${formatCurrency(l.rate)}</td>
      <td class="text-right">${l.discount > 0 ? formatCurrency(l.discount) : "—"}</td>
      <td class="text-right">${l.gst_rate}%</td>
      <td class="text-right">${formatCurrency(l.total)}</td>
    </tr>`).join("")}
  </tbody>
</table>

<table class="totals">
  <tr><td colspan="7" class="text-right"><strong>Subtotal:</strong></td><td class="text-right">${formatCurrency(printData.bill?.subtotal || 0)}</td></tr>
  ${(printData.bill?.cgst_amount || 0) > 0 ? `<tr><td colspan="7" class="text-right">CGST:</td><td class="text-right">${formatCurrency(printData.bill.cgst_amount)}</td></tr>` : ""}
  ${(printData.bill?.sgst_amount || 0) > 0 ? `<tr><td colspan="7" class="text-right">SGST:</td><td class="text-right">${formatCurrency(printData.bill.sgst_amount)}</td></tr>` : ""}
  ${(printData.bill?.igst_amount || 0) > 0 ? `<tr><td colspan="7" class="text-right">IGST:</td><td class="text-right">${formatCurrency(printData.bill.igst_amount)}</td></tr>` : ""}
  <tr class="grand-total"><td colspan="7" class="text-right"><strong>Total:</strong></td><td class="text-right"><strong>${formatCurrency(printData.bill?.total || 0)}</strong></td></tr>
</table>

<script>window.onload = () => { window.print(); }</script>
</body></html>`;
      const win = window.open("", "_blank");
      if (win) {
        win.document.write(html);
        win.document.close();
      }
      setShowPrintModal(false);
    }
  }, [printData, showPrintModal]);

  const openPaymentModal = () => {
    if (bill) {
      setPaymentAmount(bill.total - bill.amount_paid);
      setShowPaymentModal(true);
    }
  };

  const handlePaymentSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (paymentAmount <= 0) {
      setPaymentError("Payment amount must be greater than zero.");
      return;
    }
    const remaining = bill.total - bill.amount_paid;
    if (paymentAmount > remaining) {
      setPaymentError(`Payment amount cannot exceed remaining balance of ${formatCurrency(remaining)}`);
      return;
    }
    paymentMutation.mutate();
  };

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
    }).format(val);
  };

  const getStatusColor = (status: string) => {
    switch (status?.toUpperCase()) {
      case "DRAFT":
        return "bg-slate-100 text-slate-700 border-slate-200";
      case "UNPAID":
        return "bg-amber-50 text-amber-700 border-amber-200";
      case "PARTIALLY_PAID":
        return "bg-indigo-50 text-indigo-700 border-indigo-200";
      case "PAID":
        return "bg-emerald-50 text-emerald-700 border-emerald-200";
      case "CANCELLED":
        return "bg-rose-50 text-rose-700 border-rose-200";
      default:
        return "bg-slate-100 text-slate-700";
    }
  };

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (error || !bill) {
    return (
      <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
        <AlertTriangle className="w-5 h-5 flex-shrink-0" />
        <span>Error retrieving vendor bill detail files.</span>
      </div>
    );
  }

  const remainingBalance = bill.total - bill.amount_paid;

  return (
    <div className="space-y-6">
      {/* Action Header */}
      <div className="flex justify-between items-center no-print">
        <div className="flex items-center gap-3">
          <button
            onClick={() => onNavigate("bill_list")}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-xl font-bold text-slate-900 font-mono">{bill.bill_number}</h1>
          <span className={`px-2.5 py-0.5 text-xs font-semibold rounded-full border ${getStatusColor(bill.status)}`}>
            {bill.status}
          </span>
        </div>

        <div className="flex gap-2">
          <button
            onClick={() => setShowPrintModal(true)}
            disabled={showPrintModal}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-semibold border border-slate-200 text-slate-700 bg-white hover:bg-slate-50 rounded-lg transition disabled:opacity-50"
          >
            {showPrintModal ? <Download className="w-4 h-4" /> : <Printer className="w-4 h-4" />} {showPrintModal ? "Preparing Print..." : "Print"}
          </button>

          {bill.status === "DRAFT" && (
            <button
              onClick={() => finalizeMutation.mutate()}
              disabled={finalizeMutation.isPending}
              className="inline-flex items-center gap-1.5 px-4 py-1.5 text-sm font-semibold bg-brand-600 hover:bg-brand-700 text-white rounded-lg transition shadow-sm"
            >
              <ShieldCheck className="w-4 h-4" />
              {finalizeMutation.isPending ? "Posting..." : "Finalize & Post"}
            </button>
          )}

          {bill.status !== "DRAFT" && bill.status !== "PAID" && (
            <button
              onClick={openPaymentModal}
              className="inline-flex items-center gap-1.5 px-4 py-1.5 text-sm font-semibold bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg transition shadow-sm"
            >
              <Banknote className="w-4 h-4" />
              Record Payment Out
            </button>
          )}
        </div>
      </div>

      {/* Bill Sheet */}
      <div className="bg-white p-8 rounded-xl border border-slate-100 shadow-sm print-box">
        <div className="grid grid-cols-1 md:grid-cols-2 justify-between items-start border-b border-slate-100 pb-8 gap-8">
          <div>
            <span className="text-xs font-bold uppercase tracking-wider text-slate-400">Vendor (Pay to)</span>
            <h2 className="text-lg font-bold text-slate-900 mt-1">{bill.contact.name}</h2>
            {bill.contact.billing_address && (
              <div className="text-sm text-slate-500 mt-1">
                <p>{bill.contact.billing_address.street}</p>
                <p>
                  {bill.contact.billing_address.city}, {bill.contact.billing_address.state} -{" "}
                  {bill.contact.billing_address.pincode}
                </p>
              </div>
            )}
            {bill.contact.gstin && (
              <p className="text-sm font-semibold text-slate-700 mt-2">
                GSTIN: {bill.contact.gstin}
              </p>
            )}
          </div>

          <div className="md:text-right">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-400">Buyer Company</span>
            <h2 className="text-lg font-bold text-slate-900 mt-1">Varma Logistics Private Limited</h2>
            <p className="text-sm text-slate-500 mt-1">101, Business Hub, Andheri East</p>
            <p className="text-sm text-slate-500">Mumbai, Maharashtra - 400069</p>
            <p className="text-sm font-semibold text-slate-700 mt-2 md:text-right">GSTIN: 27AAAAA1111A1Z5</p>
          </div>
        </div>

        {/* Metadata */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 py-8 border-b border-slate-100 text-sm">
          <div>
            <span className="text-slate-400 font-semibold block uppercase text-[10px] tracking-wider">Bill Date</span>
            <span className="font-semibold text-slate-700 mt-1 block">
              {new Date(bill.issue_date).toLocaleDateString("en-IN")}
            </span>
          </div>
          <div>
            <span className="text-slate-400 font-semibold block uppercase text-[10px] tracking-wider">Due Date</span>
            <span className="font-semibold text-slate-700 mt-1 block">
              {new Date(bill.due_date).toLocaleDateString("en-IN")}
            </span>
          </div>
          <div>
            <span className="text-slate-400 font-semibold block uppercase text-[10px] tracking-wider">Place of Supply</span>
            <span className="font-semibold text-slate-700 mt-1 block font-mono">State Code: {bill.pos_state_code}</span>
          </div>
          <div>
            <span className="text-slate-400 font-semibold block uppercase text-[10px] tracking-wider">ITC Status</span>
            <span className="font-semibold text-emerald-700 mt-1 block flex items-center gap-1">
              <ShieldCheck className="w-4 h-4 text-emerald-600" />
              ITC Eligible
            </span>
          </div>
        </div>

        {/* Line Items */}
        <table className="w-full border-collapse text-left text-sm mt-8">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-100 text-slate-500 font-semibold">
              <th className="px-4 py-2.5">#</th>
              <th className="px-4 py-2.5">Item Description</th>
              <th className="px-4 py-2.5">HSN/SAC</th>
              <th className="px-4 py-2.5 text-right">Qty</th>
              <th className="px-4 py-2.5 text-right">Rate</th>
              <th className="px-4 py-2.5 text-right">Discount</th>
              <th className="px-4 py-2.5 text-right">GST Rate</th>
              <th className="px-4 py-2.5 text-right">Amount</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {bill.lines.map((line: any, idx: number) => (
              <tr key={line.id} className="text-slate-700">
                <td className="px-4 py-3 text-slate-400">{idx + 1}</td>
                <td className="px-4 py-3 font-semibold">{line.product?.name || "Product Item"}</td>
                <td className="px-4 py-3 font-mono">{line.hsn_sac}</td>
                <td className="px-4 py-3 text-right">{parseFloat(line.quantity)}</td>
                <td className="px-4 py-3 text-right">{formatCurrency(parseFloat(line.rate))}</td>
                <td className="px-4 py-3 text-right text-rose-600">
                  {parseFloat(line.discount) > 0 ? `-${formatCurrency(parseFloat(line.discount))}` : "—"}
                </td>
                <td className="px-4 py-3 text-right">{parseFloat(line.gst_rate)}%</td>
                <td className="px-4 py-3 text-right font-semibold">
                  {formatCurrency(parseFloat(line.total))}
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {/* Totals & Tax splits */}
        <div className="grid grid-cols-1 md:grid-cols-2 mt-8 pt-8 border-t border-slate-100 gap-8">
          <div>
            <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 mb-2">GST Input Tax Credit (ITC) Summary</h3>
            <table className="w-full text-left text-xs border border-slate-100">
              <thead className="bg-slate-50 text-slate-500 font-semibold">
                <tr>
                  <th className="p-2 border-b border-slate-100">HSN</th>
                  <th className="p-2 border-b border-slate-100 text-right">Taxable Val</th>
                  <th className="p-2 border-b border-slate-100 text-right">ITC Splits</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {bill.lines.map((l: any) => (
                  <tr key={l.id}>
                    <td className="p-2 font-mono">{l.hsn_sac}</td>
                    <td className="p-2 text-right">{formatCurrency(parseFloat(l.subtotal))}</td>
                    <td className="p-2 text-right text-emerald-700 font-semibold">
                      {parseFloat(l.cgst_amount) > 0 && `CGST: ${formatCurrency(parseFloat(l.cgst_amount))} `}
                      {parseFloat(l.sgst_amount) > 0 && `SGST: ${formatCurrency(parseFloat(l.sgst_amount))} `}
                      {parseFloat(l.igst_amount) > 0 && `IGST: ${formatCurrency(parseFloat(l.igst_amount))}`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="space-y-3 md:max-w-md md:ml-auto w-full text-sm">
            <div className="flex justify-between text-slate-500">
              <span>Subtotal</span>
              <span>{formatCurrency(parseFloat(bill.subtotal))}</span>
            </div>
            {parseFloat(bill.discount_total) > 0 && (
              <div className="flex justify-between text-slate-500">
                <span>Discount Total</span>
                <span className="text-rose-600">-{formatCurrency(parseFloat(bill.discount_total))}</span>
              </div>
            )}
            {parseFloat(bill.cgst_amount) > 0 && (
              <div className="flex justify-between text-slate-400 italic pl-2 text-xs">
                <span>Input CGST</span>
                <span>{formatCurrency(parseFloat(bill.cgst_amount))}</span>
              </div>
            )}
            {parseFloat(bill.sgst_amount) > 0 && (
              <div className="flex justify-between text-slate-400 italic pl-2 text-xs">
                <span>Input SGST</span>
                <span>{formatCurrency(parseFloat(bill.sgst_amount))}</span>
              </div>
            )}
            {parseFloat(bill.igst_amount) > 0 && (
              <div className="flex justify-between text-slate-400 italic pl-2 text-xs">
                <span>Input IGST</span>
                <span>{formatCurrency(parseFloat(bill.igst_amount))}</span>
              </div>
            )}
            <div className="flex justify-between text-base font-bold text-slate-900 pt-2 border-t border-slate-100">
              <span>Total Bill Amount</span>
              <span>{formatCurrency(parseFloat(bill.total))}</span>
            </div>
            <div className="flex justify-between text-slate-500 pt-1 text-xs">
              <span>Paid Out Balance</span>
              <span>{formatCurrency(parseFloat(bill.amount_paid))}</span>
            </div>
            <div className="flex justify-between text-brand-900 font-semibold pt-1 border-t border-dotted border-slate-200">
              <span>Outstanding Payable</span>
              <span>{formatCurrency(remainingBalance)}</span>
            </div>
          </div>
        </div>
      </div>

      {/* Record Payment Out Dialog Modal */}
      {showPaymentModal && (
        <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm flex justify-center items-center z-50 no-print">
          <div className="bg-white rounded-xl shadow-xl border border-slate-100 max-w-md w-full overflow-hidden animate-in fade-in zoom-in-95 duration-200">
            <div className="px-6 py-4 bg-slate-50 border-b border-slate-100 flex justify-between items-center">
              <h3 className="font-bold text-slate-800 text-base">Record Payment Out (Disbursement)</h3>
              <button
                onClick={() => setShowPaymentModal(false)}
                className="p-1 hover:bg-slate-200 text-slate-400 hover:text-slate-700 rounded transition"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <form onSubmit={handlePaymentSubmit} className="p-6 space-y-4">
              {paymentError && (
                <div className="p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded text-xs">
                  {paymentError}
                </div>
              )}

              <div className="space-y-1">
                <label className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Payment Mode</label>
                <select
                  value={paymentMode}
                  onChange={(e) => setPaymentMode(e.target.value)}
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
                >
                  <option value="BANK">Bank Transfer (NEFT/RTGS/IMPS)</option>
                  <option value="UPI">UPI (Business ID)</option>
                  <option value="CASH">Cash</option>
                  <option value="POS">Debit Card</option>
                </select>
              </div>

              <div className="space-y-1">
                <label className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Amount Paid (₹)</label>
                <input
                  type="number"
                  step="0.01"
                  value={paymentAmount}
                  onChange={(e) => setPaymentAmount(parseFloat(e.target.value) || 0)}
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  required
                />
              </div>

              <div className="space-y-1">
                <label className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Reference Number (UTR / TXN ID)</label>
                <input
                  type="text"
                  placeholder="e.g. Bank Reference Hash"
                  value={referenceNum}
                  onChange={(e) => setReferenceNum(e.target.value)}
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                />
              </div>

              <div className="space-y-1">
                <label className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">Disbursement Date</label>
                <input
                  type="date"
                  value={paymentDate}
                  onChange={(e) => setPaymentDate(e.target.value)}
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  required
                />
              </div>

              <div className="flex justify-end gap-2 pt-4 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowPaymentModal(false)}
                  className="px-4 py-2 border border-slate-200 text-slate-600 font-semibold rounded-lg text-sm hover:bg-slate-50 transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={paymentMutation.isPending}
                  className="px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded-lg text-sm transition shadow-sm disabled:opacity-50"
                >
                  {paymentMutation.isPending ? "Recording..." : "Disburse Payment"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
