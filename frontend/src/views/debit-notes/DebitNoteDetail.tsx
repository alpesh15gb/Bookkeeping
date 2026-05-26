import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft } from "lucide-react";

interface DebitNoteDetailProps {
  debitNoteId: string;
  onNavigate: (view: string, id?: string) => void;
}

export default function DebitNoteDetail({ debitNoteId, onNavigate }: DebitNoteDetailProps) {
  const { data: note, isLoading } = useQuery({
    queryKey: ["debit-note", debitNoteId],
    queryFn: async () => { const r = await apiClient.get(`/invoices/debit-notes/${debitNoteId}`); return r.data; },
  });
  const formatCurrency = (n: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(n);

  if (isLoading) return <div className="flex justify-center items-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div></div>;
  if (!note) return <div className="text-center py-20 text-zinc-500">Debit note not found.</div>;

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button onClick={() => onNavigate("debit_notes")} className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"><ArrowLeft className="w-5 h-5" /></button>
        <div><h1 className="text-xl font-bold tracking-tight text-zinc-900">{note.debit_note_number}</h1><p className="text-xs text-zinc-500 mt-0.5">{note.reason || "No reason provided"}</p></div>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-4">
          <span className="text-[10px] font-bold text-zinc-400 uppercase block">Date</span>
          <p className="text-sm font-bold text-zinc-900 mt-1">{new Date(note.issue_date).toLocaleDateString("en-IN")}</p>
        </div>
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-4">
          <span className="text-[10px] font-bold text-zinc-400 uppercase block">Status</span>
          <span className={`mt-1 inline-flex px-2.5 py-1 text-xs font-semibold rounded-full ${note.status === "DRAFT" ? "bg-slate-100 text-slate-700 border border-slate-200" : note.status === "ISSUED" ? "bg-blue-50 text-blue-700 border border-blue-200" : "bg-rose-50 text-rose-700 border border-rose-200"}`}>{note.status}</span>
        </div>
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-4">
          <span className="text-[10px] font-bold text-zinc-400 uppercase block">Total</span>
          <p className="text-xl font-bold text-zinc-900 mt-1 font-mono">{formatCurrency(note.total)}</p>
        </div>
      </div>
      <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm border-collapse">
            <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100 text-xs uppercase tracking-wider">
              <tr><th className="px-4 py-3">Item</th><th className="px-4 py-3 text-right w-20">Qty</th><th className="px-4 py-3 text-right w-28">Rate</th><th className="px-4 py-3 text-right w-28">Amount</th></tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {note.lines?.map((line: any, idx: number) => (
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
      </div>
    </div>
  );
}
