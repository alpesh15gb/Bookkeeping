import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Trash2, Plus, ArrowLeft, AlertCircle, Save, Send, Printer, Share2, Cog } from "lucide-react";
import logo from "../../logo.png";
import { useUnsavedChangesWarning } from "../../hooks/useUnsavedChangesWarning";

interface InvoiceFormProps {
  editId?: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail", invoiceId?: string) => void;
  onSuccess: () => void;
}

interface ContactItem {
  id: string;
  name: string;
  gstin?: string;
  state_code: string;
  billing_address?: string;
  shipping_address?: string;
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

// Helper to convert number to Indian Rupee Words
function convertNumberToWords(amount: number): string {
  const fraction = Math.round((amount % 1) * 100);
  let fractionText = "";

  if (fraction > 0) {
    fractionText = ` and ${numberToWordsString(fraction)} Paise`;
  }

  const wholeNumber = Math.floor(amount);
  const wholeText = numberToWordsString(wholeNumber);

  if (!wholeText && !fractionText) return "Rupees Zero Only";
  if (!wholeText) return "Paise " + fractionText + " Only";

  return `Rupees ${wholeText}${fractionText} Only`;
}

function numberToWordsString(num: number): string {
  if (num === 0) return "";
  const singleDigits = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
  const doubleDigits = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];

  if (num < 20) return singleDigits[num];
  if (num < 100) return doubleDigits[Math.floor(num / 10)] + (num % 10 !== 0 ? " " + singleDigits[num % 10] : "");

