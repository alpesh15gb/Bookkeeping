import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Eye } from "lucide-react";
import { useState } from "react";
import PageHeader from "../../components/PageHeader";
import Toolbar from "../../components/Toolbar";
import DataTable, { Column } from "../../components/DataTable";
import StatusBadge from "../../components/StatusBadge";

interface ContactListProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail", contactId?: string) => void;
}

interface ContactListItem {
  id: string;
  name: string;
  email: string;
  phone: string;
  contact_type: string;
  gstin: string;
  state_code: string;
}

export default function ContactList({ onNavigate }: ContactListProps) {
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("ALL");

  const { data: contacts = [], isLoading } = useQuery<ContactListItem[]>({
    queryKey: ["contacts", typeFilter],
    queryFn: async () => {
      const params: any = {};
      if (typeFilter !== "ALL") params.contact_type = typeFilter;
      const res = await apiClient.get("/masters/contacts", { params });
      return res.data;
    },
  });

  const filtered = contacts.filter((c) => {
    const q = search.toLowerCase();
    return (
      (c.name || "").toLowerCase().includes(q) ||
      (c.phone || "").toLowerCase().includes(q) ||
      (c.gstin || "").toLowerCase().includes(q)
    );
  });

  const columns: Column<ContactListItem>[] = [
    { key: "name", header: "Name", render: (val) => <span className="font-semibold text-zinc-800">{val}</span> },
    { key: "contact_type", header: "Type", align: "center", width: "110px", render: (val) => <StatusBadge status={val} /> },
    { key: "gstin", header: "GSTIN", mono: true, width: "150px", render: (val) => <span className="text-zinc-500">{val || "—"}</span> },
    { key: "phone", header: "Phone", mono: true, width: "130px", render: (val) => <span className="text-zinc-500">{val || "—"}</span> },
    { key: "state_code", header: "State", align: "center", width: "80px", render: (val) => <span className="text-zinc-500 text-xs">{val || "—"}</span> },
    {
      key: "id", header: "", width: "80px", align: "center",
      render: (_val, row) => (
        <button
          onClick={(e) => { e.stopPropagation(); onNavigate("detail", row.id); }}
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
        title="Customers & Vendors"
        subtitle="Manage contacts and allied parties"
        actions={[{ label: "Add Contact", icon: <Plus className="w-4 h-4" />, onClick: () => onNavigate("create") }]}
      />
      <Toolbar
        search={{ placeholder: "Search by name, phone or GSTIN...", value: search, onChange: setSearch }}
        filters={[{
          label: "Type",
          selected: typeFilter === "ALL" ? null : typeFilter,
          options: [
            { label: "All", value: "ALL" },
            { label: "Customers", value: "CUSTOMER" },
            { label: "Vendors", value: "VENDOR" },
          ],
          onChange: (v) => setTypeFilter(v || "ALL"),
        }]}
      />
      <DataTable<ContactListItem>
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyTitle="No contacts found"
        emptyDescription="Add your first customer or vendor to get started."
        emptyAction={{ label: "Add Contact", onClick: () => onNavigate("create") }}
        onRowClick={(row) => onNavigate("detail", row.id)}
        rowKey={(row) => row.id}
      />
    </div>
  );
}
