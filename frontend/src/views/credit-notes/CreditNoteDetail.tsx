import React from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, ShieldAlert, CheckCircle, XCircle } from "lucide-react";

interface CreditNoteDetailProps {
  creditNoteId: string;
  onNavigate: (view: "credit_notes" | "credit_note_create" | "credit_note_detail") => void;
}

interface CreditNoteLine {
  id: string;
  product_name: string;
  hsn_sac: string;
  quantity: number;
  rate: number;
  discount: number;
  subtotal: number;
  gst_rate: number;
  cgst_amount: number;
  sgst_amount: number;
  igst_amount: number;
  total: number;
}

interface CreditNoteData {
  id: string;
  credit_note_number: string;
  issue_date: string;
  reason: string;
  status: string;
  invoice_number?: string;
  contact_name?: string;
  subtotal: number;
  cgst_amount: number;
  sgst_amount: number;
  igst_amount: number;
  total: number;
  lines: CreditNoteLine[];
}

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(amount);

const getStatusBadge = (status: string) => {
  const base = "px-3 py-1 text-sm font-semibold rounded-full inline-flex items-center gap-1.5 border";
  switch (status?.toUpperCase()) {
    case "DRAFT": return `${base} bg-slate-100 text-slate-700 border-slate-200`;
    case "ISSUED": return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    case "APPLIED": return `${base} bg-blue-50 text-blue-700 border-blue-200`;
    case "CANCELLED": return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    default: return `${base} bg-slate-100 text-slate-600 border-slate-200`;
  }
};

export default function CreditNoteDetail({ creditNoteId, onNavigate }: CreditNoteDetailProps) {
  const queryClient = useQueryClient();

  const { data: cn, isLoading, error } = useQuery<CreditNoteData>({
    queryKey: ["credit-note", creditNoteId],
    queryFn: async () => {
      const res = await apiClient.get(`/credit-notes/${creditNoteId}`);
      return res.data;
    },
  });

  const issueMutation = useMutation({
    mutationFn: async () => apiClient.post(`/credit-notes/${creditNoteId}/issue`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["credit-note", creditNoteId] }),
  });

  const cancelMutation = useMutation({
    mutationFn: async () => apiClient.post(`/credit-notes/${creditNoteId}/cancel`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["credit-note", creditNoteId] }),
  });

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (error || !cn) {
    return (
      <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
        <ShieldAlert className="w-5 h-5 flex-shrink-0" />
        <span>Error loading credit note details.</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <button onClick={() => onNavigate("credit_notes")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">{cn.credit_note_number}</h1>
          <p className="text-sm text-slate-500 mt-0.5">
            Issued: {new Date(cn.issue_date).toLocaleDateString("en-IN")}
            {cn.contact_name && ` • ${cn.contact_name}`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className={getStatusBadge(cn.status)}>{cn.status}</span>
          {cn.status === "DRAFT" && (
            <button
              onClick={() => issueMutation.mutate()}
              disabled={issueMutation.isPending}
              className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold text-sm rounded-lg shadow-sm transition disabled:opacity-50"
            >
              <CheckCircle className="w-4 h-4" />
              {issueMutation.isPending ? "Issuing..." : "Issue"}
            </button>
          )}
          {cn.status !== "CANCELLED" && cn.status !== "APPLIED" && (
            <button
              onClick={() => {
                if (confirm("Are you sure you want to cancel this credit note?")) {
                  cancelMutation.mutate();
                }
              }}
              disabled={cancelMutation.isPending}
              className="flex items-center gap-2 px-4 py-2 border border-rose-200 text-rose-700 hover:bg-rose-50 font-semibold text-sm rounded-lg transition disabled:opacity-50"
            >
              <XCircle className="w-4 h-4" />
              {cancelMutation.isPending ? "Cancelling..." : "Cancel"}
            </button>
          )}
        </div>
      </div>

      {/* Detail cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        {cn.invoice_number && (
          <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-5">
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Linked Invoice</p>
            <p className="font-mono font-semibold text-brand-700">{cn.invoice_number}</p>
          </div>
        )}
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-5">
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Total Credit</p>
          <p className="text-xl font-bold text-slate-800">{formatCurrency(cn.total)}</p>
        </div>
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-5 md:col-span-2">
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Reason</p>
          <p className="text-sm text-slate-700">{cn.reason}</p>
        </div>
      </div>

      {/* Line Items Table */}
      <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
        <div className="bg-slate-50 border-b border-slate-100 px-6 py-3.5">
          <span className="font-semibold text-sm text-slate-700">Line Items</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-left text-sm">
            <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
              <tr>
                <th className="px-6 py-3.5">Item</th>
                <th className="px-6 py-3.5">HSN/SAC</th>
                <th className="px-6 py-3.5 text-right">Qty</th>
                <th className="px-6 py-3.5 text-right">Rate</th>
                <th className="px-6 py-3.5 text-right">Subtotal</th>
                <th className="px-6 py-3.5 text-right">GST</th>
                <th className="px-6 py-3.5 text-right">Total</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {(cn.lines || []).map((line) => (
                <tr key={line.id} className="hover:bg-slate-50/50 transition">
                  <td className="px-6 py-4 font-semibold text-slate-800">{line.product_name}</td>
                  <td className="px-6 py-4 font-mono text-slate-500">{line.hsn_sac}</td>
                  <td className="px-6 py-4 text-right text-slate-600">{line.quantity}</td>
                  <td className="px-6 py-4 text-right text-slate-600">{formatCurrency(line.rate)}</td>
                  <td className="px-6 py-4 text-right text-slate-600">{formatCurrency(line.subtotal)}</td>
                  <td className="px-6 py-4 text-right text-slate-500 text-xs">
                    {line.gst_rate}%
                    {line.cgst_amount > 0 && <div>C: {formatCurrency(line.cgst_amount)}</div>}
                    {line.igst_amount > 0 && <div>I: {formatCurrency(line.igst_amount)}</div>}
                  </td>
                  <td className="px-6 py-4 text-right font-bold text-slate-800">{formatCurrency(line.total)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Totals footer */}
        <div className="border-t border-slate-100 p-6 flex justify-end">
          <div className="w-64 space-y-2">
            <div className="flex justify-between text-sm text-slate-600">
              <span>Subtotal</span><span>{formatCurrency(cn.subtotal)}</span>
            </div>
            {cn.cgst_amount > 0 && (
              <div className="flex justify-between text-xs text-slate-500">
                <span>CGST</span><span>{formatCurrency(cn.cgst_amount)}</span>
              </div>
            )}
            {cn.sgst_amount > 0 && (
              <div className="flex justify-between text-xs text-slate-500">
                <span>SGST</span><span>{formatCurrency(cn.sgst_amount)}</span>
              </div>
            )}
            {cn.igst_amount > 0 && (
              <div className="flex justify-between text-xs text-slate-500">
                <span>IGST</span><span>{formatCurrency(cn.igst_amount)}</span>
              </div>
            )}
            <div className="flex justify-between text-base font-bold text-slate-900 pt-2 border-t border-slate-100">
              <span>Total Credit</span><span className="text-brand-900">{formatCurrency(cn.total)}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
