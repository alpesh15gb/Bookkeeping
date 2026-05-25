import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Edit, AlertTriangle, Tag, Barcode, Package } from "lucide-react";

interface ProductDetailProps {
  productId: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail", productId?: string) => void;
}

export default function ProductDetail({ productId, onNavigate }: ProductDetailProps) {
  const { data: product, isLoading, error } = useQuery({
    queryKey: ["product", productId],
    queryFn: async () => {
      const res = await apiClient.get(`/masters/products/${productId}`);
      return res.data;
    },
  });

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
    }).format(val);
  };

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (error || !product) {
    return (
      <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
        <AlertTriangle className="w-5 h-5 flex-shrink-0" />
        <span>Error retrieving product details.</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div className="flex items-center gap-3">
          <button
            onClick={() => onNavigate("list")}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-xl font-bold text-slate-900">{product.name}</h1>
          <span className={`px-2.5 py-0.5 text-xs font-semibold rounded-full border ${
            product.is_active
              ? "bg-emerald-50 text-emerald-700 border-emerald-200"
              : "bg-rose-50 text-rose-700 border-rose-200"
          }`}>
            {product.is_active ? "Active" : "Inactive"}
          </span>
        </div>

        <button
          onClick={() => onNavigate("edit", productId)}
          className="inline-flex items-center gap-1.5 px-4 py-1.5 text-sm font-semibold bg-brand-600 hover:bg-brand-700 text-white rounded-lg transition shadow-sm"
        >
          <Edit className="w-4 h-4" /> Edit
        </button>
      </div>

      <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="space-y-4">
            <div className="flex items-start gap-3">
              <Tag className="w-5 h-5 text-slate-400 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">Product Name</p>
                <p className="text-sm font-semibold text-slate-800 mt-0.5">{product.name}</p>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Barcode className="w-5 h-5 text-slate-400 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">SKU</p>
                <p className="text-sm font-mono text-slate-800 mt-0.5">{product.sku || "—"}</p>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Package className="w-5 h-5 text-slate-400 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">HSN/SAC Code</p>
                <p className="text-sm font-mono text-slate-800 mt-0.5">{product.hsn_sac}</p>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Package className="w-5 h-5 text-slate-400 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">Product Type</p>
                <span className={`inline-block mt-0.5 px-2 py-0.5 text-xs font-semibold rounded-full ${
                  product.product_type === "GOODS"
                    ? "bg-blue-50 text-blue-700 border border-blue-200"
                    : "bg-purple-50 text-purple-700 border border-purple-200"
                }`}>
                  {product.product_type}
                </span>
              </div>
            </div>
          </div>

          <div className="space-y-4">
            <div className="flex items-start gap-3">
              <Package className="w-5 h-5 text-slate-400 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">Unit of Measure (UOM)</p>
                <p className="text-sm font-semibold text-slate-800 mt-0.5">{product.uom}</p>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Tag className="w-5 h-5 text-slate-400 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">Sales Price</p>
                <p className="text-sm font-semibold text-slate-800 mt-0.5">{formatCurrency(product.sales_price)}</p>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Tag className="w-5 h-5 text-slate-400 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">Purchase Price</p>
                <p className="text-sm font-semibold text-slate-800 mt-0.5">{formatCurrency(product.purchase_price)}</p>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Tag className="w-5 h-5 text-slate-400 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-slate-400 uppercase tracking-wider">GST Rate</p>
                <p className="text-sm font-semibold text-slate-800 mt-0.5">{product.gst_rate}%</p>
              </div>
            </div>
          </div>
        </div>

        <div className="mt-6 pt-6 border-t border-slate-100 grid grid-cols-1 md:grid-cols-2 gap-4 text-xs text-slate-400">
          <div>
            <span className="font-semibold uppercase tracking-wider">Created</span>
            <p className="text-slate-600 mt-0.5">{new Date(product.created_at).toLocaleDateString("en-IN")}</p>
          </div>
          <div>
            <span className="font-semibold uppercase tracking-wider">Last Updated</span>
            <p className="text-slate-600 mt-0.5">{new Date(product.updated_at).toLocaleDateString("en-IN")}</p>
          </div>
        </div>
      </div>
    </div>
  );
}
