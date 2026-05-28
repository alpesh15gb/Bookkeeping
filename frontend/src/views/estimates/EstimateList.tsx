import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Eye } from "lucide-react";
import { useState } from "react";
import PageHeader from "../../components/PageHeader";
import Toolbar from "../../components/Toolbar";
import DataTable, { Column } from "../../components/DataTable";
import StatusBadge from "../../components/StatusBadge";
import AmountText from "../../components/AmountText";
import { formatDate } from "../../lib/utils";

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
}

export default function EstimateList({ onNavigate }: EstimateListProps) {
  const [search, setSearch] = useState("");
  const queryClient = useQueryClient();

  const { data: estimates = [], isLoading } = useQuery<EstimateListItem[]>({
    queryKey: ["estimates"],
    queryFn: async () => { const r = await apiClient.get("/proforma-invoices"); return r.data; },
  });

  const issueMutation = useMutation({
    mutationFn: async (id: string) => { await apiClient.post(`/proforma-invoices/${id}/issue`); },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["estimates"] }),
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => { await apiClient.delete(`/proforma-invoices/${id}`); },
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

  const columns: Column<EstimateListItem>[] = [
    { key: "proforma_number", header: "Estimate #", mono: true, width: "140px" },
    { key: "contact_name", header: "Customer", render: (val) => <span className="font-semibold text-zinc-800">{val || "—"}</span> },
    { key: "issue_date", header: "Date", width: "110px", render: (val) => <span className="text-zinc-500">{formatDate(val)}</span> },
    { key: "due_date", header: "Valid Until", width: "120px", render: (val) => <span className="text-zinc-500">{val ? formatDate(val) : "—"}</span> },
    { key: "total", header: "Amount", align: "right", mono: true, render: (val) => <AmountText value={val} /> },
    { key: "status", header: "Status", align: "center", width: "110px", render: (val) => <StatusBadge status={val} /> },
    {
      key: "id", header: "", width: "80px", align: "center",
      render: (_val, row) => (
        <button
          onClick={(e) => { e.stopPropagation(); onNavigate("estimate_detail", row.id); }}
          className="px-2.5 py-1 text-[11px] font-semibold text-blue-600 bg-blue-50 border border-blue-200 rounded-lg hover:bg-blue-100 transition inline-flex items-center gap-1"
        >
          <Eye className="w-3 h-3" /> View
        </button>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Estimates"
        subtitle="Create and manage quotations / proforma invoices"
        actions={[{ label: "New Estimate", icon: <Plus className="w-4 h-4" />, onClick: () => onNavigate("estimate_create") }]}
      />
      <Toolbar search={{ placeholder: "Search by number or customer...", value: search, onChange: setSearch }} />
      <DataTable<EstimateListItem>
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyTitle="No estimates found"
        emptyDescription="Create your first quotation or proforma invoice."
        emptyAction={{ label: "New Estimate", onClick: () => onNavigate("estimate_create") }}
        onRowClick={(row) => onNavigate("estimate_detail", row.id)}
        rowKey={(row) => row.id}
      />
    </div>
  );
}
