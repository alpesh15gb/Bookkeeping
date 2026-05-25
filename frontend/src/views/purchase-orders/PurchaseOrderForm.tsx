import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Trash2, Plus, ArrowLeft, AlertCircle } from "lucide-react";

interface PurchaseOrderFormProps {
  editId?: string;
  onNavigate: (view: "purchase_orders" | "purchase_order_create" | "purchase_order_detail", id?: string) => void;
  onSuccess: () => void;
}

interface ContactItem {
  id: string;
  name: string;
  contact_type: string;
  state_code: string;
}

interface ProductItem {
  id: string;
  name: string;
  sku: string;
  hsn_sac: string;
  purchase_price: number;
  gst_rate: number;
}

interface LineItemDraft {
  product_id: string;
  quantity: number;
  rate: number;
  discount: number;
  hsn_sac: string;
  gst_rate: number;
}

const STATE_CODES = [
  { code: "01", name: "Jammu & Kashmir (01)" },
  { code: "02", name: "Himachal Pradesh (02)" },
  { code: "03", name: "Punjab (03)" },
  { code: "04", name: "Chandigarh (04)" },
  { code: "05", name: "Uttarakhand (05)" },
  { code: "06", name: "Haryana (06)" },
  { code: "07", name: "Delhi (07)" },
  { code: "08", name: "Rajasthan (08)" },
  { code: "09", name: "Uttar Pradesh (09)" },
  { code: "10", name: "Bihar (10)" },
  { code: "11", name: "Sikkim (11)" },
  { code: "12", name: "Arunachal Pradesh (12)" },
  { code: "13", name: "Nagaland (13)" },
  { code: "14", name: "Manipur (14)" },
  { code: "15", name: "Mizoram (15)" },
  { code: "16", name: "Tripura (16)" },
  { code: "17", name: "Meghalaya (17)" },
  { code: "18", name: "Assam (18)" },
  { code: "19", name: "West Bengal (19)" },
  { code: "20", name: "Jharkhand (20)" },
  { code: "21", name: "Odisha (21)" },
  { code: "22", name: "Chhattisgarh (22)" },
  { code: "23", name: "Madhya Pradesh (23)" },
  { code: "24", name: "Gujarat (24)" },
  { code: "25", name: "Daman & Diu (25)" },
  { code: "26", name: "Dadra & Nagar Haveli (26)" },
  { code: "27", name: "Maharashtra (27)" },
  { code: "28", name: "Andhra Pradesh (Old) (28)" },
  { code: "29", name: "Karnataka (29)" },
  { code: "30", name: "Goa (30)" },
  { code: "31", name: "Lakshadweep (31)" },
  { code: "32", name: "Kerala (32)" },
  { code: "33", name: "Tamil Nadu (33)" },
  { code: "34", name: "Puducherry (34)" },
  { code: "35", name: "Andaman & Nicobar (35)" },
  { code: "36", name: "Telangana (36)" },
  { code: "37", name: "Andhra Pradesh (37)" },
  { code: "38", name: "Ladakh (38)" },
];

