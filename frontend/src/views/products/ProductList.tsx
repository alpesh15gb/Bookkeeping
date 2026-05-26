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
    <div className="space-y-6 relative pb-16">
      {/* Desktop Header */}
      <div className="hidden md:flex justify-between items-center pb-2 border-b border-zinc-200">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">
            Products & Inventory
          </h1>
          <p className="text-sm text-zinc-500 mt-0.5">Manage product catalogue and inventory.</p>
        </div>
        <div className="flex items-center gap-3">
          <div className="relative">
            <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
            <input
              type="text"
              placeholder="Search items by name, HSN..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-9 pr-4 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none w-64 bg-white"
            />
          </div>
          <button
            onClick={() => onNavigate("create")}
            className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition"
          >
            <Plus className="w-4 h-4" /> Add Item
          </button>
        </div>
      </div>

      {/* Mobile Top Header */}
      <div className="md:hidden bg-[#0B1B3D] text-white p-4 -mx-4 -mt-4 mb-6 border-b border-navy-800 shadow-md">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-bold tracking-tight text-white font-sans">Inventory</h1>
          </div>
          <button className="text-zinc-300 hover:text-[#DCA035]">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
            </svg>
          </button>
        </div>
        {/* Search Bar inside Header */}
        <div className="relative">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            placeholder="Search items by name, HSN code..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 bg-white text-slate-800 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 border-none placeholder-slate-400"
          />
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span>Error loading inventory. Please check API server.</span>
        </div>
      ) : filteredProducts.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <Package className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Items Found</h3>
          <p className="text-xs text-slate-500 mt-1">Try resetting filters or create a new item.</p>
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-xs">
              <thead className="bg-[#0B1B3D] text-white font-bold border-b border-navy-800">
                <tr>
                  <th className="px-4 py-3">Item Name</th>
                  <th className="px-4 py-3">HSN Code</th>
                  <th className="px-4 py-3">Unit</th>
                  <th className="px-4 py-3">GST Rate</th>
                  <th className="px-4 py-3">Type</th>
                  <th className="px-4 py-3">Selling Price</th>
                  <th className="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredProducts.map((p) => {
                  return (
                    <tr 
                      key={p.id} 
                      className="hover:bg-slate-50/50 transition"
                    >
                      <td className="px-4 py-3.5 font-bold text-navy-900">
                        {p.name}
                      </td>
                      <td className="px-4 py-3.5 font-mono text-slate-500">{p.hsn_sac}</td>
                      <td className="px-4 py-3.5 text-slate-500 font-medium">{p.uom.toLowerCase()}</td>
                      <td className="px-4 py-3.5 text-slate-500 font-bold">{p.gst_rate}%</td>
                      <td className="px-4 py-3.5 font-bold text-slate-800">
                        {p.product_type === "GOODS" ? (
                          <span className="px-2 py-0.5 text-[10px] font-bold rounded-full bg-blue-50 text-blue-700 border border-blue-200">Goods</span>
                        ) : (
                          <span className="px-2 py-0.5 text-[10px] font-bold rounded-full bg-purple-50 text-purple-700 border border-purple-200">Service</span>
                        )}
                      </td>
                      <td className="px-4 py-3.5 font-extrabold text-slate-800">
                        {formatCurrency(p.sales_price)}
                      </td>
                      <td className="px-4 py-3.5 text-right">
                        <div className="inline-flex items-center gap-2">
                          <button
                            onClick={() => onNavigate("edit", p.id)}
                            aria-label="Edit product"
                            className="p-1 text-slate-400 hover:text-navy-900 hover:bg-slate-100 rounded transition focus:outline-none focus:ring-2 focus:ring-brand-500"
                          >
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                            </svg>
                          </button>
                          <button
                            onClick={() => onNavigate("detail", p.id)}
                            aria-label="View product details"
                            className="p-1 text-slate-400 hover:text-navy-900 hover:bg-slate-100 rounded transition focus:outline-none focus:ring-2 focus:ring-brand-500"
                          >
                            <Eye className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Floating Action Button (FAB) */}
      <button
        onClick={() => onNavigate("create")}
        className="md:hidden fixed bottom-20 right-6 w-14 h-14 bg-[#DCA035] hover:bg-[#C98F2C] text-white rounded-full flex items-center justify-center shadow-lg transition active:scale-95 z-40 border border-[#DCA035]/20 font-extrabold text-2xl"
      >
        <Plus className="w-6 h-6" />
      </button>

      
    </div>
  );
}
