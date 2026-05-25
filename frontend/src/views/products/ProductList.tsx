import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, Package, Eye, Edit, ShieldAlert } from "lucide-react";

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
  created_at: string;
  updated_at: string;
}

export default function ProductList({ onNavigate }: ProductListProps) {
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("ALL");

  const { data: products = [], isLoading, error } = useQuery<ProductListItem[]>({
    queryKey: ["products"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/products");
      return res.data;
    },
  });

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 2,
    }).format(amount);
  };

  const filteredProducts = products.filter((p) => {
    const matchesSearch =
      p.name.toLowerCase().includes(search.toLowerCase()) ||
      p.sku.toLowerCase().includes(search.toLowerCase()) ||
      p.hsn_sac.toLowerCase().includes(search.toLowerCase());
    const matchesType = typeFilter === "ALL" || p.product_type === typeFilter;
    return matchesSearch && matchesType;
  });

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Products & Inventory</h1>
          <p className="text-sm text-slate-500">Manage product catalogue, pricing, and GST rates.</p>
        </div>
        <button
          onClick={() => onNavigate("create")}
          className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold transition"
        >
          <Plus className="w-4 h-4" />
          Create Product
        </button>
      </div>

      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4.5 w-4.5 text-slate-400" />
          <input
            type="text"
            placeholder="Search by name, SKU, or HSN/SAC..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm"
          />
        </div>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
        >
          <option value="ALL">All Types</option>
          <option value="GOODS">Goods</option>
          <option value="SERVICE">Services</option>
        </select>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span>Error loading products. Please check API server.</span>
        </div>
      ) : filteredProducts.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <Package className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Products Found</h3>
          <p className="text-xs text-slate-500 mt-1">Try resetting filters or create a new product to get started.</p>
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">Name</th>
                  <th className="px-6 py-3.5">SKU</th>
                  <th className="px-6 py-3.5">HSN/SAC</th>
                  <th className="px-6 py-3.5">Type</th>
                  <th className="px-6 py-3.5">UOM</th>
                  <th className="px-6 py-3.5">Sales Price</th>
                  <th className="px-6 py-3.5">Purchase Price</th>
                  <th className="px-6 py-3.5">GST Rate</th>
                  <th className="px-6 py-3.5">Status</th>
                  <th className="px-6 py-3.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredProducts.map((p) => (
                  <tr key={p.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-semibold text-slate-800">{p.name}</td>
                    <td className="px-6 py-4 font-mono text-slate-500">{p.sku || "—"}</td>
                    <td className="px-6 py-4 font-mono text-slate-500">{p.hsn_sac}</td>
                    <td className="px-6 py-4">
                      <span className={`px-2 py-0.5 text-xs font-semibold rounded-full ${
                        p.product_type === "GOODS"
                          ? "bg-blue-50 text-blue-700 border border-blue-200"
                          : "bg-purple-50 text-purple-700 border border-purple-200"
                      }`}>
                        {p.product_type}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-slate-500">{p.uom}</td>
                    <td className="px-6 py-4 font-semibold text-slate-800">{formatCurrency(p.sales_price)}</td>
                    <td className="px-6 py-4 text-slate-500">{formatCurrency(p.purchase_price)}</td>
                    <td className="px-6 py-4 text-slate-500">{p.gst_rate}%</td>
                    <td className="px-6 py-4">
                      <span className={`px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center gap-1 ${
                        p.is_active
                          ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                          : "bg-rose-50 text-rose-700 border border-rose-200"
                      }`}>
                        {p.is_active ? "Active" : "Inactive"}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <div className="inline-flex items-center gap-2">
                        <button
                          onClick={() => onNavigate("detail", p.id)}
                          title="View Details"
                          className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        {p.is_active && (
                          <button
                            onClick={() => onNavigate("edit", p.id)}
                            title="Edit Product"
                            className="p-1 text-slate-400 hover:text-amber-600 hover:bg-slate-100 rounded transition"
                          >
                            <Edit className="w-4 h-4" />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
