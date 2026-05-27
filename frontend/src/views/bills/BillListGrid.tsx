import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search } from "lucide-react";
import SyncfusionGrid from "../../components/SyncfusionGrid";

interface BillListGridProps {
  onNavigate: (view: "bill_list" | "bill_create" | "bill_edit" | "bill_detail", billId?: string) => void;
}

export default function BillListGrid({ onNavigate }: BillListGridProps) {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("ALL");

  const { data: bills = [], isLoading, error } = useQuery<any[]>({
    queryKey: ["bills-grid", search, statusFilter],
    queryFn: async () => {
      const res = await apiClient.get("/bills", { params: { search: search || undefined, status: statusFilter !== "ALL" ? statusFilter : undefined } });
      return Array.isArray(res.data) ? res.data : res.data?.items || [];
    },
  });

  const formatCurrency = (amount: number) =>
    new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(amount);

  const getStatusClass = (status: string) => {
    const base = "px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center border";
    const s = status.toUpperCase();
    if (s === "PAID") return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    if (s === "DRAFT") return `${base} bg-slate-100 text-slate-700 border-slate-200`;
    if (s === "CANCELLED") return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    if (s === "OVERDUE") return `${base} bg-red-50 text-red-700 border-red-200`;
    return `${base} bg-amber-50 text-amber-700 border-amber-200`;
  };

  const columns = [
    { field: "bill_number", headerText: "Bill #", width: "140", textAlign: "Left" as const },
    { field: "contact_name", headerText: "Vendor", width: "180", textAlign: "Left" as const },
    { field: "issue_date", headerText: "Issue Date", width: "110", textAlign: "Left" as const, format: "dd/MMM/yyyy" },
    { field: "due_date", headerText: "Due Date", width: "110", textAlign: "Left" as const, format: "dd/MMM/yyyy" },
    { field: "total", headerText: "Amount", width: "130", textAlign: "Right" as const, format: "c" },
    { field: "amount_paid", headerText: "Paid", width: "130", textAlign: "Right" as const, format: "c" },
    { field: "status", headerText: "Status", width: "110", textAlign: "Center" as const },
    { field: "id", headerText: "Actions", width: "100", textAlign: "Center" as const },
  ];

  const data = bills.map((b: any) => ({
    ...b,
    issue_date: b.issue_date ? new Date(b.issue_date) : null,
    due_date: b.due_date ? new Date(b.due_date) : null,
  }));

  return (
    <div className="space-y-5">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 pb-2">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Vendor Bills</h1>
          <p className="text-sm text-zinc-500 mt-0.5">Manage purchase bills and vendor payables.</p>
        </div>
        <button
          onClick={() => onNavigate("bill_create")}
          className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition"
        >
          <Plus className="w-4 h-4" />
          Create Bill
        </button>
      </div>
      <div className="flex flex-col md:flex-row gap-3 items-center justify-between">
        <div className="relative w-full md:max-w-xs">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            placeholder="Search bills..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 border border-zinc-200 rounded-lg text-xs focus:outline-none focus:ring-2 focus:ring-brand-500 placeholder-zinc-400"
          />
        </div>
        <div className="flex flex-wrap items-center gap-2 w-full md:w-auto">
          {["ALL", "PAID", "UNPAID", "OVERDUE", "CANCELLED"].map((s) => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              className={`px-4.5 py-1.5 rounded-lg text-xs font-semibold border transition ${
                statusFilter === s
                  ? "bg-brand-900 border-brand-900 text-white shadow-sm"
                  : "bg-white border-zinc-200 text-zinc-600 hover:bg-zinc-50"
              }`}
            >
              {s === "ALL" ? "All" : s.charAt(0) + s.slice(1).toLowerCase()}
            </button>
          ))}
        </div>
      </div>
      <div className="ej-grid-custom">
        <SyncfusionGrid
          dataSource={data}
          columns={columns}
          allowPaging={true}
          allowSorting={true}
          allowFiltering={true}
          allowExcelExport={true}
          allowPdfExport={true}
          toolbar={["ExcelExport", "PdfExport", "Search"]}
          pageSettings={{ pageSize: 20, pageSizes: [10, 20, 50, 100] }}
        />
      </div>
    </div>
  );
}