  // Indian numbering system splits (Lakh, Thousand, Hundred)
  if (num < 1000) return singleDigits[Math.floor(num / 100)] + " Hundred" + (num % 100 !== 0 ? " " + numberToWordsString(num % 100) : "");
  if (num < 100000) return numberToWordsString(Math.floor(num / 1000)) + " Thousand" + (num % 1000 !== 0 ? " " + numberToWordsString(num % 1000) : "");
  if (num < 10000000) return numberToWordsString(Math.floor(num / 100000)) + " Lakh" + (num % 100000 !== 0 ? " " + numberToWordsString(num % 100000) : "");
  return numberToWordsString(Math.floor(num / 10000000)) + " Crore" + (num % 10000000 !== 0 ? " " + numberToWordsString(num % 10000000) : "");
}

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
  const [dueDate, setDueDate] = useState(new Date(Date.now() + 15 * 24 * 3600 * 1000).toISOString().split("T")[0]);
  const [placeOfSupply, setPlaceOfSupply] = useState(originStateCode);
  const [billingAddress, setBillingAddress] = useState("");
  const [shippingAddress, setShippingAddress] = useState("");
  const [sameAsBilling, setSameAsBilling] = useState(true);
  const [discountPercent, setDiscountPercent] = useState(0);
  const [shippingCharges, setShippingCharges] = useState(0);
  const [lines, setLines] = useState<LineItemDraft[]>([
    { product_id: "", quantity: 1, rate: 0, discount: 0, hsn_sac: "", gst_rate: 18 }
  ]);
  const [formError, setFormError] = useState("");

  // Fetch Customers & Products
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

  // Sync edit values
  useEffect(() => {
    if (invoice && isEdit) {
      setContactId(invoice.contact_id);
      setInvoiceNumber(invoice.invoice_number);
      setIssueDate(invoice.issue_date);
      setDueDate(invoice.due_date);
      setPlaceOfSupply(invoice.pos_state_code);
      setBillingAddress(invoice.billing_address || "");
      setShippingAddress(invoice.shipping_address || "");
      setDiscountPercent(parseFloat(invoice.discount_rate || 0));
      setShippingCharges(parseFloat(invoice.shipping_charges || 0));
      setLines(
        invoice.lines.map((l: any) => ({
          product_id: l.product_id,
          quantity: parseFloat(l.quantity),
          rate: parseFloat(l.rate),
          discount: parseFloat(l.discount || 0),
          hsn_sac: l.hsn_sac || "",
          gst_rate: parseFloat(l.gst_rate)
        }))
      );
    }
  }, [invoice, isEdit]);

  // Invoice series generation
  useEffect(() => {
    if (!isEdit && !invoiceNumber) {
      const randSeq = Math.floor(100000 + Math.random() * 900000);
      setInvoiceNumber(`INV-2025-${randSeq}`);
    }
  }, [isEdit, invoiceNumber]);

  // Watch Same as Billing
  useEffect(() => {
    if (sameAsBilling) {
      setShippingAddress(billingAddress);
    }
  }, [billingAddress, sameAsBilling]);

  const handleCustomerChange = (selectedContactId: string) => {
    setContactId(selectedContactId);
    const selected = contacts.find((c) => c.id === selectedContactId);
    if (selected) {
      setPlaceOfSupply(selected.state_code);
      const addr = selected.billing_address || `${selected.name}, Main Business District, Delhi, India`;
      setBillingAddress(addr);
      if (sameAsBilling) {
        setShippingAddress(addr);
      } else {
        setShippingAddress(selected.shipping_address || addr);
      }
    }
  };

  const handleLineProductChange = (index: number, productId: string) => {
    const selectedProd = products.find((p) => p.id === productId);
    if (selectedProd) {
      const newLines = [...lines];
      newLines[index] = {
        product_id: productId,
        quantity: lines[index].quantity || 1,
        rate: selectedProd.sales_price,
        discount: lines[index].discount || 0,
        hsn_sac: selectedProd.hsn_sac || "84716050",
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

  // Live total calculations
  const calculateTotals = () => {
    let subtotal = 0;
    let cgst = 0;
    let sgst = 0;
    let igst = 0;

    const isIntraState = originStateCode === placeOfSupply;

    lines.forEach((line) => {
      const lineBase = (line.quantity || 0) * (line.rate || 0) - (line.discount || 0);
      subtotal += lineBase;

      const lineTax = lineBase * ((line.gst_rate || 0) / 100);
      if (isIntraState) {
        cgst += lineTax / 2;
        sgst += lineTax / 2;
      } else {
        igst += lineTax;
      }
    });

    const discountValue = subtotal * (discountPercent / 100);
    const taxableAmount = subtotal - discountValue;

    // Recalculate CGST/SGST/IGST based on taxable amount
    let taxMultiplier = taxableAmount / (subtotal || 1);
    if (subtotal === 0) taxMultiplier = 0;
    
    const finalCgst = cgst * taxMultiplier;
    const finalSgst = sgst * taxMultiplier;
    const finalIgst = igst * taxMultiplier;

    const grandTotal = taxableAmount + finalCgst + finalSgst + finalIgst + Number(shippingCharges);

    return {
      subtotal,
      discountValue,
      taxableAmount,
      cgst: finalCgst,
      sgst: finalSgst,
      igst: finalIgst,
      grandTotal,
    };
  };

  const totals = calculateTotals();

  // Save Mutation
  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        contact_id: contactId,
        invoice_number: invoiceNumber,
        issue_date: issueDate,
        due_date: dueDate,
        pos_state_code: placeOfSupply,
        billing_address: billingAddress,
        shipping_address: shippingAddress,
        discount_rate: discountPercent,
        shipping_charges: shippingCharges,
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
      const msg = err.response?.data?.detail || "Failed to save invoice.";
      setFormError(msg);
    }
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    if (!contactId) {
      setFormError("Customer selection is required.");
      return;
    }
    if (!invoiceNumber) {
      setFormError("Invoice number is required.");
      return;
    }
    const hasEmptyProduct = lines.some((l) => !l.product_id);
    if (hasEmptyProduct) {
      setFormError("Please select an item for all lines.");
      return;
    }

    saveMutation.mutate();
  };

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
    }).format(val || 0);
  };

  const selectedCustomer = contacts.find(c => c.id === contactId);

  return (
    <div className="space-y-5">
      {/* Top action header */}
      <div className="flex justify-between items-center pb-2 border-b border-zinc-200">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => onNavigate("list")}
            className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">
            {isEdit ? "Edit Invoice" : "Create Invoice"}
          </h1>
        </div>
        <button className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-zinc-50 text-zinc-700 border border-zinc-200 rounded-lg text-xs font-semibold shadow-sm transition">
          <Cog className="w-4 h-4 text-zinc-500" /> Customize Template
        </button>
      </div>

      {formError && (
        <div className="flex items-start gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-xs">
            <span className="font-semibold">Validation Error:</span> {formError}
          </div>
        </div>
      )}

      {/* Grid container: form on left, invoice sheet on right */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        
        {/* LEFT COLUMN: Data entry form */}
        <div className="lg:col-span-5 space-y-5">
          <form onSubmit={handleSubmit} className="space-y-5">
            
            {/* Core details */}
            <div className="bg-white p-5 rounded-xl border border-zinc-200 shadow-sm space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Invoice Date *</label>
                  <input
                    type="date"
                    value={issueDate}
                    onChange={(e) => setIssueDate(e.target.value)}
                    className="w-full text-xs px-2.5 py-1.5 border border-zinc-200 rounded-md bg-white focus:outline-none"
                    required
                  />
                </div>
                <div className="space-y-1">
                  <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Invoice Number *</label>
                  <input
                    type="text"
                    value={invoiceNumber}
                    onChange={(e) => setInvoiceNumber(e.target.value)}
                    className="w-full text-xs px-2.5 py-1.5 border border-zinc-200 rounded-md focus:outline-none"
                    required
                  />
                </div>
              </div>

              <div className="space-y-1">
                <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Customer *</label>
                <select
                  value={contactId}
                  onChange={(e) => handleCustomerChange(e.target.value)}
                  className="w-full text-xs px-2.5 py-1.5 border border-zinc-200 rounded-md bg-white focus:outline-none"
                  required
                >
                  <option value="">Search customer by name, GSTIN...</option>
                  {contacts.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name} ({c.state_code})
                    </option>
                  ))}
                </select>
              </div>

              <div className="grid grid-cols-1 gap-3">
                <div className="space-y-1">
                  <div className="flex justify-between items-center">
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Billing Address *</label>
                  </div>
                  <textarea
                    rows={2}
                    value={billingAddress}
                    onChange={(e) => setBillingAddress(e.target.value)}
                    className="w-full text-xs p-2 border border-zinc-200 rounded-md focus:outline-none"
                    placeholder="Enter customer billing address..."
                  />
                </div>

                <div className="space-y-1">
                  <div className="flex justify-between items-center">
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Shipping Address</label>
                    <div className="flex items-center gap-1.5 text-xs text-zinc-500 font-medium">
                      <input
                        type="checkbox"
                        id="sameBilling"
                        checked={sameAsBilling}
                        onChange={(e) => setSameAsBilling(e.target.checked)}
                        className="rounded border-zinc-300 text-brand-600 focus:ring-brand-500"
                      />
                      <label htmlFor="sameBilling" className="cursor-pointer text-[10px]">Same as billing</label>
                    </div>
                  </div>
                  <textarea
                    rows={2}
                    value={shippingAddress}
                    onChange={(e) => setShippingAddress(e.target.value)}
                    disabled={sameAsBilling}
                    className="w-full text-xs p-2 border border-zinc-200 rounded-md focus:outline-none bg-zinc-50/50 disabled:bg-zinc-50 disabled:text-zinc-400"
                    placeholder="Enter customer shipping address..."
                  />
                </div>
              </div>
            </div>

            {/* Line items editor */}
            <div className="bg-white p-5 rounded-xl border border-zinc-200 shadow-sm space-y-4">
              <div className="flex justify-between items-center">
                <h3 className="font-bold text-xs uppercase tracking-wider text-zinc-500">Items</h3>
                <button
                  type="button"
                  onClick={addLine}
                  className="inline-flex items-center gap-1 text-[11px] font-bold text-amber-600 hover:text-amber-700"
                >
                  <Plus className="w-3.5 h-3.5" /> Add Item
                </button>
              </div>

              <div className="space-y-4 max-h-[350px] overflow-y-auto pr-1">
                {lines.map((line, idx) => (
                  <div key={idx} className="p-3 bg-zinc-50 rounded-lg border border-zinc-150 space-y-2.5 relative">
                    <div className="flex justify-between items-center">
                      <span className="text-[10px] font-bold text-zinc-400"># {idx + 1}</span>
                      <button
                        type="button"
                        onClick={() => removeLine(idx)}
                        disabled={lines.length === 1}
                        className="text-zinc-400 hover:text-red-500 disabled:opacity-30 transition"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>

                    <div className="space-y-1">
                      <label className="text-[9px] font-bold text-zinc-400 uppercase tracking-wider block">Item Name *</label>
                      <select
                        value={line.product_id}
                        onChange={(e) => handleLineProductChange(idx, e.target.value)}
                        className="w-full text-xs px-2.5 py-1.5 border border-zinc-200 rounded bg-white focus:outline-none"
                        required
                      >
                        <option value="">-- Choose Product --</option>
                        {products.map((p) => (
                          <option key={p.id} value={p.id}>
                            {p.name}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="grid grid-cols-3 gap-2">
                      <div className="space-y-0.5">
                        <label className="text-[9px] font-bold text-zinc-400 uppercase tracking-wider block">HSN Code</label>
                        <input
                          type="text"
                          value={line.hsn_sac}
                          readOnly
                          className="w-full text-xs px-2 py-1 bg-zinc-100 text-zinc-500 border border-zinc-200 rounded cursor-not-allowed text-center font-mono"
                        />
                      </div>
                      <div className="space-y-0.5">
                        <label className="text-[9px] font-bold text-zinc-400 uppercase tracking-wider block">Qty *</label>
                        <input
                          type="number"
                          min="1"
                          step="any"
                          value={line.quantity}
                          onChange={(e) => handleLineChange(idx, "quantity", parseFloat(e.target.value) || 0)}
                          className="w-full text-xs px-2 py-1 border border-zinc-200 rounded font-mono text-center"
                          required
                        />
                      </div>
                      <div className="space-y-0.5">
                        <label className="text-[9px] font-bold text-zinc-400 uppercase tracking-wider block">Rate (₹) *</label>
                        <input
                          type="number"
                          min="0"
                          step="0.01"
                          value={line.rate}
                          onChange={(e) => handleLineChange(idx, "rate", parseFloat(e.target.value) || 0)}
                          className="w-full text-xs px-2 py-1 border border-zinc-200 rounded font-mono text-center"
                          required
                        />
                      </div>
                    </div>

                    <div className="grid grid-cols-2 gap-2 pt-1 border-t border-zinc-200/50">
                      <div className="space-y-0.5">
                        <label className="text-[9px] font-bold text-zinc-400 uppercase tracking-wider block">Discount (₹)</label>
                        <input
                          type="number"
                          min="0"
                          step="0.01"
                          value={line.discount}
                          onChange={(e) => handleLineChange(idx, "discount", parseFloat(e.target.value) || 0)}
                          className="w-full text-xs px-2 py-1 border border-zinc-200 rounded font-mono text-center"
                        />
                      </div>
                      <div className="space-y-0.5">
                        <label className="text-[9px] font-bold text-zinc-400 uppercase tracking-wider block">GST Rate</label>
                        <select
                          value={line.gst_rate}
                          onChange={(e) => handleLineChange(idx, "gst_rate", parseFloat(e.target.value) || 0)}
                          className="w-full text-xs px-2 py-1 border border-zinc-200 rounded bg-white focus:outline-none text-center"
                        >
                          <option value="0">0%</option>
                          <option value="5">5%</option>
                          <option value="12">12%</option>
                          <option value="18">18%</option>
                          <option value="28">28%</option>
                        </select>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Calculations & Discounts */}
            <div className="bg-white p-5 rounded-xl border border-zinc-200 shadow-sm space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1">
                  <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Discount (%)</label>
                  <input
                    type="number"
                    min="0"
                    max="100"
                    value={discountPercent}
                    onChange={(e) => setDiscountPercent(parseFloat(e.target.value) || 0)}
                    className="w-full text-xs px-2.5 py-1.5 border border-zinc-200 rounded-md font-mono"
                  />
                </div>
                <div className="space-y-1">
                  <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Shipping Charges</label>
                  <input
                    type="number"
                    min="0"
                    value={shippingCharges}
                    onChange={(e) => setShippingCharges(parseFloat(e.target.value) || 0)}
                    className="w-full text-xs px-2.5 py-1.5 border border-zinc-200 rounded-md font-mono"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Place of Supply (POS)</label>
                <select
                  value={placeOfSupply}
                  onChange={(e) => setPlaceOfSupply(e.target.value)}
                  className="w-full text-xs px-2.5 py-1.5 border border-zinc-200 rounded-md bg-white focus:outline-none"
                >
                  {STATE_CODES.map((s) => (
                    <option key={s.code} value={s.code}>
                      {s.name}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* Submit & Form Actions (Gold themed) */}
            <div className="grid grid-cols-4 gap-2 pt-2 pb-8">
              <button
                type="button"
                onClick={() => onNavigate("list")}
                className="col-span-1 border border-[#DCA035] text-[#DCA035] hover:bg-[#DCA035]/5 py-2 rounded-lg font-bold text-xs transition duration-150 inline-flex items-center justify-center gap-1 shadow-sm"
              >
                <Save className="w-3.5 h-3.5" /> Draft
              </button>
              
              <button
                type="submit"
                disabled={saveMutation.isPending}
                className="col-span-1 bg-[#DCA035] hover:bg-[#C98F2C] text-zinc-950 py-2 rounded-lg font-bold text-xs transition duration-150 inline-flex items-center justify-center gap-1 shadow-sm"
              >
                <Send className="w-3.5 h-3.5" /> Send
              </button>

              <button
                type="button"
                onClick={() => window.print()}
                className="col-span-1 bg-[#DCA035] hover:bg-[#C98F2C] text-zinc-950 py-2 rounded-lg font-bold text-xs transition duration-150 inline-flex items-center justify-center gap-1 shadow-sm"
              >
                <Printer className="w-3.5 h-3.5" /> Print
              </button>

              <button
                type="button"
                className="col-span-1 bg-[#DCA035] hover:bg-[#C98F2C] text-zinc-950 py-2 rounded-lg font-bold text-xs transition duration-150 inline-flex items-center justify-center gap-1 shadow-sm"
              >
                <Share2 className="w-3.5 h-3.5" /> Share
              </button>
            </div>

          </form>
        </div>

        {/* RIGHT COLUMN: TAX INVOICE Sheet Live Preview */}
        <div className="lg:col-span-7 sticky top-20 no-print">
          <div className="bg-white border border-zinc-200 rounded-xl shadow-[0_8px_30px_rgb(0,0,0,0.04)] p-8 max-w-[650px] mx-auto min-h-[750px] flex flex-col justify-between text-zinc-800 text-[10px] leading-relaxed">
            
            {/* Live Sheet Header */}
            <div>
              <div className="flex justify-between items-start pb-6 border-b border-zinc-100">
                <div>
                  <img src={logo} alt="Apex Books Logo" className="h-10 object-contain mb-1" />
                  <span className="text-[8px] text-zinc-400 font-semibold uppercase tracking-wider block">Accounting Made Simple</span>
                </div>
                <div className="text-right">
                  <h2 className="text-sm font-bold text-zinc-900 tracking-wider">TAX INVOICE</h2>
                  <p className="font-mono text-zinc-500 font-semibold">{invoiceNumber || "INV-XXXXXX"}</p>
                  <p className="text-zinc-400 mt-0.5">
                    {issueDate 
                      ? new Date(issueDate).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })
                      : "--"
                    }
                  </p>
                </div>
              </div>

              {/* Bill/Ship column information */}
              <div className="grid grid-cols-2 gap-8 py-5 border-b border-zinc-150/40 text-[9px]">
                <div className="space-y-1">
                  <span className="font-bold text-zinc-400 uppercase tracking-wide block">Bill To</span>
                  <p className="font-bold text-zinc-800 text-[10px] leading-none mb-1">
                    {selectedCustomer?.name || "Customer Name"}
                  </p>
                  <p className="text-zinc-500 whitespace-pre-wrap leading-tight">
                    {billingAddress || "Billing Address Details"}
                  </p>
                  {selectedCustomer && (
                    <p className="text-zinc-600 font-semibold mt-1">
                      GSTIN: <span className="font-mono">{selectedCustomer.gstin || "—"}</span>
                    </p>
                  )}
                </div>
                <div className="space-y-1">
                  <span className="font-bold text-zinc-400 uppercase tracking-wide block">Ship To</span>
                  <p className="font-bold text-zinc-800 text-[10px] leading-none mb-1">
                    {selectedCustomer?.name || "Customer Name"}
                  </p>
                  <p className="text-zinc-500 whitespace-pre-wrap leading-tight">
                    {shippingAddress || "Shipping Address Details"}
                  </p>
                  {selectedCustomer && (
                    <p className="text-zinc-600 font-semibold mt-1">
                      POS: State Code {placeOfSupply}
                    </p>
                  )}
                </div>
              </div>

              {/* Items Sheet list */}
              <div className="py-4">
                <table className="w-full text-left text-[9px] border-collapse">
                  <thead>
                    <tr className="bg-brand-900 text-white font-bold">
                      <th className="px-3 py-1.5 rounded-l text-center font-bold">#</th>
                      <th className="px-3 py-1.5 font-bold">Item Name</th>
                      <th className="px-3 py-1.5 font-bold">HSN Code</th>
                      <th className="px-3 py-1.5 text-center font-bold">Qty</th>
                      <th className="px-3 py-1.5 text-right font-bold">Rate (₹)</th>
                      <th className="px-3 py-1.5 rounded-r text-right font-bold">Amount (₹)</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-zinc-100">
                    {lines.map((line, idx) => {
                      const prod = products.find(p => p.id === line.product_id);
                      const baseAmt = line.quantity * line.rate - line.discount;
                      return (
                        <tr key={idx} className="text-zinc-700">
                          <td className="px-3 py-2.5 text-center text-zinc-400 font-semibold">{idx + 1}</td>
                          <td className="px-3 py-2.5 font-semibold text-zinc-800">{prod?.name || "Selected Item"}</td>
                          <td className="px-3 py-2.5 font-mono text-zinc-500">{line.hsn_sac || "84716050"}</td>
                          <td className="px-3 py-2.5 text-center font-mono font-medium">{line.quantity}</td>
                          <td className="px-3 py-2.5 text-right font-mono">{formatCurrency(line.rate).replace("₹", "")}</td>
                          <td className="px-3 py-2.5 text-right font-mono font-bold text-zinc-800">{formatCurrency(baseAmt).replace("₹", "")}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Calculations summaries and authorized block */}
            <div className="space-y-6">
              
              {/* Bottom split: Left note & word amount, Right aggregates */}
              <div className="grid grid-cols-12 gap-4 items-start pt-4 border-t border-zinc-100">
                <div className="col-span-7 space-y-3">
                  <div className="p-2.5 bg-zinc-50 border border-zinc-150 rounded-lg text-[8px] text-zinc-500 space-y-1">
                    <p className="font-bold text-zinc-600 uppercase tracking-wider text-[7px] leading-none mb-0.5">Payment Terms</p>
                    <p>Thank you for your business! Please make the payment within 15 days from the invoice date.</p>
                  </div>
                  <div className="space-y-0.5">
                    <p className="text-[8px] font-bold text-zinc-400 uppercase tracking-wide">Total Amount (in words)</p>
                    <p className="font-bold text-zinc-700 italic leading-tight pr-4">
                      {convertNumberToWords(totals.grandTotal)}
                    </p>
                  </div>
                </div>

                <div className="col-span-5 space-y-1.5 font-mono text-right text-[9px] text-zinc-600">
                  <div className="flex justify-between">
                    <span>Subtotal:</span>
                    <span className="font-semibold text-zinc-800">{formatCurrency(totals.subtotal).replace("₹", "")}</span>
                  </div>
                  {totals.discountValue > 0 && (
                    <div className="flex justify-between text-red-600">
                      <span>Discount ({discountPercent}%):</span>
                      <span className="font-semibold">-{formatCurrency(totals.discountValue).replace("₹", "")}</span>
                    </div>
                  )}
                  <div className="flex justify-between border-t border-zinc-100 pt-1">
                    <span>Taxable Amount:</span>
                    <span className="font-semibold text-zinc-800">{formatCurrency(totals.taxableAmount).replace("₹", "")}</span>
                  </div>
                  
                  {totals.cgst > 0 && (
                    <div className="flex justify-between text-zinc-400 text-[8px]">
                      <span>CGST (9%):</span>
                      <span>{formatCurrency(totals.cgst).replace("₹", "")}</span>
                    </div>
                  )}
                  {totals.sgst > 0 && (
                    <div className="flex justify-between text-zinc-400 text-[8px]">
                      <span>SGST (9%):</span>
                      <span>{formatCurrency(totals.sgst).replace("₹", "")}</span>
                    </div>
                  )}
                  {totals.igst > 0 && (
                    <div className="flex justify-between text-zinc-400 text-[8px]">
                      <span>IGST (18%):</span>
                      <span>{formatCurrency(totals.igst).replace("₹", "")}</span>
                    </div>
                  )}
                  {shippingCharges > 0 && (
                    <div className="flex justify-between">
                      <span>Shipping:</span>
                      <span className="font-semibold text-zinc-800">{formatCurrency(shippingCharges).replace("₹", "")}</span>
                    </div>
                  )}
                  <div className="flex justify-between border-t-2 border-zinc-900 pt-1.5 text-[11px] font-bold text-zinc-900 uppercase">
                    <span>Total Amount:</span>
                    <span>{formatCurrency(totals.grandTotal)}</span>
                  </div>
                </div>
              </div>

              {/* Signatory footer representation */}
              <div className="flex justify-between items-end pt-4 border-t border-zinc-100/50">
                <div className="flex items-center gap-1.5 text-zinc-400 text-[7px] uppercase font-bold">
                  <span className="h-4 w-4 bg-green-50 text-green-600 rounded-full flex items-center justify-center border border-green-200">✔</span>
                  <span>Digitally Signed Invoice</span>
                </div>
                <div className="text-right space-y-6">
                  <div className="text-[8px] text-zinc-400 font-bold uppercase tracking-wider">For Apex Books</div>
                  <div className="border-t border-zinc-200 pt-1 pr-2">
                    <p className="font-medium text-zinc-800">Arjun Mehta</p>
                    <p className="text-[8px] text-zinc-400">Authorized Signatory</p>
                  </div>
                </div>
              </div>

            </div>

          </div>
        </div>

      </div>
    </div>
  );
}
