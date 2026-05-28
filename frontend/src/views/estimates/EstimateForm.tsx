import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Plus, Trash2, Save } from "lucide-react";
import { useUnsavedChangesWarning } from "../../hooks/useUnsavedChangesWarning";

interface EstimateFormProps {
  editId?: string;
  onNavigate: (view: "estimate_list" | "estimate_create" | "estimate_edit" | "estimate_detail", id?: string) => void;
  onSuccess: () => void;
}

interface ContactItem {
  id: string; name: string; state_code: string;
}
interface ProductItem {
  id: string; name: string; sales_price: number; gst_rate: number; hsn_sac: string;
}
interface LineDraft {
  product_id: string; product_name: string; quantity: number; rate: number; discount: number; hsn_sac: string; gst_rate: number;
}

export default function EstimateForm({ editId, onNavigate, onSuccess }: EstimateFormProps) {
  const isEdit = Boolean(editId);

  const [contactId, setContactId] = useState("");
  const [estimateNumber, setEstimateNumber] = useState("");
  const [issueDate, setIssueDate] = useState(new Date().toISOString().split("T")[0]);
  const [dueDate, setDueDate] = useState("");
  const [placeOfSupply, setPlaceOfSupply] = useState("");
  const [lines, setLines] = useState<LineDraft[]>([{ product_id: "", product_name: "", quantity: 1, rate: 0, discount: 0, hsn_sac: "", gst_rate: 18 }]);

  useUnsavedChangesWarning(contactId !== "" || lines.some(l => l.product_id !== ""));

  useEffect(() => {
    const d = new Date();
    d.setDate(d.getDate() + 15);
    setDueDate(d.toISOString().split("T")[0]);
  }, []);

  useEffect(() => {
    if (!isEdit && !estimateNumber) {
      const randSeq = Math.floor(100000 + Math.random() * 900000);
      setEstimateNumber(`EST-2025-${randSeq}`);
    }
  }, [isEdit, estimateNumber]);

  const { data: contacts = [] } = useQuery<ContactItem[]>({
    queryKey: ["contacts"],
    queryFn: async () => { const r = await apiClient.get("/contacts"); return r.data; },
  });

  const { data: products = [] } = useQuery<ProductItem[]>({
    queryKey: ["products"],
    queryFn: async () => { const r = await apiClient.get("/masters/products"); return r.data; },
  });

  const { data: existing } = useQuery({
    queryKey: ["estimate", editId],
    queryFn: async () => { const r = await apiClient.get(`/proforma-invoices/${editId}`); return r.data; },
    enabled: isEdit,
  });

  useEffect(() => {
    if (existing) {
      setContactId(existing.contact?.id || "");
      setEstimateNumber(existing.proforma_number || "");
      setIssueDate(existing.issue_date);
      setDueDate(existing.due_date);
      setPlaceOfSupply(existing.pos_state_code || "");
      if (existing.lines?.length) {
        setLines(existing.lines.map((l: any) => ({
          product_id: l.product?.id || l.product_id || "",
          product_name: l.description || l.product?.name || "",
          quantity: Number(l.quantity),
          rate: Number(l.rate),
          discount: Number(l.discount || 0),
          hsn_sac: l.hsn_sac || "",
          gst_rate: Number(l.gst_rate || 18),
        })));
      }
    }
  }, [existing]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        contact_id: contactId,
        proforma_number: estimateNumber,
        issue_date: issueDate,
        due_date: dueDate,
        pos_state_code: placeOfSupply,
        line_items: lines.map(l => ({
          product_id: l.product_id,
          quantity: l.quantity,
          rate: l.rate,
          discount: l.discount,
          hsn_sac: l.hsn_sac,
          gst_rate: l.gst_rate,
        })),
      };
      if (isEdit) await apiClient.put(`/proforma-invoices/${editId}`, payload);
      else await apiClient.post("/proforma-invoices", payload);
    },
    onSuccess: () => onSuccess(),
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!contactId || !issueDate || !dueDate || !placeOfSupply || lines.some(l => !l.product_id)) return;
    saveMutation.mutate();
  };

  const addLine = () => setLines([...lines, { product_id: "", product_name: "", quantity: 1, rate: 0, discount: 0, hsn_sac: "", gst_rate: 18 }]);
  const removeLine = (i: number) => { if (lines.length > 1) setLines(lines.filter((_, idx) => idx !== i)); };

  const handleProductSelect = (i: number, pid: string) => {
    const p = products.find(pr => pr.id === pid);
    setLines(lines.map((l, idx) => idx === i ? {
      ...l, product_id: pid, product_name: p?.name || "",
      rate: p?.sales_price || l.rate,
      hsn_sac: p?.hsn_sac || "",
      gst_rate: p?.gst_rate || 18,
    } : l));
  };

  const handleCustomerChange = (selectedContactId: string) => {
    setContactId(selectedContactId);
    const selected = contacts.find((c) => c.id === selectedContactId);
    if (selected) {
      setPlaceOfSupply(selected.state_code);
    }
  };

  const total = lines.reduce((s, l) => s + l.quantity * l.rate - l.discount, 0);

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button onClick={() => onNavigate("estimate_list")} className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">{isEdit ? "Edit Estimate" : "New Estimate"}</h1>
          <p className="text-xs text-zinc-500 mt-0.5">Create a quotation or proforma invoice for your customer.</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-5">
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-6 space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <div className="space-y-2">
              <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Customer *</label>
              <select value={contactId} onChange={(e) => handleCustomerChange(e.target.value)}
                className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500" required>
                <option value="">Select customer...</option>
                {contacts.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </div>
            <div className="space-y-2">
              <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Issue Date *</label>
              <input type="date" value={issueDate} onChange={(e) => setIssueDate(e.target.value)}
                className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" required />
            </div>
            <div className="space-y-2">
              <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Valid Until *</label>
              <input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)}
                className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" required />
            </div>
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-6 space-y-4">
          <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider">Line Items</h3>
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="text-xs text-zinc-500 font-bold uppercase tracking-wider border-b border-zinc-100">
                <th className="pb-2 pr-2">Item</th>
                <th className="pb-2 pr-2 w-16">HSN</th>
                <th className="pb-2 pr-2 w-16">Qty</th>
                <th className="pb-2 pr-2 w-24 text-right">Rate (₹)</th>
                <th className="pb-2 pr-2 w-16 text-right">Disc</th>
                <th className="pb-2 pr-2 w-16 text-right">GST%</th>
                <th className="pb-2 w-24 text-right">Amount</th>
                <th className="pb-2 w-10"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-50">
              {lines.map((line, idx) => (
                <tr key={idx}>
                  <td className="py-2 pr-2">
                    <select value={line.product_id} onChange={(e) => handleProductSelect(idx, e.target.value)}
                      className="w-full px-2 py-1.5 border border-zinc-200 rounded-md text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500">
                      <option value="">Select item...</option>
                      {products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
                    </select>
                  </td>
                  <td className="py-2 pr-2">
                    <input type="text" value={line.hsn_sac} maxLength={8}
                      onChange={(e) => setLines(lines.map((l, i) => i === idx ? { ...l, hsn_sac: e.target.value } : l))}
                      className="w-full px-2 py-1.5 border border-zinc-200 rounded-md text-xs font-mono focus:outline-none focus:ring-2 focus:ring-brand-500" />
                  </td>
                  <td className="py-2 pr-2">
                    <input type="number" min="0.01" step="0.01" value={line.quantity}
                      onChange={(e) => setLines(lines.map((l, i) => i === idx ? { ...l, quantity: parseFloat(e.target.value) || 0 } : l))}
                      className="w-full px-2 py-1.5 border border-zinc-200 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500" />
                  </td>
                  <td className="py-2 pr-2">
                    <input type="number" min="0" step="0.01" value={line.rate}
                      onChange={(e) => setLines(lines.map((l, i) => i === idx ? { ...l, rate: parseFloat(e.target.value) || 0 } : l))}
                      className="w-full px-2 py-1.5 border border-zinc-200 rounded-md text-sm text-right focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono" />
                  </td>
                  <td className="py-2 pr-2">
                    <input type="number" min="0" step="0.01" value={line.discount}
                      onChange={(e) => setLines(lines.map((l, i) => i === idx ? { ...l, discount: parseFloat(e.target.value) || 0 } : l))}
                      className="w-full px-2 py-1.5 border border-zinc-200 rounded-md text-sm text-right focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono" />
                  </td>
                  <td className="py-2 pr-2">
                    <input type="number" min="0" max="100" step="0.01" value={line.gst_rate}
                      onChange={(e) => setLines(lines.map((l, i) => i === idx ? { ...l, gst_rate: parseFloat(e.target.value) || 0 } : l))}
                      className="w-full px-2 py-1.5 border border-zinc-200 rounded-md text-sm text-right focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono" />
                  </td>
                  <td className="py-2 text-right font-mono font-semibold text-zinc-800">
                    {new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(line.quantity * line.rate - line.discount)}
                  </td>
                  <td className="py-2 text-center">
                    <button type="button" onClick={() => removeLine(idx)} disabled={lines.length === 1}
                      className="p-1 text-zinc-300 hover:text-red-500 disabled:opacity-30 transition">
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <button type="button" onClick={addLine}
            className="inline-flex items-center gap-1 text-xs font-semibold text-brand-600 hover:text-brand-700 transition">
            <Plus className="w-3.5 h-3.5" /> Add Item
          </button>

          <div className="border-t border-zinc-100 pt-3 flex justify-end">
            <div className="text-right">
              <span className="text-xs text-zinc-500 font-medium">Total Amount</span>
              <p className="text-xl font-bold text-zinc-900 font-mono">
                {new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(total)}
              </p>
            </div>
          </div>
        </div>

        <div className="flex justify-end gap-3">
          <button type="button" onClick={() => onNavigate("estimate_list")}
            className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition">Cancel</button>
          <button type="submit" disabled={saveMutation.isPending}
            className="inline-flex items-center gap-1.5 px-6 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50">
            <Save className="w-4 h-4" /> {saveMutation.isPending ? "Saving..." : isEdit ? "Update Estimate" : "Create Estimate"}
          </button>
        </div>
      </form>
    </div>
  );
}
