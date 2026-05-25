import React, { useState } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, AlertCircle, Plus, Trash2 } from "lucide-react";

interface CreditNoteFormProps {
  onSuccess: () => void;
  onNavigate: (view: "credit_notes" | "credit_note_create" | "credit_note_detail") => void;
}

interface InvoiceItem {
  id: string;
  invoice_number: string;
  total: number;
  contact_name: string;
}

interface ProductItem {
  id: string;
  name: string;
  sku: string;
  hsn_sac: string;
  selling_price: number;
  gst_rate: number;
}

interface CreditNoteLineItem {
  product_id: string;
  quantity: number;
  rate: number;
  discount: number;
  hsn_sac: string;
  gst_rate: number;
}

const STATE_CODES = [
  { code: "01", name: "Jammu & Kashmir (01)" },
  { code: "07", name: "Delhi (07)" },
  { code: "09", name: "Uttar Pradesh (09)" },
  { code: "19", name: "West Bengal (19)" },
  { code: "24", name: "Gujarat (24)" },
  { code: "27", name: "Maharashtra (27)" },
  { code: "29", name: "Karnataka (29)" },
  { code: "33", name: "Tamil Nadu (33)" },
  { code: "36", name: "Telangana (36)" },
  { code: "37", name: "Andhra Pradesh (37)" },
];

