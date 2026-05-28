import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Eye } from "lucide-react";
import { useState } from "react";
import PageHeader from "../../components/PageHeader";
import Toolbar from "../../components/Toolbar";
import DataTable, { Column } from "../../components/DataTable";
import StatusBadge from "../../components/StatusBadge";
import AmountText from "../../components/AmountText";

interface ProductListProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail", productId?: string) => void;
}

interface ProductListItem {
  id: string;
  name: string;
  sku: string;
  hsn_sac: string;
  product_type: string;
  uom: string;
  sales_price: number;
  purchase_price: number;
  gst_rate: number;
  is_active: boolean;
}

export default function ProductList({ onNavigate }: ProductListProps) {
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("ALL");

  const { data: products = [], isLoading } = useQuery<ProductListItem[]>({
    queryKey: ["products"],
    queryFn: async () => { const r = await apiClient.get("/masters/products"); return r.data; },
  });

  const filtered = products.filter((p) => {
    const matchesSearch =
      p.name.toLowerCase().includes(search.toLowerCase()) ||
      p.sku.toLowerCase().includes(search.toLowerCase()) ||
      p.hsn_sac.toLowerCase().includes(search.toLowerCase());
    const matchesType = typeFilter === "ALL" || p.product_type === typeFilter;
    return matchesSearch && matchesType;
  });

  const columns: Column<ProductListItem>[] = [
    { key: "name", header: "Product", render: (val) => <span className="font-semibold text-zinc-800">{val}</span> },
    { key: "sku", header: "SKU", mono: true, width: "110px", render: (val) => <span className="text-zinc-500">{val || "—"}</span> },
    { key: "hsn_sac", header: "HSN/SAC", mono: true, width: "100px" },
    { key: "product_type", header: "Type", align: "center", width: "90px", render: (val) => <StatusBadge status={val} variant="info" /> },
    { key: "uom", header: "UOM", align: "center", width: "70px", render: (val) => <span className="text-zinc-500 text-xs">{val || "—"}</span> },
    { key: "sales_price", header: "Sale Price", align: "right", mono: true, width: "110px", render: (val) => <AmountText value={val} /> },
    { key: "gst_rate", header: "GST%", align: "right", width: "80px", mono: true, render: (val) => <span className="text-zinc-600">{val}%</span> },
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
        title="Products & Inventory"
        subtitle="Manage product catalogue and inventory"
        actions={[{ label: "Add Product", icon: <Plus className="w-4 h-4" />, onClick: () => onNavigate("create") }]}
      />
      <Toolbar
        search={{ placeholder: "Search by name, SKU or HSN...", value: search, onChange: setSearch }}
        filters={[{
          label: "Type",
          selected: typeFilter === "ALL" ? null : typeFilter,
          options: [{ label: "All", value: "ALL" }, { label: "Goods", value: "GOODS" }, { label: "Services", value: "SERVICE" }],
          onChange: (v) => setTypeFilter(v || "ALL"),
        }]}
      />
      <DataTable<ProductListItem>
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyTitle="No products found"
        emptyDescription="Add your first product to the catalogue."
        emptyAction={{ label: "Add Product", onClick: () => onNavigate("create") }}
        onRowClick={(row) => onNavigate("detail", row.id)}
        rowKey={(row) => row.id}
      />
    </div>
  );
}
