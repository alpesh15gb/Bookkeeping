import React, { useState, useEffect, useCallback } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search } from "lucide-react";
import SyncfusionGrid from "../../components/SyncfusionGrid";

interface ExpenseListGridProps {
  onNavigate: (view: "expense_list" | "expense_create" | "expense_edit" | "expense_detail", id?: string) => void;
}

export default function ExpenseListGrid({ onNavigate }: ExpenseListGridProps) {
  const [search, setSearch] = useState("");
  const { data: expenses = [], isLoading, error } = useQuery<any[]>({
    queryKey: ["expenses-grid", search],
    queryFn: async () => {
      const res = await apiClient.get("/expenses", { params: { search: search || undefined } });
      return Array.isArray(res.data) ? res.data : res.data?.items || [];
    },
  });

  const formatCurrency = (n: number) =>
    new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(n);

  const getStatusClass = (s: string) => {
    const base = "px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center border";
    if (s === "PAID") return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    if (s === "DRAFT") return `${base} bg-slate-100 text-slate-700 border-slate-200`;
    if (s === "CANCELLED") return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    return `${base} bg-amber-50 text-amber-700 border-amber-200`;
  };

  const columns = [
    { field: "expense_number", headerText: "Expense #", width: "140", textAlign: "Left" as const },
    { field: "expense_date", headerText: "Date", width: "110", textAlign: "Left" as const, format: "dd/MMM/yyyy" },
    { field: "category_name", headerText: "Category", width: "140", textAlign: "Left" as const },
    { field: "vendor_name", headerText: "Vendor", width: "160", textAlign: "Left" as const },
    { field: "description", headerText: "Description", width: "200", textAlign: "Left" as const },
    { field: "amount", headerText: "Amount", width: "130", textAlign: "Right" as const, format: "c" },
    { field: "status", headerText: "Status", width: "110", textAlign: "Center" as const },
    { field: "id", headerText: "Actions", width: "100", textAlign: "Center" as const },
  ];

  const data = expenses.map((e: any) => ({
    ...e,
    expense_date: e.expense_date ? new Date(e.expense_date) : null,
  }));

  if (error) {
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">Error loading expenses.</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Expenses</h1>
          <p className="text-sm text-zinc-500 mt-0.5">Track operating and miscellaneous expenses.</p>
        </div>
        <button
          onClick={() => onNavigate("expense_create")}
          className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition"
        >
          <Plus className="w-4 h-4" />
          Record Expense
        </button>
      </div>
      <div className="relative w-full md:max-w-xs">
        <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
        <input
          type="text"
          placeholder="Search expenses..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full pl-9 pr-4 py-2 border border-zinc-200 rounded-lg text-xs focus:outline-none focus:ring-2 focus:ring-brand-500 placeholder-zinc-400"
        />
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
