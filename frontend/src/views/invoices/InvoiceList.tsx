import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, Eye, Edit } from "lucide-react";
import { useState } from "react";
import PageHeader from "../../components/PageHeader";
import Toolbar from "../../components/Toolbar";
import DataTable, { Column } from "../../components/DataTable";
import StatusBadge from "../../components/StatusBadge";
import AmountText from "../../components/AmountText";
import { formatDate } from "../../lib/utils";

interface InvoiceListProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail", invoiceId?: string) => void;
}

interface InvoiceListItem {
  id: string;
  invoice_number: string;
  issue_date: string;
  due_date: string;
  status: string;
  total: number;
  amount_paid: number;
  contact_name: string;
}

export default function InvoiceList({ onNavigate }: InvoiceListProps) {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("ALL");
  const [page, setPage] = useState(1);
  const limit = 20;

  const { data: invoicesResponse, isLoading } = useQuery<{
    items: InvoiceListItem[]; total: number;
  }>({
    queryKey: ["invoices", page, search, statusFilter],
    queryFn: async () => {
      const res = await apiClient.get("/invoices", {
        params: { page, limit, search: search || undefined, status: statusFilter !== "ALL" ? statusFilter : undefined },
      });
      return res.data;
    },
  });

  const invoices = invoicesResponse?.items || [];
  const totalItems = invoicesResponse?.total || 0;

  const columns: Column<InvoiceListItem>[] = [
    { key: "invoice_number", header: "Invoice #", mono: true, width: "140px" },
    {
      key: "contact_name",
      header: "Customer",
      render: (val) => <span className="font-medium">{val || "—"}</span>,
    },
    {
      key: "issue_date",
      header: "Date",
      width: "110px",
      render: (val) => <span className="text-zinc-500">{formatDate(val)}</span>,
    },
    {
      key: "due_date",
      header: "Due Date",
      width: "110px",
      render: (val) => <span className="text-zinc-500">{val ? formatDate(val) : "—"}</span>,
    },
    {
      key: "total",
      header: "Amount",
      align: "right",
      mono: true,
      render: (val) => <AmountText value={val} />,
    },
    {
      key: "amount_paid",
      header: "Paid",
      align: "right",
      mono: true,
      render: (val) => <AmountText value={val} colored />,
    },
    {
      key: "status",
      header: "Status",
      align: "center",
      width: "110px",
      render: (val) => <StatusBadge status={val} />,
    },
    {
      key: "id",
      header: "Actions",
      align: "center",
      width: "140px",
      render: (_val, row) => (
        <div className="inline-flex items-center gap-1">
          <button
            onClick={(e) => { e.stopPropagation(); onNavigate("detail", row.id); }}
            className="px-2.5 py-1 text-[11px] font-semibold text-blue-600 bg-blue-50 border border-blue-200 rounded-lg hover:bg-blue-100 transition inline-flex items-center gap-1"
          >
            <Eye className="w-3 h-3" /> View
          </button>
          <button
            onClick={(e) => { e.stopPropagation(); onNavigate("edit", row.id); }}
            className="px-2.5 py-1 text-[11px] font-semibold text-zinc-600 bg-white border border-zinc-200 rounded-lg hover:bg-zinc-50 transition inline-flex items-center gap-1"
          >
            <Edit className="w-3 h-3" /> Edit
          </button>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Invoices"
        subtitle="Manage sales invoices and GST compliance"
        actions={[
          {
            label: "New Invoice",
            icon: <Plus className="w-4 h-4" />,
            onClick: () => onNavigate("create"),
          },
        ]}
      />

      <Toolbar
        search={{
          placeholder: "Search by invoice number or customer...",
          value: search,
          onChange: (v) => { setSearch(v); setPage(1); },
        }}
        filters={[
          {
            label: "Status",
            selected: statusFilter === "ALL" ? null : statusFilter,
            options: [
              { label: "All", value: "ALL" },
              { label: "Draft", value: "DRAFT" },
              { label: "Posted", value: "POSTED" },
              { label: "Paid", value: "PAID" },
              { label: "Partial", value: "PARTIALLY_PAID" },
              { label: "Cancelled", value: "CANCELLED" },
            ],
            onChange: (v) => { setStatusFilter(v || "ALL"); setPage(1); },
          },
        ]}
      />

      <DataTable<InvoiceListItem>
        columns={columns}
        data={invoices}
        loading={isLoading}
        emptyTitle="No invoices found"
        emptyDescription="Create your first GST invoice to get started."
        emptyAction={{
          label: "Create Invoice",
          onClick: () => onNavigate("create"),
        }}
        onRowClick={(row) => onNavigate("detail", row.id)}
        rowKey={(row) => row.id}
      />

      {totalItems > limit && (
        <div className="flex items-center justify-between">
          <span className="text-xs text-zinc-500">
            Showing {(page - 1) * limit + 1}–{Math.min(page * limit, totalItems)} of {totalItems}
          </span>
          <div className="flex items-center gap-1">
            <button
              onClick={() => setPage(page - 1)}
              disabled={page === 1}
              className="px-3 py-1.5 text-xs font-semibold text-zinc-500 bg-white border border-zinc-200 rounded-lg hover:bg-zinc-50 disabled:opacity-40 transition"
            >
              Previous
            </button>
            <span className="px-3 py-1.5 text-xs font-bold text-zinc-700">Page {page}</span>
            <button
              onClick={() => setPage(page + 1)}
              disabled={page * limit >= totalItems}
              className="px-3 py-1.5 text-xs font-semibold text-zinc-500 bg-white border border-zinc-200 rounded-lg hover:bg-zinc-50 disabled:opacity-40 transition"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