export default function PurchaseOrderForm({ editId, onNavigate, onSuccess }: PurchaseOrderFormProps) {
  const isEdit = !!editId;

  const { data: settingsData } = useQuery({
    queryKey: ["settings"],
    queryFn: async () => {
      const res = await apiClient.get("/settings");
      return res.data;
    },
  });

  const originStateCode = settingsData?.origin_state_code || "27";

  // Form states
  const [contactId, setContactId] = useState("");
  const [poNumber, setPoNumber] = useState("");
  const [orderDate, setOrderDate] = useState(new Date().toISOString().split("T")[0]);
  const [dueDate, setDueDate] = useState(new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString().split("T")[0]);
  const [placeOfSupply, setPlaceOfSupply] = useState(originStateCode);
  const [lines, setLines] = useState<LineItemDraft[]>([
    { product_id: "", quantity: 1, rate: 0, discount: 0, hsn_sac: "", gst_rate: 18 }
  ]);
  const [formError, setFormError] = useState("");

  // Fetch Vendor contacts from API
  const { data: contacts = [] } = useQuery<ContactItem[]>({
    queryKey: ["contacts"],
    queryFn: async () => {
      const res = await apiClient.get("/contacts");
      return res.data;
    }
  });

  const vendors = contacts.filter(c => c.contact_type === "VENDOR" || c.contact_type === "BOTH");

  // Fetch Products
  const { data: products = [] } = useQuery<ProductItem[]>({
    queryKey: ["products"],
    queryFn: async () => {
      const res = await apiClient.get("/products");
      return res.data;
    }
  });

  // Fetch PO details if editing
  const { data: po } = useQuery({
    queryKey: ["purchase-order", editId],
    queryFn: async () => {
      const res = await apiClient.get(`/purchase-orders/${editId}`);
      return res.data;
    },
    enabled: isEdit,
  });

  // Load existing PO data
  useEffect(() => {
    if (po && isEdit) {
      setContactId(po.contact_id);
      setPoNumber(po.po_number);
      setOrderDate(po.order_date);
      setDueDate(po.due_date);
      setPlaceOfSupply(po.pos_state_code);
      setLines(
        po.lines.map((l: any) => ({
          product_id: l.product_id,
          quantity: parseFloat(l.quantity),
          rate: parseFloat(l.rate),
          discount: parseFloat(l.discount),
          hsn_sac: l.hsn_sac,
          gst_rate: parseFloat(l.gst_rate)
        }))
      );
    }
  }, [po, isEdit]);

  const handleVendorChange = (selectedContactId: string) => {
    setContactId(selectedContactId);
    const selected = vendors.find((v) => v.id === selectedContactId);
    if (selected) {
      setPlaceOfSupply(selected.state_code);
    }
  };

  const handleLineProductChange = (index: number, productId: string) => {
    const selectedProd = products.find((p) => p.id === productId);
    if (selectedProd) {
      const newLines = [...lines];
      newLines[index] = {
        product_id: productId,
        quantity: lines[index].quantity || 1,
        rate: selectedProd.purchase_price,
        discount: lines[index].discount || 0,
        hsn_sac: selectedProd.hsn_sac,
        gst_rate: selectedProd.gst_rate
      };
      setLines(newLines);
    }
  };

  const handleLineChange = (index: number, field: keyof LineItemDraft, value: any) => {
    const newLines = [...lines];
    newLines[index] = {
      ...newLines[index],
      [field]: value
    };
    setLines(newLines);
  };

  const addLine = () => {
    setLines([...lines, { product_id: "", quantity: 1, rate: 0, discount: 0, hsn_sac: "", gst_rate: 18 }]);
  };

  const removeLine = (index: number) => {
    if (lines.length > 1) {
      setLines(lines.filter((_, i) => i !== index));
    }
  };

  const calculateTotals = () => {
    let subtotal = 0;
    let discountTotal = 0;
    let cgst = 0;
    let sgst = 0;
    let igst = 0;

    const isIntraState = originStateCode === placeOfSupply;

    lines.forEach((line) => {
      const itemSubtotal = (line.quantity || 0) * (line.rate || 0) - (line.discount || 0);
      subtotal += itemSubtotal;
      discountTotal += line.discount || 0;

      const lineTax = itemSubtotal * ((line.gst_rate || 0) / 100);
      if (isIntraState) {
        cgst += lineTax / 2;
        sgst += lineTax / 2;
      } else {
        igst += lineTax;
      }
    });

    const grandTotal = subtotal + cgst + sgst + igst;

    return {
      subtotal,
      discountTotal,
      cgst,
      sgst,
      igst,
      grandTotal,
    };
  };

  const totals = calculateTotals();

  // Create or Update Mutation
  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        contact_id: contactId,
        po_number: poNumber,
        order_date: orderDate,
        due_date: dueDate,
        pos_state_code: placeOfSupply,
        line_items: lines.map((l) => ({
          product_id: l.product_id,
          quantity: l.quantity,
          rate: l.rate,
          discount: l.discount,
          hsn_sac: l.hsn_sac,
          gst_rate: l.gst_rate
        })),
      };

      if (isEdit) {
        return apiClient.put(`/purchase-orders/${editId}`, payload);
      } else {
        return apiClient.post("/purchase-orders", payload);
      }
    },
    onSuccess: () => {
      onSuccess();
    },
    onError: (err: any) => {
      const msg = err.response?.data?.detail || "Failed to save purchase order. Check API inputs.";
      setFormError(msg);
    }
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    if (!contactId) {
      setFormError("Vendor selection is required.");
      return;
    }
    if (!poNumber) {
      setFormError("PO number is required.");
      return;
    }
    if (new Date(dueDate) < new Date(orderDate)) {
      setFormError("Due date must be on or after order date.");
      return;
    }
    const hasEmptyProduct = lines.some((l) => !l.product_id);
    if (hasEmptyProduct) {
      setFormError("Please select a product for all line items.");
      return;
    }
    const hasInvalidQty = lines.some((l) => l.quantity <= 0);
    if (hasInvalidQty) {
      setFormError("Quantity must be greater than zero for all line items.");
      return;
    }

    saveMutation.mutate();
  };

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
    }).format(val);
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={() => onNavigate("purchase_orders")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">
          {isEdit ? "Edit Purchase Order" : "New Purchase Order"}
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
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
          {/* Vendor Selection */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Vendor</label>
            <select
              value={contactId}
              onChange={(e) => handleVendorChange(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            >
              <option value="">-- Select Vendor --</option>
              {vendors.map((v) => (
                <option key={v.id} value={v.id}>
                  {v.name} (Code: {v.state_code})
                </option>
              ))}
            </select>
          </div>

          {/* Place of Supply */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Place of Supply (POS)</label>
            <select
              value={placeOfSupply}
              onChange={(e) => setPlaceOfSupply(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              {STATE_CODES.map((s) => (
                <option key={s.code} value={s.code}>
                  {s.name}
                </option>
              ))}
            </select>
          </div>

          {/* PO Number */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Purchase Order Number</label>
            <input
              type="text"
              value={poNumber}
              onChange={(e) => setPoNumber(e.target.value)}
              placeholder="e.g. PO-2026-0001"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          {/* Order Date */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Order Date</label>
            <input
              type="date"
              value={orderDate}
              onChange={(e) => setOrderDate(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          {/* Due Date */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Expected Delivery/Due Date</label>
            <input
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>
        </div>

        {/* Line Items */}
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
          <div className="bg-slate-50 border-b border-slate-100 px-6 py-3.5 flex justify-between items-center">
            <span className="font-semibold text-sm text-slate-700">Line Items</span>
            <button
              type="button"
              onClick={addLine}
              className="inline-flex items-center gap-1.5 text-xs font-semibold text-brand-600 hover:text-brand-700 transition"
            >
              <Plus className="w-4 h-4" /> Add Item
            </button>
          </div>

          <div className="p-6 space-y-4">
            {lines.map((line, idx) => (
              <div key={idx} className="flex flex-col md:flex-row items-start md:items-center gap-4 border-b border-slate-50 pb-4 last:border-0 last:pb-0">
                {/* Product Select */}
                <div className="flex-1 min-w-[200px] space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">Item</label>
                  <select
                    value={line.product_id}
                    onChange={(e) => handleLineProductChange(idx, e.target.value)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm bg-white focus:ring-1 focus:ring-brand-500 focus:outline-none"
                    required
                  >
                    <option value="">-- Choose Product --</option>
                    {products.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name} ({p.sku})
                      </option>
                    ))}
                  </select>
                </div>

                {/* HSN */}
                <div className="w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">HSN/SAC</label>
                  <input
                    type="text"
                    value={line.hsn_sac}
                    readOnly
                    className="w-full px-2 py-1.5 border border-slate-100 bg-slate-50 text-slate-500 rounded text-sm focus:outline-none"
                  />
                </div>

                {/* Quantity */}
                <div className="w-20 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">Quantity</label>
                  <input
                    type="number"
                    min="1"
                    step="any"
                    value={line.quantity}
                    onChange={(e) => handleLineChange(idx, "quantity", parseFloat(e.target.value) || 0)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm focus:ring-1 focus:ring-brand-500 focus:outline-none"
                    required
                  />
                </div>

                {/* Rate */}
                <div className="w-28 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">Rate (₹)</label>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={line.rate}
                    onChange={(e) => handleLineChange(idx, "rate", parseFloat(e.target.value) || 0)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm focus:ring-1 focus:ring-brand-500 focus:outline-none"
                    required
                  />
                </div>

                {/* Discount */}
                <div className="w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">Discount (₹)</label>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={line.discount}
                    onChange={(e) => handleLineChange(idx, "discount", parseFloat(e.target.value) || 0)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm focus:ring-1 focus:ring-brand-500 focus:outline-none"
                  />
                </div>

                {/* GST */}
                <div className="w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-slate-400 uppercase">GST Rate</label>
                  <select
                    value={line.gst_rate}
                    onChange={(e) => handleLineChange(idx, "gst_rate", parseFloat(e.target.value) || 0)}
                    className="w-full px-2 py-1.5 border border-slate-200 rounded text-sm bg-white focus:ring-1 focus:ring-brand-500 focus:outline-none"
                  >
                    <option value="0">0%</option>
                    <option value="5">5%</option>
                    <option value="12">12%</option>
                    <option value="18">18%</option>
                    <option value="28">28%</option>
                  </select>
                </div>

                {/* Subtotal */}
                <div className="w-28 space-y-1 text-right">
                  <span className="block text-[10px] font-semibold text-slate-400 uppercase">Subtotal</span>
                  <span className="text-sm font-semibold text-slate-700 block py-1.5">
                    {formatCurrency(line.quantity * line.rate - line.discount)}
                  </span>
                </div>

                {/* Delete button */}
                <div className="self-end md:self-center py-1.5">
                  <button
                    type="button"
                    onClick={() => removeLine(idx)}
                    disabled={lines.length === 1}
                    className="p-1.5 text-slate-400 hover:text-rose-600 rounded hover:bg-rose-50 disabled:opacity-30 disabled:hover:bg-transparent transition"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Total Aggregates */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm md:col-span-2">
            <h3 className="font-semibold text-sm text-slate-700 mb-2">Purchase Terms</h3>
            <textarea
              rows={4}
              placeholder="Record vendor delivery constraints or shipping reference details..."
              className="w-full p-3 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>

          <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-3">
            <h3 className="font-semibold text-sm text-slate-700 pb-2 border-b border-slate-100">Aggregated Totals</h3>
            <div className="flex justify-between text-sm text-slate-600">
              <span>Subtotal</span>
              <span>{formatCurrency(totals.subtotal)}</span>
            </div>
            {totals.discountTotal > 0 && (
              <div className="flex justify-between text-sm text-slate-600">
                <span>Discount Total</span>
                <span className="text-rose-600">-{formatCurrency(totals.discountTotal)}</span>
              </div>
            )}
            {totals.cgst > 0 && (
              <div className="flex justify-between text-xs text-slate-500 italic pl-2">
                <span>CGST (Central)</span>
                <span>{formatCurrency(totals.cgst)}</span>
              </div>
            )}
            {totals.sgst > 0 && (
              <div className="flex justify-between text-xs text-slate-500 italic pl-2">
                <span>SGST (State)</span>
                <span>{formatCurrency(totals.sgst)}</span>
              </div>
            )}
            {totals.igst > 0 && (
              <div className="flex justify-between text-xs text-slate-500 italic pl-2">
                <span>IGST (Integrated)</span>
                <span>{formatCurrency(totals.igst)}</span>
              </div>
            )}
            <div className="flex justify-between text-base font-bold text-slate-900 pt-2 border-t border-slate-100">
              <span>Grand Total</span>
              <span className="text-brand-900">{formatCurrency(totals.grandTotal)}</span>
            </div>
          </div>
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-3">
          <button
            type="button"
            onClick={() => onNavigate("purchase_orders")}
            className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saveMutation.isPending}
            className="px-6 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50"
          >
            {saveMutation.isPending ? "Saving..." : isEdit ? "Update Order" : "Save Draft"}
          </button>
        </div>
      </form>
    </div>
  );
}
