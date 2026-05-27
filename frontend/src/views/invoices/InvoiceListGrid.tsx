import React, { useState, useEffect, useCallback, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, SlidersHorizontal, ChevronDown } from "lucide-react";
import SyncfusionGrid from "../../components/SyncfusionGrid";

interface InvoiceListGridProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail", invoiceId?: string) => void;
}

export default function InvoiceListGrid({ onNavigate }: InvoiceListGridProps) {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("ALL");
  const [gridInstance, setGridInstance] = useState<any>(null);
  const gridRef = useRef<any>(null);

  const { data: invoicesResponse, isLoading, error } = useQuery<any>({
    queryKey: ["invoices-grid", search, statusFilter],
    queryFn: async () => {
      const res = await apiClient.get("/invoices", {
        params: { search: search || undefined, status: statusFilter !== "ALL" ? statusFilter : undefined },
      });
      return res.data;
    },
  });

  const invoices = Array.isArray(invoicesResponse)
    ? invoicesResponse
    : invoicesResponse?.items || [];

  const formatCurrency = (amount: number) =>
    new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(amount);

  const getStatusClass = (status: string) => {
    const base = "px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center border";
    const s = status.toUpperCase();
    if (s === "PAID") return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    if (s === "CANCELLED") return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    return `${base} bg-amber-50 text-amber-700 border-amber-200`;
  };

  const getStatusLabel = (status: string) => {
    const s = status.toUpperCase();
    if (s === "PAID") return "Paid";
    if (s === "CANCELLED") return "Cancelled";
    return "Unpaid";
  };

  const actionTemplate = (props: any) => (
    <div className="inline-flex items-center gap-1">
      <button
        onClick={() => onNavigate("detail", props.id)}
        className="border border-blue-200 bg-blue-50/20 hover:bg-blue-50 text-blue-600 px-2 py-1 rounded text-[11px] font-semibold inline-flex items-center gap-1 transition shadow-sm"
      >
        View
      </button>
      <button
        onClick={() => onNavigate("edit", props.id)}
        className="border border-zinc-200 bg-white hover:bg-zinc-50 text-zinc-600 px-2 py-1 rounded text-[11px] font-semibold inline-flex items-center gap-1 transition shadow-sm"
      >
        Edit
      </button>
    </div>
  );

  const statusTemplate = (props: any) => (
    <span className={getStatusClass(props.status)}>{getStatusLabel(props.status)}</span>
  );

  const columns = [
    { field: "invoice_number", headerText: "Invoice #", width: "140", textAlign: "Left" as const },
    { field: "contact_name", headerText: "Customer", width: "180", textAlign: "Left" as const },
    {
      field: "issue_date",
      headerText: "Date",
      width: "110",
      textAlign: "Left" as const,
      format: "dd/MMM/yyyy",
    },
    {
      field: "total",
      headerText: "Amount",
      width: "130",
      textAlign: "Right" as const,
      format: "c",
    },
    {
      field: "amount_paid",
      headerText: "Paid",
      width: "130",
      textAlign: "Right" as const,
      format: "c",
    },
    {
      field: "balance",
      headerText: "Balance",
      width: "130",
      textAlign: "Right" as const,
      format: "c",
    },
    {
      field: "status",
      headerText: "Status",
      width: "110",
      textAlign: "Center" as const,
    },
    {
      field: "id",
      headerText: "Actions",
      width: "140",
      textAlign: "Center" as const,
    },
  ];

  const data = invoices.map((inv: any) => ({
    ...inv,
    balance: inv.total - inv.amount_paid,
  }));

  return (
    <div className="space-y-5">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 pb-2">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Invoices</h1>
          <p className="text-sm text-zinc-500 mt-0.5">Manage sales invoices and GST compliance.</p>
        </div>
        <button
          onClick={() => onNavigate("create")}
          className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition"
        >
          <Plus className="w-4 h-4" />
          Create Invoice
        </button>
      </div>

      <div className="flex flex-col md:flex-row gap-3 items-center justify-between">
        <div className="relative w-full md:max-w-xs">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            placeholder="Search invoices..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 border border-zinc-200 rounded-lg text-xs focus:outline-none focus:ring-2 focus:ring-brand-500 placeholder-zinc-400"
          />
        </div>
        <div className="flex flex-wrap items-center gap-2 w-full md:w-auto">
          {["ALL", "PAID", "UNPAID", "CANCELLED"].map((s) => (
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
