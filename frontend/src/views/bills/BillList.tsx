import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Eye, Edit } from "lucide-react";
import { useState } from "react";
import PageHeader from "../../components/PageHeader";
import Toolbar from "../../components/Toolbar";
import DataTable, { Column } from "../../components/DataTable";
import StatusBadge from "../../components/StatusBadge";
import AmountText from "../../components/AmountText";
import { formatDate } from "../../lib/utils";

interface BillListProps {
  onNavigate: (view: "bill_list" | "bill_create" | "bill_edit" | "bill_detail", billId?: string) => void;
}

interface BillListItem {
  id: string;
  bill_number: string;
  issue_date: string;
  due_date: string;
  status: string;
  total: number;
  amount_paid: number;
  contact_name: string;
}

export default function BillList({ onNavigate }: BillListProps) {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("ALL");

  const { data: bills = [], isLoading } = useQuery<BillListItem[]>({
    queryKey: ["bills"],
    queryFn: async () => {
      const res = await apiClient.get("/bills");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const filtered = bills.filter((b) => {
    const matches =
      b.bill_number.toLowerCase().includes(search.toLowerCase()) ||
      b.contact_name.toLowerCase().includes(search.toLowerCase());
    if (statusFilter === "ALL") return matches;
    if (statusFilter === "PAID") return matches && b.status.toUpperCase() === "PAID";
    if (statusFilter === "DRAFT") return matches && b.status.toUpperCase() === "DRAFT";
    return matches && b.status.toUpperCase() !== "PAID" && b.status.toUpperCase() !== "DRAFT";
  });

  const columns: Column<BillListItem>[] = [
    { key: "bill_number", header: "Bill #", mono: true, width: "140px" },
    { key: "contact_name", header: "Vendor", render: (val) => <span className="font-medium">{val || "—"}</span> },
    { key: "issue_date", header: "Date", width: "110px", render: (val) => <span className="text-zinc-500">{formatDate(val)}</span> },
    { key: "due_date", header: "Due Date", width: "110px", render: (val) => <span className="text-zinc-500">{val ? formatDate(val) : "—"}</span> },
    { key: "total", header: "Amount", align: "right", mono: true, render: (val) => <AmountText value={val} /> },
    { key: "amount_paid", header: "Paid", align: "right", mono: true, render: (val) => <AmountText value={val} colored /> },
    { key: "status", header: "Status", align: "center", width: "110px", render: (val) => <StatusBadge status={val} /> },
    {
      key: "id", header: "Actions", align: "center", width: "140px",
      render: (_val, row) => (
        <div className="inline-flex items-center gap-1">
          <button onClick={(e) => { e.stopPropagation(); onNavigate("bill_detail", row.id); }} className="px-2.5 py-1 text-[11px] font-semibold text-blue-600 bg-blue-50 border border-blue-200 rounded-lg hover:bg-blue-100 transition inline-flex items-center gap-1">
            <Eye className="w-3 h-3" /> View
          </button>
          <button onClick={(e) => { e.stopPropagation(); onNavigate("bill_edit", row.id); }} className="px-2.5 py-1 text-[11px] font-semibold text-zinc-600 bg-white border border-zinc-200 rounded-lg hover:bg-zinc-50 transition inline-flex items-center gap-1">
            <Edit className="w-3 h-3" /> Edit
          </button>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Vendor Bills"
        subtitle="Manage purchase bills and vendor payments"
        actions={[{ label: "New Bill", icon: <Plus className="w-4 h-4" />, onClick: () => onNavigate("bill_create") }]}
      />
      <Toolbar
        search={{ placeholder: "Search by bill number or vendor...", value: search, onChange: setSearch }}
        filters={[{
          label: "Status", selected: statusFilter === "ALL" ? null : statusFilter,
          options: [{ label: "All", value: "ALL" }, { label: "Draft", value: "DRAFT" }, { label: "Paid", value: "PAID" }, { label: "Unpaid", value: "UNPAID" }],
          onChange: (v) => setStatusFilter(v || "ALL"),
        }]}
      />
      <DataTable<BillListItem>
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyTitle="No bills found"
        emptyDescription="Record your first vendor bill to track purchases."
        emptyAction={{ label: "Create Bill", onClick: () => onNavigate("bill_create") }}
        onRowClick={(row) => onNavigate("bill_detail", row.id)}
        rowKey={(row) => row.id}
      />
    </div>
  );
}
