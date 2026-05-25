import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Trash2, Plus, ArrowLeft, AlertCircle } from "lucide-react";

interface InvoiceFormProps {
  editId?: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail", invoiceId?: string) => void;
  onSuccess: () => void;
}

interface ContactItem {
  id: string;
  name: string;
  state_code: string;
}

interface ProductItem {
  id: string;
  name: string;
  sku: string;
  hsn_sac: string;
  sales_price: number;
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

// Indian State Codes list for dropdown
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

export default function InvoiceForm({ editId, onNavigate, onSuccess }: InvoiceFormProps) {
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
  const [invoiceNumber, setInvoiceNumber] = useState("");
  const [issueDate, setIssueDate] = useState(new Date().toISOString().split("T")[0]);
  const [dueDate, setDueDate] = useState(new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString().split("T")[0]);
  const [placeOfSupply, setPlaceOfSupply] = useState(originStateCode);
  const [lines, setLines] = useState<LineItemDraft[]>([
    { product_id: "", quantity: 1, rate: 0, discount: 0, hsn_sac: "", gst_rate: 18 }
  ]);
  const [formError, setFormError] = useState("");

  // Fetch Customers & Products from API
  const { data: contacts = [] } = useQuery<ContactItem[]>({
    queryKey: ["contacts"],
    queryFn: async () => {
      const res = await apiClient.get("/contacts");
      return res.data;
    }
  });

const { data: products = [] } = useQuery<ProductItem[]>({
  queryKey: ["products"],
  queryFn: async () => {
    const res = await apiClient.get("/products");
    return res.data;
  }
});

  // Fetch Invoice details if editing
  const { data: invoice } = useQuery({
    queryKey: ["invoice", editId],
    queryFn: async () => {
      const res = await apiClient.get(`/invoices/${editId}`);
      return res.data;
    },
    enabled: isEdit,
  });

  // Load existing invoice data into states
  useEffect(() => {
    if (invoice && isEdit) {
      setContactId(invoice.contact_id);
      setInvoiceNumber(invoice.invoice_number);
      setIssueDate(invoice.issue_date);
      setDueDate(invoice.due_date);
      setPlaceOfSupply(invoice.pos_state_code);
      setLines(
        invoice.lines.map((l: any) => ({
          product_id: l.product_id,
          quantity: parseFloat(l.quantity),
          rate: parseFloat(l.rate),
          discount: parseFloat(l.discount),
          hsn_sac: l.hsn_sac,
          gst_rate: parseFloat(l.gst_rate)
        }))
      );
    }
  }, [invoice, isEdit]);

  // Set initial invoice sequence number if creating
  useEffect(() => {
    if (!isEdit && !invoiceNumber) {
      const randSeq = Math.floor(1000 + Math.random() * 9000);
      setInvoiceNumber(`INV/2026-27/${randSeq}`);
    }
  }, [isEdit, invoiceNumber]);

  // Handle customer state extraction
  const handleCustomerChange = (selectedContactId: string) => {
    setContactId(selectedContactId);
    const selected = contacts.find((c) => c.id === selectedContactId);
    if (selected) {
      setPlaceOfSupply(selected.state_code);
    }
  };

  // Handle line item inputs
  const handleLineProductChange = (index: number, productId: string) => {
    const selectedProd = products.find((p) => p.id === productId);
    if (selectedProd) {
      const newLines = [...lines];
      newLines[index] = {
        product_id: productId,
        quantity: lines[index].quantity || 1,
        rate: selectedProd.sales_price,
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

  // Perform client-side tax splits for responsive UI display
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
        invoice_number: invoiceNumber,
        issue_date: issueDate,
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
        return apiClient.put(`/invoices/${editId}`, payload);
      } else {
        return apiClient.post("/invoices", payload);
      }
    },
    onSuccess: () => {
      onSuccess();
    },
    onError: (err: any) => {
      const msg = err.response?.data?.detail || "Failed to save invoice. Ensure API parameters are valid.";
      setFormError(msg);
    }
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    // Simple validations
    if (!contactId) {
      setFormError("Customer selection is required.");
      return;
    }
    if (!invoiceNumber) {
      setFormError("Invoice number is required.");
      return;
    }
    if (new Date(dueDate) < new Date(issueDate)) {
      setFormError("Due date must be on or after issue date.");
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
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button
          type="button"
          onClick={() => onNavigate("list")}
          className="p-1.5 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-4 h-4" />
        </button>
        <h1 className="text-xl font-bold tracking-tight text-zinc-900">
          {isEdit ? "Edit Invoice" : "Create Invoice"}
        </h1>
      </div>

      {formError && (
        <div className="flex items-start gap-3 p-4 bg-red-50 border border-red-200 text-red-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-xs">
            <span className="font-semibold">Validation Error:</span> {formError}
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm">
          {/* Customer Selection */}
          <div className="space-y-1">
            <label className="form-label">Customer</label>
            <select
              value={contactId}
              onChange={(e) => handleCustomerChange(e.target.value)}
              className="form-select bg-white"
              required
            >
              <option value="">-- Select Customer --</option>
              {contacts.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} (Code: {c.state_code})
                </option>
              ))}
            </select>
          </div>

          {/* Place of Supply */}
          <div className="space-y-1">
            <label className="form-label">Place of Supply (POS)</label>
            <select
              value={placeOfSupply}
              onChange={(e) => setPlaceOfSupply(e.target.value)}
              className="form-select bg-white"
            >
              {STATE_CODES.map((s) => (
                <option key={s.code} value={s.code}>
                  {s.name}
                </option>
              ))}
            </select>
          </div>

          {/* Invoice Number */}
          <div className="space-y-1">
            <label className="form-label">Invoice Number</label>
            <input
              type="text"
              value={invoiceNumber}
              onChange={(e) => setInvoiceNumber(e.target.value)}
              placeholder="e.g. INV/2026-27/0001"
              className="form-input"
              required
            />
          </div>

          {/* Issue Date */}
          <div className="space-y-1">
            <label className="form-label">Issue Date</label>
            <input
              type="date"
              value={issueDate}
              onChange={(e) => setIssueDate(e.target.value)}
              className="form-input"
              required
            />
          </div>

          {/* Due Date */}
          <div className="space-y-1">
            <label className="form-label">Due Date</label>
            <input
              type="date"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
              className="form-input"
              required
            />
          </div>
        </div>

        {/* Line Items Table */}
        <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm overflow-hidden">
          <div className="bg-zinc-50 border-b border-zinc-200 px-5 py-3 flex justify-between items-center">
            <span className="font-semibold text-sm text-zinc-700">Line Items</span>
            <button
              type="button"
              onClick={addLine}
              className="btn-secondary py-1 px-2.5 text-xs font-semibold"
            >
              <Plus className="w-3.5 h-3.5" /> Add Item
            </button>
          </div>

          <div className="p-4 md:p-6 space-y-4">
            {lines.map((line, idx) => (
              <div key={idx} className="grid grid-cols-2 md:flex md:flex-row items-end md:items-center gap-3 border-b border-zinc-100 pb-4 last:border-0 last:pb-0">
                {/* Product Select */}
                <div className="col-span-2 md:flex-1 md:min-w-[200px] space-y-1">
                  <label className="text-[10px] font-semibold text-zinc-400 uppercase tracking-wider block">Item</label>
                  <select
                    value={line.product_id}
                    onChange={(e) => handleLineProductChange(idx, e.target.value)}
                    className="form-select text-xs py-1.5 px-2 bg-white"
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

                {/* HSN Code (Readonly for reference) */}
                <div className="col-span-1 md:w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-zinc-400 uppercase tracking-wider block">HSN/SAC</label>
                  <input
                    type="text"
                    value={line.hsn_sac}
                    readOnly
                    className="form-input text-xs py-1.5 px-2 bg-zinc-50 text-zinc-500 cursor-not-allowed border-zinc-200/60"
                  />
                </div>

                {/* Quantity */}
                <div className="col-span-1 md:w-20 space-y-1">
                  <label className="text-[10px] font-semibold text-zinc-400 uppercase tracking-wider block">Quantity</label>
                  <input
                    type="number"
                    min="1"
                    step="any"
                    value={line.quantity}
                    onChange={(e) => handleLineChange(idx, "quantity", parseFloat(e.target.value) || 0)}
                    className="form-input text-xs py-1.5 px-2 font-mono"
                    required
                  />
                </div>

                {/* Rate */}
                <div className="col-span-1 md:w-28 space-y-1">
                  <label className="text-[10px] font-semibold text-zinc-400 uppercase tracking-wider block">Rate (₹)</label>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={line.rate}
                    onChange={(e) => handleLineChange(idx, "rate", parseFloat(e.target.value) || 0)}
                    className="form-input text-xs py-1.5 px-2 font-mono"
                    required
                  />
                </div>

                {/* Discount */}
                <div className="col-span-1 md:w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-zinc-400 uppercase tracking-wider block">Discount (₹)</label>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={line.discount}
                    onChange={(e) => handleLineChange(idx, "discount", parseFloat(e.target.value) || 0)}
                    className="form-input text-xs py-1.5 px-2 font-mono"
                  />
                </div>

                {/* GST rate */}
                <div className="col-span-1 md:w-24 space-y-1">
                  <label className="text-[10px] font-semibold text-zinc-400 uppercase tracking-wider block">GST Rate</label>
                  <select
                    value={line.gst_rate}
                    onChange={(e) => handleLineChange(idx, "gst_rate", parseFloat(e.target.value) || 0)}
                    className="form-select text-xs py-1.5 px-2 bg-white"
                  >
                    <option value="0">0%</option>
                    <option value="5">5%</option>
                    <option value="12">12%</option>
                    <option value="18">18%</option>
                    <option value="28">28%</option>
                  </select>
                </div>

                {/* Subtotal Display */}
                <div className="col-span-1 md:w-28 space-y-1 text-right">
                  <span className="block text-[10px] font-semibold text-zinc-400 uppercase tracking-wider">Subtotal</span>
                  <span className="text-xs font-semibold text-zinc-700 block py-2 font-mono">
                    {formatCurrency(line.quantity * line.rate - line.discount)}
                  </span>
                </div>

                {/* Delete button */}
                <div className="col-span-2 md:col-span-1 self-end md:self-center py-1 flex justify-end md:justify-start">
                  <button
                    type="button"
                    onClick={() => removeLine(idx)}
                    disabled={lines.length === 1}
                    className="p-2 text-zinc-400 hover:text-red-600 rounded-lg hover:bg-red-50 disabled:opacity-30 disabled:hover:bg-transparent transition duration-150"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Totals Summary */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm md:col-span-2 space-y-2">
            <h3 className="font-semibold text-xs uppercase tracking-wider text-zinc-500">Terms & Notes</h3>
            <textarea
              rows={4}
              placeholder="Provide client payment instructions or terms of service..."
              className="form-textarea"
            />
          </div>

          <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm space-y-3 text-xs">
            <h3 className="font-semibold text-xs uppercase tracking-wider text-zinc-500 pb-2 border-b border-zinc-100">Calculated Summary</h3>
            <div className="flex justify-between text-zinc-600">
              <span>Subtotal</span>
              <span className="font-mono font-medium text-zinc-800">{formatCurrency(totals.subtotal)}</span>
            </div>
            {totals.discountTotal > 0 && (
              <div className="flex justify-between text-zinc-600">
                <span>Discount Total</span>
                <span className="text-red-600 font-mono font-medium">-{formatCurrency(totals.discountTotal)}</span>
              </div>
            )}
            {totals.cgst > 0 && (
              <div className="flex justify-between text-zinc-500 italic pl-2">
                <span>CGST (Central Tax)</span>
                <span className="font-mono">{formatCurrency(totals.cgst)}</span>
              </div>
            )}
            {totals.sgst > 0 && (
              <div className="flex justify-between text-zinc-500 italic pl-2">
                <span>SGST (State Tax)</span>
                <span className="font-mono">{formatCurrency(totals.sgst)}</span>
              </div>
            )}
            {totals.igst > 0 && (
              <div className="flex justify-between text-zinc-500 italic pl-2">
                <span>IGST (Integrated Tax)</span>
                <span className="font-mono">{formatCurrency(totals.igst)}</span>
              </div>
            )}
            <div className="flex justify-between text-sm font-bold text-zinc-900 pt-2 border-t border-zinc-100">
              <span>Invoice Total</span>
              <span className="text-zinc-950 font-mono">{formatCurrency(totals.grandTotal)}</span>
            </div>
          </div>
        </div>

        {/* Form Actions */}
        <div className="flex justify-end gap-3 pb-8">
          <button
            type="button"
            onClick={() => onNavigate("list")}
            className="btn-secondary"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saveMutation.isPending}
            className="btn-primary px-6"
          >
            {saveMutation.isPending ? "Saving..." : isEdit ? "Update Invoice" : "Save Draft"}
          </button>
        </div>
      </form>
    </div>
  );
}
