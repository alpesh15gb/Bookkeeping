import React, { useState, useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, Eye, ShieldAlert, ShoppingCart } from "lucide-react";
import Pagination from "../../components/Pagination";

interface PurchaseOrderListProps {
  onNavigate: (view: "purchase_orders" | "purchase_order_create" | "purchase_order_detail", id?: string) => void;
}

interface PurchaseOrderItem {
  id: string;
  po_number: string;
  order_date: string;
  due_date: string;
  contact_name: string;
  status: string;
  total: number;
  amount_received: number;
}

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(amount);

const getStatusBadge = (status: string) => {
  const base = "px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center border";
  switch (status?.toUpperCase()) {
    case "DRAFT": return `${base} bg-slate-100 text-slate-700 border-slate-200`;
    case "CONFIRMED": return `${base} bg-blue-50 text-blue-700 border-blue-200`;
    case "RECEIVED": return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    case "CANCELLED": return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    default: return `${base} bg-slate-100 text-slate-600 border-slate-200`;
  }
};

export default function PurchaseOrderList({ onNavigate }: PurchaseOrderListProps) {
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const itemsPerPage = 20;
  const [statusFilter, setStatusFilter] = useState("ALL");

  const { data: purchaseOrders = [], isLoading, error } = useQuery<PurchaseOrderItem[]>({
    queryKey: ["purchase-orders"],
    queryFn: async () => {
      const res = await apiClient.get("/purchase-orders");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const filtered = purchaseOrders.filter((po) => {
    const matchSearch =
      po.po_number?.toLowerCase().includes(search.toLowerCase()) ||
      po.contact_name?.toLowerCase().includes(search.toLowerCase());
    const matchStatus = statusFilter === "ALL" || po.status?.toUpperCase() === statusFilter;
    return matchSearch && matchStatus;
  });

  const totalPages = Math.ceil(filtered.length / itemsPerPage);
  const paginatedItems = filtered.slice((page - 1) * itemsPerPage, page * itemsPerPage);

  useEffect(() => setPage(1), [search, statusFilter]);

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Purchase Orders</h1>
          <p className="text-sm text-slate-500">Manage purchase orders sent to vendors before billing.</p>
        </div>
        <button
          onClick={() => onNavigate("purchase_order_create")}
          className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold transition"
        >
          <Plus className="w-4 h-4" />
          New Purchase Order
        </button>
      </div>

      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            placeholder="Search by PO number or vendor name..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
        >
          <option value="ALL">All Statuses</option>
          <option value="DRAFT">Draft</option>
          <option value="CONFIRMED">Confirmed</option>
          <option value="RECEIVED">Received</option>
          <option value="CANCELLED">Cancelled</option>
        </select>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span>Error loading purchase orders. Please check API server.</span>
        </div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <ShoppingCart className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Purchase Orders Found</h3>
          <p className="text-xs text-slate-500 mt-1">Create a purchase order to begin tracking vendor procurement.</p>
        </div>
      ) : (
        <>
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">PO #</th>
                  <th className="px-6 py-3.5">Order Date</th>
                  <th className="px-6 py-3.5">Vendor</th>
                  <th className="px-6 py-3.5">Due Date</th>
                  <th className="px-6 py-3.5">Total</th>
                  <th className="px-6 py-3.5">Status</th>
                  <th className="px-6 py-3.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {paginatedItems.map((po) => (
                  <tr key={po.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-medium text-brand-900">{po.po_number}</td>
                    <td className="px-6 py-4 text-slate-500">
                      {new Date(po.order_date).toLocaleDateString("en-IN")}
                    </td>
                    <td className="px-6 py-4 font-semibold text-slate-800">{po.contact_name}</td>
                    <td className="px-6 py-4 text-slate-500">
                      {po.due_date ? new Date(po.due_date).toLocaleDateString("en-IN") : "—"}
                    </td>
                    <td className="px-6 py-4 font-semibold text-slate-800">{formatCurrency(po.total)}</td>
                    <td className="px-6 py-4">
                      <span className={getStatusBadge(po.status)}>{po.status}</span>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <button
                        onClick={() => onNavigate("purchase_order_detail" as any, po.id)}
                        title="View Details"
                        className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition"
                      >
                        <Eye className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
        <Pagination currentPage={page} totalPages={totalPages} onPageChange={setPage} totalItems={filtered.length} pageSize={itemsPerPage} />
        </>
      )}
    </div>
  );
}