export default function CreditNoteForm({ onSuccess, onNavigate }: CreditNoteFormProps) {
  const [invoiceId, setInvoiceId] = useState("");
  const [issueDate, setIssueDate] = useState(new Date().toISOString().split("T")[0]);
  const [reason, setReason] = useState("");
  const [posStateCode, setPosStateCode] = useState("27");
  const [lines, setLines] = useState<CreditNoteLineItem[]>([
    { product_id: "", quantity: 1, rate: 0, discount: 0, hsn_sac: "", gst_rate: 18 },
  ]);
  const [formError, setFormError] = useState("");

  const { data: invoices = [] } = useQuery<InvoiceItem[]>({
    queryKey: ["invoices"],
    queryFn: async () => {
      const res = await apiClient.get("/invoices");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const { data: products = [] } = useQuery<ProductItem[]>({
    queryKey: ["products"],
    queryFn: async () => {
      const res = await apiClient.get("/products");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const handleLineProductChange = (index: number, productId: string) => {
    const prod = products.find((p) => p.id === productId);
    if (prod) {
      const newLines = [...lines];
      newLines[index] = {
        product_id: productId,
        quantity: newLines[index].quantity || 1,
        rate: prod.selling_price,
        discount: 0,
        hsn_sac: prod.hsn_sac,
        gst_rate: prod.gst_rate,
      };
      setLines(newLines);
    }
  };

  const handleLineChange = (index: number, field: keyof CreditNoteLineItem, value: any) => {
    const newLines = [...lines];
    newLines[index] = { ...newLines[index], [field]: value };
    setLines(newLines);
  };

  const addLine = () =>
    setLines([...lines, { product_id: "", quantity: 1, rate: 0, discount: 0, hsn_sac: "", gst_rate: 18 }]);

  const removeLine = (index: number) => {
    if (lines.length > 1) setLines(lines.filter((_, i) => i !== index));
  };

  const calculateTotals = () => {
    let subtotal = 0;
    let cgst = 0;
    let sgst = 0;
    let igst = 0;

    lines.forEach((line) => {
      const itemSubtotal = (line.quantity || 0) * (line.rate || 0) - (line.discount || 0);
      subtotal += itemSubtotal;
      const tax = itemSubtotal * ((line.gst_rate || 0) / 100);
      cgst += tax / 2;
      sgst += tax / 2;
    });

    return { subtotal, cgst, sgst, igst, grandTotal: subtotal + cgst + sgst + igst };
  };

  const totals = calculateTotals();

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(val);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        invoice_id: invoiceId || undefined,
        issue_date: issueDate,
        reason,
        pos_state_code: posStateCode,
        line_items: lines.map((l) => ({
          product_id: l.product_id,
          quantity: l.quantity,
          rate: l.rate,
          discount: l.discount,
          hsn_sac: l.hsn_sac,
          gst_rate: l.gst_rate,
        })),
      };
      return apiClient.post("/credit-notes", payload);
    },
    onSuccess: () => {
      onSuccess();
    },
    onError: (err: any) => {
      setFormError(err.response?.data?.detail || "Failed to save credit note.");
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    if (!reason.trim()) {
      setFormError("Reason is required.");
      return;
    }
    if (lines.some((l) => !l.product_id)) {
      setFormError("Please select a product for all line items.");
      return;
    }

    saveMutation.mutate();
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={() => onNavigate("credit_notes")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">New Credit Note</h1>
      </div>

      {formError && (
        <div className="flex items-start gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-sm"><span className="font-semibold">Error:</span> {formError}</div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Header fields */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">
              Linked Invoice (Optional)
            </label>
            <select
              value={invoiceId}
              onChange={(e) => setInvoiceId(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              <option value="">-- No Linked Invoice --</option>
              {invoices.map((inv) => (
                <option key={inv.id} value={inv.id}>
                  {inv.invoice_number} — {inv.contact_name}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Issue Date</label>
            <input
              type="date"
              value={issueDate}
              onChange={(e) => setIssueDate(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Place of Supply (POS)</label>
            <select
              value={posStateCode}
              onChange={(e) => setPosStateCode(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              {STATE_CODES.map((s) => (
                <option key={s.code} value={s.code}>{s.name}</option>
              ))}
            </select>
          </div>

          <div className="space-y-2 md:col-span-3">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Reason</label>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={2}
              placeholder="Reason for issuing credit note (e.g. goods returned, billing error)..."
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>
        </div>

        {/* Line Items */}
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
          <div className="bg-slate-50 border-b border-slate-100 px-6 py-3.5 flex justify-between items-center">
            <span className="font-semibold text-sm text-slate-700">Line Items</span>
            <button type="button" onClick={addLine}
              className="inline-flex items-center gap-1.5 text-xs font-semibold text-brand-600 hover:text-brand-700 transition">
              <Plus className="w-4 h-4" /> Add Item
            </button>
          </div>

          <div className="p-6 space-y-4">
            {lines.map((line, idx) => (
              <div key={idx} className="flex flex-col md:flex-row items-start md:items-center gap-4 border-b border-slate-50 pb-4 last:border-0 last:pb-0">
                <div className="flex-1 min-w-[200px] space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">Item</label>
                  <select
                    value={line.product_id}
                    onChange={(e) => handleLineProductChange(idx, e.target.value)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm bg-white focus:ring-1 focus:ring-brand-500 focus:outline-none"
                  >
                    <option value="">-- Choose Product --</option>
                    {products.map((p) => (
                      <option key={p.id} value={p.id}>{p.name} ({p.sku})</option>
                    ))}
                  </select>
                </div>

                <div className="w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">HSN/SAC</label>
                  <input type="text" value={line.hsn_sac} readOnly
                    className="w-full px-2 py-1.5 border border-slate-100 bg-slate-50 text-slate-500 rounded text-sm focus:outline-none" />
                </div>

                <div className="w-20 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">Qty</label>
                  <input type="number" min="1" step="any" value={line.quantity}
                    onChange={(e) => handleLineChange(idx, "quantity", parseFloat(e.target.value) || 0)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm focus:ring-1 focus:ring-brand-500 focus:outline-none" />
                </div>

                <div className="w-28 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">Rate (₹)</label>
                  <input type="number" min="0" step="0.01" value={line.rate}
                    onChange={(e) => handleLineChange(idx, "rate", parseFloat(e.target.value) || 0)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm focus:ring-1 focus:ring-brand-500 focus:outline-none" />
                </div>

                <div className="w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">Discount (₹)</label>
                  <input type="number" min="0" step="0.01" value={line.discount}
                    onChange={(e) => handleLineChange(idx, "discount", parseFloat(e.target.value) || 0)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm focus:ring-1 focus:ring-brand-500 focus:outline-none" />
                </div>

                <div className="w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">GST %</label>
                  <select value={line.gst_rate}
                    onChange={(e) => handleLineChange(idx, "gst_rate", parseFloat(e.target.value) || 0)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm bg-white focus:ring-1 focus:ring-brand-500 focus:outline-none">
                    <option value="0">0%</option>
                    <option value="5">5%</option>
                    <option value="12">12%</option>
                    <option value="18">18%</option>
                    <option value="28">28%</option>
                  </select>
                </div>

                <div className="w-28 space-y-1 text-right">
                  <span className="block text-[10px] font-semibold text-slate-400 uppercase">Subtotal</span>
                  <span className="text-sm font-semibold text-slate-700 block py-1.5">
                    {formatCurrency(line.quantity * line.rate - line.discount)}
                  </span>
                </div>

                <div className="self-end md:self-center py-1.5">
                  <button type="button" onClick={() => removeLine(idx)} disabled={lines.length === 1}
                    className="p-1.5 text-slate-400 hover:text-rose-600 rounded hover:bg-rose-50 disabled:opacity-30 transition">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Totals */}
        <div className="flex justify-end">
          <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm w-72 space-y-3">
            <h3 className="font-semibold text-sm text-slate-700 pb-2 border-b border-slate-100">Credit Note Totals</h3>
            <div className="flex justify-between text-sm text-slate-600">
              <span>Subtotal</span><span>{formatCurrency(totals.subtotal)}</span>
            </div>
            {totals.cgst > 0 && (
              <div className="flex justify-between text-xs text-slate-500 italic pl-2">
                <span>CGST</span><span>{formatCurrency(totals.cgst)}</span>
              </div>
            )}
            {totals.sgst > 0 && (
              <div className="flex justify-between text-xs text-slate-500 italic pl-2">
                <span>SGST</span><span>{formatCurrency(totals.sgst)}</span>
              </div>
            )}
            <div className="flex justify-between text-base font-bold text-slate-900 pt-2 border-t border-slate-100">
              <span>Grand Total</span><span className="text-brand-900">{formatCurrency(totals.grandTotal)}</span>
            </div>
          </div>
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-3">
          <button type="button" onClick={() => onNavigate("credit_notes")}
            className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition">
            Cancel
          </button>
          <button type="submit" disabled={saveMutation.isPending}
            className="px-6 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50">
            {saveMutation.isPending ? "Saving..." : "Create Credit Note"}
          </button>
        </div>
      </form>
    </div>
  );
}
