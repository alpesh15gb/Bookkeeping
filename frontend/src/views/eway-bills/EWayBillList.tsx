import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Truck, ShieldAlert, Search } from "lucide-react";

interface EWayBillListProps {
  onNavigate: (view: string, id?: string) => void;
}

interface EWayBillItem {
  id: string;
  eway_bill_number: string;
  status: string;
  supply_type: string;
  valid_until: string;
  vehicle_number: string | null;
  transporter_name: string | null;
}

export default function EWayBillList({ onNavigate }: EWayBillListProps) {
  const [search, setSearch] = useState("");
  const { data: bills = [], isLoading, error } = useQuery<EWayBillItem[]>({
    queryKey: ["eway-bills"],
    queryFn: async () => { const r = await apiClient.get("/eway-bills"); return r.data; },
  });

  const filtered = bills.filter(b => b.eway_bill_number.includes(search) || (b.transporter_name || "").toLowerCase().includes(search.toLowerCase()));
  const getBadge = (s: string) => {
    const base = "px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center border";
    if (s === "GENERATED") return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    if (s === "CANCELLED") return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    return `${base} bg-slate-100 text-slate-700 border-slate-200`;
  };

  const getDisplayLabel = (s: string) => {
    if (s === "GENERATED") return "Active";
    if (s === "CANCELLED") return "Cancelled";
    return s;
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div><h1 className="text-xl font-bold tracking-tight text-zinc-900">E-Way Bills</h1><p className="text-sm text-zinc-500 mt-0.5">Track goods movement compliance.</p></div>
      </div>
      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input type="text" placeholder="Search by EWB number or transporter..." value={search} onChange={e => setSearch(e.target.value)} className="w-full pl-10 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm" />
        </div>
      </div>
      {isLoading ? (
        <div className="flex justify-center items-center py-20"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div></div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg"><ShieldAlert className="w-5 h-5" /><span>Error loading e-way bills.</span></div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm"><Truck className="w-12 h-12 text-slate-300 mx-auto mb-3" /><h3 className="text-sm font-semibold text-slate-700">No E-Way Bills Found</h3><p className="text-xs text-slate-500 mt-1">Generate e-way bills from finalized invoices.</p></div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr><th className="px-6 py-3.5">EWB Number</th><th className="px-6 py-3.5">Transporter</th><th className="px-6 py-3.5">Vehicle</th><th className="px-6 py-3.5">Valid Until</th><th className="px-6 py-3.5">Status</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filtered.map(b => (
                  <tr key={b.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-bold text-zinc-800">{b.eway_bill_number}</td>
                    <td className="px-6 py-4 text-zinc-600">{b.transporter_name || "—"}</td>
                    <td className="px-6 py-4 font-mono text-zinc-500">{b.vehicle_number || "—"}</td>
                    <td className="px-6 py-4 text-zinc-500">{b.valid_until ? new Date(b.valid_until).toLocaleDateString("en-IN") : "—"}</td>
                    <td className="px-6 py-4"><span className={getBadge(b.status)}>{getDisplayLabel(b.status)}</span></td>
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
