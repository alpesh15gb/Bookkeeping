import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, AlertCircle, Search } from "lucide-react";

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
  const [hsnDescription, setHsnDescription] = useState("");
  const [hsnLookupLoading, setHsnLookupLoading] = useState(false);

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

  const handleHSNSearch = async () => {
    if (!hsnSac || hsnSac.length < 6) return;
    setHsnLookupLoading(true);
    setFormError("");
    setHsnDescription("");
    try {
      const r = await apiClient.get(`/gst/hsn/${hsnSac}`);
      setHsnDescription(r.data.description);
      if (!name.trim()) setName(r.data.description);
    } catch (err: any) {
      if (err.response?.status === 404) {
        setFormError(`HSN code ${hsnSac} not found in directory.`);
      } else {
        setFormError(err.response?.data?.detail || "HSN lookup failed.");
      }
    } finally {
      setHsnLookupLoading(false);
    }
  };

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

  const [description, setDescription] = useState("");
  const [openingStock, setOpeningStock] = useState("");
  const [reorderLevel, setReorderLevel] = useState("");
  const [isActive, setIsActive] = useState(true);

  return (
    <div className="max-w-md md:max-w-4xl mx-auto space-y-6 pb-12">
      {/* Desktop Header */}
      <div className="hidden md:flex justify-between items-center pb-2 border-b border-zinc-200">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => onNavigate("list")}
            className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
          >
            <ArrowLeft className="w-5 h-5 text-[#0B1B3D]" />
          </button>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">
            {isEdit ? "Edit Item" : "Add Item"}
          </h1>
        </div>
      </div>

      {/* Mobile Header Banner */}
      <div className="md:hidden bg-[#0B1B3D] text-white p-4 -mx-4 -mt-4 mb-6 flex items-center justify-between border-b border-navy-800 shadow-md">
        <button
          onClick={() => onNavigate("list")}
          className="text-zinc-300 hover:text-[#DCA035] transition p-1"
        >
          <ArrowLeft className="w-5 h-5 text-[#DCA035]" />
        </button>
        <h1 className="text-lg font-bold text-[#DCA035] text-center flex-1">
          {isEdit ? "Edit Item" : "Add Item"}
        </h1>
        <div className="w-7 h-7" />
      </div>

      {formError && (
        <div className="flex items-start gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-sm">
            <span className="font-semibold">Validation Error:</span> {formError}
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Form Container */}
        <div className="bg-white p-5 rounded-2xl border border-slate-100 shadow-sm space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-4">
            
            {/* Item Name */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 7h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
              </div>
              <div className="flex-1 space-y-1">
                <label className="text-xs font-bold text-slate-500 uppercase">Item Name</label>
                <input
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Enter item name"
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none"
                  required
                />
              </div>
            </div>

            {/* HSN Code */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 10h16M4 14h16M4 18h16" />
                </svg>
              </div>
              <div className="flex-1 space-y-1">
                <div className="flex justify-between items-center">
                  <label className="text-xs font-bold text-slate-500 uppercase">HSN/SAC Code</label>
                  <span className="text-[10px] text-slate-400">{hsnSac.length}/8</span>
                </div>
                <div className="flex gap-2">
                  <input
                    type="text"
                    maxLength={8}
                    value={hsnSac}
                    onChange={(e) => { setHsnSac(e.target.value.replace(/\D/g, "")); setHsnDescription(""); }}
                    placeholder="Enter 8 digit HSN code"
                    className="flex-1 px-3 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none font-mono"
                    required
                  />
                  <button
                    type="button"
                    onClick={handleHSNSearch}
                    disabled={hsnLookupLoading || hsnSac.length < 6}
                    className="px-3 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-xs font-semibold disabled:opacity-50 transition flex items-center gap-1"
                  >
                    <Search className="w-3.5 h-3.5" />
                    {hsnLookupLoading ? "..." : "Lookup"}
                  </button>
                </div>
                {hsnDescription && (
                  <p className="text-[10px] text-emerald-600 font-semibold mt-1">{hsnDescription}</p>
                )}
              </div>
            </div>

            {/* Description */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
              </div>
              <div className="flex-1 space-y-1">
                <label className="text-xs font-bold text-slate-500 uppercase">Description</label>
                <textarea
                  rows={2}
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Enter item description"
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none resize-none"
                />
              </div>
            </div>

            {/* Unit */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 6l3 1m0 0l-3 9a5.002 5.002 0 006.001 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5.002 5.002 0 006.001 0M18 7l3 9m-3-9l-6-2m0-2v2m0 16V5m0 16H9m3 0h3" />
                </svg>
              </div>
              <div className="flex-1 space-y-1">
                <label className="text-xs font-bold text-slate-500 uppercase">Unit</label>
                <select
                  value={uom}
                  onChange={(e) => setUom(e.target.value)}
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-500 outline-none"
                  required
                >
                  {UOM_OPTIONS.map((opt) => (
                    <option key={opt} value={opt}>
                      {opt}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* GST Rate */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 9l6 6m0-6L9 15m12-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <div className="flex-1 space-y-1">
                <label className="text-xs font-bold text-slate-500 uppercase">GST Rate</label>
                <select
                  value={gstRate}
                  onChange={(e) => setGstRate(parseInt(e.target.value) || 0)}
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-xs bg-white focus:ring-2 focus:ring-brand-500 outline-none"
                  required
                >
                  {GST_RATES.map((rate) => (
                    <option key={rate} value={rate}>
                      {rate}%
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* Selling Price */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <span className="text-[#DCA035] font-extrabold text-sm font-sans flex items-center justify-center h-5 w-5">₹</span>
              </div>
              <div className="flex-1 space-y-1">
                <label className="text-xs font-bold text-slate-500 uppercase">Selling Price</label>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={salesPrice || ""}
                  onChange={(e) => setSalesPrice(parseFloat(e.target.value) || 0)}
                  placeholder="Enter selling price"
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none font-mono"
                  required
                />
              </div>
            </div>

            {/* Purchase Price */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
                </svg>
              </div>
              <div className="flex-1 space-y-1">
                <label className="text-xs font-bold text-slate-500 uppercase">Purchase Price</label>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={purchasePrice || ""}
                  onChange={(e) => setPurchasePrice(parseFloat(e.target.value) || 0)}
                  placeholder="Enter purchase price"
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none font-mono"
                />
              </div>
            </div>

            {/* Opening Stock */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v3m0 0v3m0-3h3m-3 0H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <div className="flex-1 space-y-1">
                <label className="text-xs font-bold text-slate-500 uppercase">Opening Stock</label>
                <input
                  type="number"
                  min="0"
                  value={openingStock}
                  onChange={(e) => setOpeningStock(e.target.value)}
                  placeholder="Enter opening stock"
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none font-mono"
                />
              </div>
            </div>

            {/* Reorder Level */}
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl mt-6">
                <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </div>
              <div className="flex-1 space-y-1">
                <label className="text-xs font-bold text-slate-500 uppercase">Reorder Level (Alert limit)</label>
                <input
                  type="number"
                  min="0"
                  value={reorderLevel}
                  onChange={(e) => setReorderLevel(e.target.value)}
                  placeholder="Enter alert level"
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none font-mono"
                />
              </div>
            </div>

            {/* Active Switch */}
            <div className="flex items-center justify-between py-2 border-t border-slate-100 md:col-span-2">
              <div className="flex items-center gap-3">
                <div className="p-2.5 bg-[#0B1B3D] text-white rounded-xl">
                  <svg className="w-5 h-5 text-[#DCA035]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5.121 17.804A13.937 13.937 0 0112 16c2.5 0 4.847.655 6.879 1.804M15 10a3 3 0 11-6 0 3 3 0 016 0zm6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                </div>
                <div>
                  <span className="text-xs font-bold text-slate-800 block">Active</span>
                  <span className="text-[10px] text-slate-400 block mt-0.5">Item will be active and available for transactions</span>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setIsActive(!isActive)}
                className={`relative w-11 h-6 rounded-full transition-colors ${
                  isActive ? "bg-[#DCA035]" : "bg-slate-200"
                }`}
              >
                <span
                  className={`absolute top-1 left-1 w-4 h-4 bg-white rounded-full shadow transition-transform ${
                    isActive ? "translate-x-5" : ""
                  }`}
                />
              </button>
            </div>

          </div>
        </div>

        {/* Action Button */}
        <button
          type="submit"
          disabled={saveMutation.isPending}
          className="w-full bg-[#DCA035] hover:bg-[#C98F2C] text-white py-3 rounded-2xl font-bold text-sm shadow-md transition flex items-center justify-center gap-2"
        >
          <svg className="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4" />
          </svg>
          {saveMutation.isPending ? "Saving..." : "Save"}
        </button>
      </form>
    </div>
  );
}
