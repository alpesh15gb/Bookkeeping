import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, AlertCircle } from "lucide-react";

interface ProductFormProps {
  editId?: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail", productId?: string) => void;
  onSuccess: () => void;
}

const UOM_OPTIONS = ["PCS", "KGS", "NOS", "MTR", "BOX", "LTR", "SET", "BAG", "TON", "SFT"];
const GST_RATES = [0, 5, 12, 18, 28];

export default function ProductForm({ editId, onNavigate, onSuccess }: ProductFormProps) {
  const isEdit = !!editId;

  const [name, setName] = useState("");
  const [sku, setSku] = useState("");
  const [hsnSac, setHsnSac] = useState("");
  const [productType, setProductType] = useState("GOODS");
  const [uom, setUom] = useState("NOS");
  const [salesPrice, setSalesPrice] = useState(0);
  const [purchasePrice, setPurchasePrice] = useState(0);
  const [gstRate, setGstRate] = useState(18);
  const [formError, setFormError] = useState("");

  const { data: product } = useQuery({
    queryKey: ["product", editId],
    queryFn: async () => {
      const res = await apiClient.get(`/masters/products/${editId}`);
      return res.data;
    },
    enabled: isEdit,
  });

  useEffect(() => {
    if (product && isEdit) {
      setName(product.name);
      setSku(product.sku || "");
      setHsnSac(product.hsn_sac);
      setProductType(product.product_type);
      setUom(product.uom);
      setSalesPrice(parseFloat(product.sales_price) || 0);
      setPurchasePrice(parseFloat(product.purchase_price) || 0);
      setGstRate(parseFloat(product.gst_rate) || 0);
    }
  }, [product, isEdit]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        name,
        sku: sku || undefined,
        hsn_sac: hsnSac,
        product_type: productType,
        uom,
        sales_price: salesPrice,
        purchase_price: purchasePrice,
        gst_rate: gstRate,
      };

      if (isEdit) {
        return apiClient.put(`/masters/products/${editId}`, payload);
      } else {
        return apiClient.post("/masters/products", payload);
      }
    },
    onSuccess: () => {
      onSuccess();
    },
    onError: (err: any) => {
      const msg = err.response?.data?.detail || "Failed to save product. Ensure API parameters are valid.";
      setFormError(msg);
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    if (!name.trim()) {
      setFormError("Product name is required.");
      return;
    }
    if (!hsnSac.trim()) {
      setFormError("HSN/SAC code is required.");
      return;
    }
    if (!/^\d{6,8}$/.test(hsnSac.trim())) {
      setFormError("HSN/SAC must be 6-8 digits.");
      return;
    }
    if (!productType) {
      setFormError("Product type is required.");
      return;
    }
    if (!uom) {
      setFormError("Unit of measure is required.");
      return;
    }

    saveMutation.mutate();
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => onNavigate("list")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">
          {isEdit ? "Edit Product" : "Create Product"}
        </h1>
      </div>

      {formError && (
        <div className="flex items-start gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-sm">
            <span className="font-semibold">Validation Error:</span> {formError}
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Product Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. TMT Steel Bar 12mm"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">SKU (Optional)</label>
            <input
              type="text"
              value={sku}
              onChange={(e) => setSku(e.target.value)}
              placeholder="e.g. TMT-12MM-500"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">HSN/SAC Code</label>
            <input
              type="text"
              value={hsnSac}
              onChange={(e) => setHsnSac(e.target.value)}
              placeholder="e.g. 72011000"
              maxLength={8}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Product Type</label>
            <select
              value={productType}
              onChange={(e) => setProductType(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            >
              <option value="GOODS">Goods</option>
              <option value="SERVICE">Service</option>
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Unit of Measure (UOM)</label>
            <select
              value={uom}
              onChange={(e) => setUom(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            >
              {UOM_OPTIONS.map((opt) => (
                <option key={opt} value={opt}>{opt}</option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">GST Rate (%)</label>
            <select
              value={gstRate}
              onChange={(e) => setGstRate(parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              {GST_RATES.map((rate) => (
                <option key={rate} value={rate}>{rate}%</option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Sales Price (₹)</label>
            <input
              type="number"
              min="0"
              step="0.01"
              value={salesPrice}
              onChange={(e) => setSalesPrice(parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Purchase Price (₹)</label>
            <input
              type="number"
              min="0"
              step="0.01"
              value={purchasePrice}
              onChange={(e) => setPurchasePrice(parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>
        </div>

        <div className="flex justify-end gap-3">
          <button
            type="button"
            onClick={() => onNavigate("list")}
            className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saveMutation.isPending}
            className="px-6 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50"
          >
            {saveMutation.isPending ? "Saving..." : isEdit ? "Update Product" : "Create Product"}
          </button>
        </div>
      </form>
    </div>
  );
}
