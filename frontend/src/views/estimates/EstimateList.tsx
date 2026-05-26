import React, { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, FileText, ShieldAlert, Eye, FileSpreadsheet } from "lucide-react";

interface EstimateListProps {
  onNavigate: (view: "estimate_list" | "estimate_create" | "estimate_edit" | "estimate_detail", estimateId?: string) => void;
}

interface EstimateListItem {
  id: string;
  proforma_number: string;
  issue_date: string;
  due_date: string;
  status: string;
  total: number;
  contact_name: string;
  converted_to_invoice_id: string | null;
  created_at: string;
}

export default function EstimateList({ onNavigate }: EstimateListProps) {
  const [search, setSearch] = useState("");
  const queryClient = useQueryClient();

  const { data: estimates = [], isLoading, error } = useQuery<EstimateListItem[]>({
    queryKey: ["estimates"],
    queryFn: async () => {
      const res = await apiClient.get("/proforma-invoices");
      return res.data;
    },
  });

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency", currency: "INR", maximumFractionDigits: 2,
    }).format(amount);
  };

  const issueMutation = useMutation({
    mutationFn: async (id: string) => {
      await apiClient.post(`/proforma-invoices/${id}/issue`);
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["estimates"] }),
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      await apiClient.delete(`/proforma-invoices/${id}`);
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["estimates"] }),
  });

  const filtered = estimates.filter((e) => {
    const q = search.toLowerCase();
    return (
      e.proforma_number.toLowerCase().includes(q) ||
      e.contact_name.toLowerCase().includes(q) ||
      e.status.toLowerCase().includes(q)
    );
  });

  const getStatusBadge = (status: string) => {
    const s = status.toUpperCase();
    if (s === "DRAFT") return <span className="px-2.5 py-0.5 rounded text-xs font-semibold bg-slate-100 text-slate-700 border border-slate-200">Draft</span>;
    if (s === "ISSUED") return <span className="px-2.5 py-0.5 rounded text-xs font-semibold bg-blue-50 text-blue-700 border border-blue-200">Sent</span>;
    if (s === "CONVERTED") return <span className="px-2.5 py-0.5 rounded text-xs font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">Invoiced</span>;
    return <span className="px-2.5 py-0.5 rounded text-xs font-semibold bg-rose-50 text-rose-700 border border-rose-200">Cancelled</span>;
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Estimates</h1>
          <p className="text-sm text-zinc-500 mt-0.5">Create and manage quotations / proforma invoices.</p>
        </div>
        <button
          onClick={() => onNavigate("estimate_create")}
          className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition"
        >
          <Plus className="w-4 h-4" /> New Estimate
        </button>
      </div>

      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            placeholder="Search by number, customer or status..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm"
          />
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span>Error loading estimates.</span>
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <FileText className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Estimates Found</h3>
          <p className="text-xs text-slate-500 mt-1">Create a new estimate to quote your customer.</p>
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">Estimate #</th>
                  <th className="px-6 py-3.5">Customer</th>
                  <th className="px-6 py-3.5">Date</th>
                  <th className="px-6 py-3.5 text-right">Amount</th>
                  <th className="px-6 py-3.5">Status</th>
                  <th className="px-6 py-3.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filtered.map((e) => (
                  <tr key={e.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-semibold text-slate-800">{e.proforma_number}</td>
                    <td className="px-6 py-4 font-semibold text-slate-900">{e.contact_name}</td>
                    <td className="px-6 py-4 text-slate-500">{new Date(e.issue_date).toLocaleDateString("en-IN")}</td>
                    <td className="px-6 py-4 text-right font-mono font-bold text-slate-800">{formatCurrency(e.total)}</td>
                    <td className="px-6 py-4">{getStatusBadge(e.status)}</td>
                    <td className="px-6 py-4 text-right">
                      <div className="inline-flex items-center gap-2">
                        <button
                          onClick={() => onNavigate("estimate_detail", e.id)}
                          title="View"
                          aria-label="View estimate"
                          className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        {e.status === "DRAFT" && (
                          <button
                            onClick={() => issueMutation.mutate(e.id)}
                            disabled={issueMutation.isPending}
                            title="Send to customer"
                            aria-label="Send estimate"
                            className="p-1 text-slate-400 hover:text-blue-600 hover:bg-slate-100 rounded transition"
                          >
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
                            </svg>
                          </button>
                        )}
                        {e.status === "ISSUED" && !e.converted_to_invoice_id && (
                          <button
                            onClick={() => { onNavigate("estimate_detail", e.id); }}
                            title="Convert to invoice"
                            aria-label="Convert to invoice"
                            className="p-1 text-slate-400 hover:text-emerald-600 hover:bg-slate-100 rounded transition"
                          >
                            <FileSpreadsheet className="w-4 h-4" />
                          </button>
                        )}
                      </div>
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
