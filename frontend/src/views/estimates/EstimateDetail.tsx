import React from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Send, FileSpreadsheet, Trash2, Edit } from "lucide-react";

interface EstimateDetailProps {
  estimateId: string;
  onNavigate: (view: "estimate_list" | "estimate_create" | "estimate_edit" | "estimate_detail", id?: string) => void;
}

export default function EstimateDetail({ estimateId, onNavigate }: EstimateDetailProps) {
  const queryClient = useQueryClient();

  const { data: estimate, isLoading } = useQuery({
    queryKey: ["estimate", estimateId],
    queryFn: async () => { const r = await apiClient.get(`/proforma-invoices/${estimateId}`); return r.data; },
  });

  const issueMutation = useMutation({
    mutationFn: async () => { await apiClient.post(`/proforma-invoices/${estimateId}/issue`); },
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ["estimate"] }); queryClient.invalidateQueries({ queryKey: ["estimates"] }); },
  });

  const convertMutation = useMutation({
    mutationFn: async () => { await apiClient.post(`/proforma-invoices/${estimateId}/convert`); },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["estimate"] });
      queryClient.invalidateQueries({ queryKey: ["estimates"] });
      queryClient.invalidateQueries({ queryKey: ["invoices"] });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async () => { await apiClient.delete(`/proforma-invoices/${estimateId}`); },
    onSuccess: () => onNavigate("estimate_list"),
  });

  const formatCurrency = (n: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(n);

  if (isLoading) return <div className="flex justify-center items-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div></div>;
  if (!estimate) return <div className="text-center py-20 text-slate-500">Estimate not found.</div>;

  const statusBadge = () => {
    const s = estimate.status.toUpperCase();
    if (s === "DRAFT") return <span className="px-2.5 py-1 text-xs font-semibold rounded-full bg-slate-100 text-slate-700 border border-slate-200">Draft</span>;
    if (s === "ISSUED") return <span className="px-2.5 py-1 text-xs font-semibold rounded-full bg-blue-50 text-blue-700 border border-blue-200">Sent</span>;
    if (s === "CONVERTED") return <span className="px-2.5 py-1 text-xs font-semibold rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">Invoiced</span>;
    return <span className="px-2.5 py-1 text-xs font-semibold rounded-full bg-rose-50 text-rose-700 border border-rose-200">Cancelled</span>;
  };

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div className="flex items-center justify-between pb-4 border-b border-zinc-200/60">
        <div className="flex items-center gap-3">
          <button onClick={() => onNavigate("estimate_list")} className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h1 className="text-xl font-bold tracking-tight text-zinc-900">{estimate.proforma_number}</h1>
            <p className="text-xs text-zinc-500 mt-0.5">{estimate.contact?.name}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {estimate.status === "DRAFT" && (
            <>
              <button onClick={() => onNavigate("estimate_edit", estimateId)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-zinc-50 text-zinc-700 border border-zinc-200 rounded-lg text-xs font-semibold shadow-sm transition">
                <Edit className="w-3.5 h-3.5" /> Edit
              </button>
              <button onClick={() => issueMutation.mutate()} disabled={issueMutation.isPending}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-xs font-semibold shadow-sm transition disabled:opacity-50">
                <Send className="w-3.5 h-3.5" /> {issueMutation.isPending ? "Sending..." : "Send to Customer"}
              </button>
            </>
          )}
          {estimate.status === "ISSUED" && !estimate.converted_to_invoice_id && (
            <button onClick={() => { if (confirm("Convert this estimate to an invoice?")) convertMutation.mutate(); }} disabled={convertMutation.isPending}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg text-xs font-semibold shadow-sm transition disabled:opacity-50">
              <FileSpreadsheet className="w-3.5 h-3.5" /> {convertMutation.isPending ? "Converting..." : "Convert to Invoice"}
            </button>
          )}
          {(estimate.status === "DRAFT" || estimate.status === "ISSUED") && (
            <button onClick={() => { if (confirm("Delete this estimate?")) deleteMutation.mutate(); }}
              className="p-1.5 text-zinc-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition">
              <Trash2 className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-4">
          <span className="text-[10px] font-bold text-zinc-400 uppercase block">Customer</span>
          <p className="text-sm font-bold text-zinc-900 mt-1">{estimate.contact?.name || "—"}</p>
          {estimate.contact?.email && <p className="text-xs text-zinc-500">{estimate.contact.email}</p>}
          {estimate.contact?.phone && <p className="text-xs text-zinc-500">{estimate.contact.phone}</p>}
        </div>
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-4">
          <span className="text-[10px] font-bold text-zinc-400 uppercase block">Dates</span>
          <p className="text-xs text-zinc-500 mt-1">Issued: {new Date(estimate.issue_date).toLocaleDateString("en-IN")}</p>
          <p className="text-xs text-zinc-500">Valid until: {new Date(estimate.due_date).toLocaleDateString("en-IN")}</p>
        </div>
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-4">
          <span className="text-[10px] font-bold text-zinc-400 uppercase block">Status</span>
          <div className="mt-1">{statusBadge()}</div>
          {estimate.converted_to_invoice_id && (
            <p className="text-xs text-emerald-600 font-semibold mt-1">Converted to invoice ✓</p>
          )}
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm border-collapse">
            <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100 text-xs uppercase tracking-wider">
              <tr>
                <th className="px-4 py-3">Item</th>
                <th className="px-4 py-3 text-right w-20">Qty</th>
                <th className="px-4 py-3 text-right w-28">Rate</th>
                <th className="px-4 py-3 text-right w-28">Amount</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {estimate.lines?.map((line: any, idx: number) => (
                <tr key={idx} className="hover:bg-slate-50/50">
                  <td className="px-4 py-3 font-medium text-zinc-800">{line.description || line.product?.name || "—"}</td>
                  <td className="px-4 py-3 text-right text-zinc-600">{Number(line.quantity).toFixed(2)}</td>
                  <td className="px-4 py-3 text-right font-mono text-zinc-600">{formatCurrency(Number(line.rate))}</td>
                  <td className="px-4 py-3 text-right font-mono font-bold text-zinc-800">{formatCurrency(Number(line.total))}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="border-t border-slate-100 px-4 py-3 flex justify-end">
          <div className="text-right">
            <span className="text-xs text-zinc-500 font-medium">Total Amount</span>
            <p className="text-xl font-bold text-zinc-900 font-mono">{formatCurrency(Number(estimate.total))}</p>
          </div>
        </div>
      </div>

      <p className="text-xs text-zinc-400">
        Created: {new Date(estimate.created_at).toLocaleString("en-IN")}
        {estimate.updated_at !== estimate.created_at && <> · Updated: {new Date(estimate.updated_at).toLocaleString("en-IN")}</>}
      </p>
    </div>
  );
}
