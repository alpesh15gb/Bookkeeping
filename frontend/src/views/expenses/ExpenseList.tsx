import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Eye } from "lucide-react";
import { useState, useEffect } from "react";
import PageHeader from "../../components/PageHeader";
import Toolbar from "../../components/Toolbar";
import DataTable, { Column } from "../../components/DataTable";
import StatusBadge from "../../components/StatusBadge";
import AmountText from "../../components/AmountText";
import { formatDate } from "../../lib/utils";

interface ExpenseListProps {
  onNavigate: (view: "expense_list" | "expense_create" | "expense_edit" | "expense_detail", expenseId?: string) => void;
}

interface ExpenseListItem {
  id: string;
  expense_number: string;
  expense_date: string;
  vendor_name: string | null;
  description: string | null;
  total: number;
  status: string;
  category_name: string | null;
}

export default function ExpenseList({ onNavigate }: ExpenseListProps) {
  const [search, setSearch] = useState("");

  const { data: expenses = [], isLoading } = useQuery<ExpenseListItem[]>({
    queryKey: ["expenses"],
    queryFn: async () => {
      const res = await apiClient.get("/expenses");
      return res.data;
    },
  });

  const filtered = expenses.filter((e) => {
    const q = search.toLowerCase();
    return (
      e.expense_number.toLowerCase().includes(q) ||
      (e.vendor_name || "").toLowerCase().includes(q) ||
      (e.description || "").toLowerCase().includes(q) ||
      (e.category_name || "").toLowerCase().includes(q)
    );
  });

  const columns: Column<ExpenseListItem>[] = [
    { key: "expense_number", header: "Expense #", mono: true, width: "150px" },
    { key: "expense_date", header: "Date", width: "110px", render: (val) => <span className="text-zinc-500">{formatDate(val)}</span> },
    {
      key: "vendor_name",
      header: "Vendor",
      render: (val) => <span className="font-medium">{val || "—"}</span>,
    },
    { key: "category_name", header: "Category", render: (val) => <span className="text-zinc-500">{val || "—"}</span> },
    { key: "total", header: "Amount", align: "right", mono: true, render: (val) => <AmountText value={val} /> },
    { key: "status", header: "Status", align: "center", width: "110px", render: (val) => <StatusBadge status={val} /> },
    {
      key: "id", header: "", width: "80px", align: "center",
      render: (_val, row) => (
        <button
          onClick={(e) => { e.stopPropagation(); onNavigate("expense_detail", row.id); }}
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
        title="Expenses"
        subtitle="Manage business expenses and post to ledger"
        actions={[{ label: "Add Expense", icon: <Plus className="w-4 h-4" />, onClick: () => onNavigate("expense_create") }]}
      />
      <Toolbar search={{ placeholder: "Search by number, vendor, category...", value: search, onChange: setSearch }} />
      <DataTable<ExpenseListItem>
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyTitle="No expenses found"
        emptyDescription="Record your first expense to track business spending."
        emptyAction={{ label: "Add Expense", onClick: () => onNavigate("expense_create") }}
        onRowClick={(row) => onNavigate("expense_detail", row.id)}
        rowKey={(row) => row.id}
      />
    </div>
  );
}
