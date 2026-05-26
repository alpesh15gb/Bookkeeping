import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, FileMinus, ShieldAlert, Eye, Search } from "lucide-react";

interface DebitNoteListProps {
  onNavigate: (view: string, id?: string) => void;
}

interface DebitNoteItem {
  id: string;
  debit_note_number: string;
  issue_date: string;
  status: string;
  total: number;
  reason: string | null;
  created_at: string;
}

export default function DebitNoteList({ onNavigate }: DebitNoteListProps) {
  const [search, setSearch] = useState("");
  const { data: notes = [], isLoading, error } = useQuery<DebitNoteItem[]>({
    queryKey: ["debit-notes"],
    queryFn: async () => { const r = await apiClient.get("/invoices/debit-notes"); return r.data; },
  });

  const formatCurrency = (n: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(n);
  const filtered = notes.filter(n => n.debit_note_number.includes(search) || (n.reason || "").toLowerCase().includes(search.toLowerCase()));
  const getBadge = (s: string) => {
    if (s === "DRAFT") return <span className="px-2.5 py-0.5 rounded text-xs font-semibold bg-slate-100 text-slate-700 border border-slate-200">Draft</span>;
    if (s === "ISSUED") return <span className="px-2.5 py-0.5 rounded text-xs font-semibold bg-blue-50 text-blue-700 border border-blue-200">Issued</span>;
    return <span className="px-2.5 py-0.5 rounded text-xs font-semibold bg-rose-50 text-rose-700 border border-rose-200">Cancelled</span>;
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div><h1 className="text-xl font-bold tracking-tight text-zinc-900">Debit Notes</h1><p className="text-sm text-zinc-500 mt-0.5">Vendor debit notes / purchase returns.</p></div>
      </div>
      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input type="text" placeholder="Search by number or reason..." value={search} onChange={e => setSearch(e.target.value)} className="w-full pl-10 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm" />
        </div>
      </div>
      {isLoading ? (
        <div className="flex justify-center items-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div></div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg"><ShieldAlert className="w-5 h-5" /><span>Error loading debit notes.</span></div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm"><FileMinus className="w-12 h-12 text-slate-300 mx-auto mb-3" /><h3 className="text-sm font-semibold text-slate-700">No Debit Notes Found</h3></div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr><th className="px-6 py-3.5">Debit Note #</th><th className="px-6 py-3.5">Date</th><th className="px-6 py-3.5">Reason</th><th className="px-6 py-3.5 text-right">Amount</th><th className="px-6 py-3.5">Status</th><th className="px-6 py-3.5 text-right">Actions</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filtered.map(n => (
                  <tr key={n.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-semibold text-zinc-800">{n.debit_note_number}</td>
                    <td className="px-6 py-4 text-zinc-500">{new Date(n.issue_date).toLocaleDateString("en-IN")}</td>
                    <td className="px-6 py-4 text-zinc-500 max-w-[200px] truncate">{n.reason || "—"}</td>
                    <td className="px-6 py-4 text-right font-mono font-bold text-zinc-800">{formatCurrency(n.total)}</td>
                    <td className="px-6 py-4">{getBadge(n.status)}</td>
                    <td className="px-6 py-4 text-right">
                      <button onClick={() => onNavigate("debit_note_detail", n.id)} title="View" aria-label="View debit note" className="p-1 text-zinc-400 hover:text-brand-600 hover:bg-zinc-100 rounded transition"><Eye className="w-4 h-4" /></button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
