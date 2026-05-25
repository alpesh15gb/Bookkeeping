import React, { useState } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, AlertCircle, Plus, Trash2 } from "lucide-react";

interface PaymentFormProps {
  mode: "receipt" | "disbursement";
  onSuccess: () => void;
  onNavigate: (view: "payments" | "payment_receipt" | "payment_disbursement") => void;
}

interface ContactItem {
  id: string;
  name: string;
  contact_type: string;
}

interface InvoiceItem {
  id: string;
  invoice_number: string;
  total: number;
  amount_paid: number;
  contact_name: string;
}

interface BillItem {
  id: string;
  bill_number: string;
  total: number;
  amount_paid: number;
  contact_name: string;
}

interface AllocationDraft {
  invoice_id?: string;
  bill_id?: string;
  amount: number;
}

const PAYMENT_MODES = ["CASH", "BANK", "UPI", "POS", "OTHER"];

export default function PaymentForm({ mode, onSuccess, onNavigate }: PaymentFormProps) {
  const isReceipt = mode === "receipt";

  const [contactId, setContactId] = useState("");
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().split("T")[0]);
  const [amount, setAmount] = useState<number>(0);
  const [paymentMode, setPaymentMode] = useState("BANK");
  const [referenceNumber, setReferenceNumber] = useState("");
  const [description, setDescription] = useState("");
  const [allocations, setAllocations] = useState<AllocationDraft[]>([]);
  const [formError, setFormError] = useState("");

  // Fetch contacts
  const { data: contacts = [] } = useQuery<ContactItem[]>({
    queryKey: ["contacts"],
    queryFn: async () => {
      const res = await apiClient.get("/contacts");
      return res.data;
    },
  });

  const filteredContacts = contacts.filter((c) =>
    isReceipt
      ? c.contact_type === "CUSTOMER" || c.contact_type === "BOTH"
      : c.contact_type === "VENDOR" || c.contact_type === "BOTH"
  );

  // Fetch outstanding invoices/bills for allocation
  const { data: outstandingInvoices = [] } = useQuery<InvoiceItem[]>({
    queryKey: ["invoices-outstanding"],
    queryFn: async () => {
      const res = await apiClient.get("/invoices", {
        params: { status: "SENT,PARTIALLY_PAID" },
      });
      return Array.isArray(res.data) ? res.data : [];
    },
    enabled: isReceipt,
  });

  const { data: outstandingBills = [] } = useQuery<BillItem[]>({
    queryKey: ["bills-outstanding"],
    queryFn: async () => {
      const res = await apiClient.get("/bills", {
        params: { status: "UNPAID,PARTIALLY_PAID" },
      });
      return Array.isArray(res.data) ? res.data : [];
    },
    enabled: !isReceipt,
  });

  const addAllocation = () => {
    setAllocations([...allocations, isReceipt ? { invoice_id: "", amount: 0 } : { bill_id: "", amount: 0 }]);
  };

  const removeAllocation = (index: number) => {
    setAllocations(allocations.filter((_, i) => i !== index));
  };

  const updateAllocation = (index: number, field: keyof AllocationDraft, value: any) => {
    const updated = [...allocations];
    updated[index] = { ...updated[index], [field]: value };
    setAllocations(updated);
  };

  const formatCurrency = (val: number) =>
    new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(val);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        contact_id: contactId,
        payment_date: paymentDate,
        amount,
        payment_mode: paymentMode,
        reference_number: referenceNumber || undefined,
        description: description || undefined,
        allocations: allocations
          .filter((a) => a.amount > 0 && (a.invoice_id || a.bill_id))
          .map((a) => ({
            ...(isReceipt ? { invoice_id: a.invoice_id } : { bill_id: a.bill_id }),
            amount: a.amount,
          })),
      };

      const endpoint = isReceipt ? "/payments/receipts" : "/payments/disbursements";
      return apiClient.post(endpoint, payload);
    },
    onSuccess: () => {
      onSuccess();
    },
    onError: (err: any) => {
      setFormError(err.response?.data?.detail || "Failed to save payment. Please check API.");
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    if (!contactId) {
      setFormError(isReceipt ? "Customer is required." : "Vendor is required.");
      return;
    }
    if (!amount || amount <= 0) {
      setFormError("Amount must be greater than zero.");
      return;
    }

    saveMutation.mutate();
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={() => onNavigate("payments")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            {isReceipt ? "Record Customer Receipt" : "Record Vendor Payment"}
          </h1>
          <p className="text-sm text-slate-500 mt-0.5">
            {isReceipt ? "Register money received from a customer." : "Register payment made to a vendor."}
          </p>
        </div>
      </div>

      {formError && (
        <div className="flex items-start gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-sm">
            <span className="font-semibold">Error:</span> {formError}
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Core fields */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">
              {isReceipt ? "Customer" : "Vendor"}
            </label>
            <select
              value={contactId}
              onChange={(e) => setContactId(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            >
              <option value="">-- Select {isReceipt ? "Customer" : "Vendor"} --</option>
              {filteredContacts.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Payment Date</label>
            <input
              type="date"
              value={paymentDate}
              onChange={(e) => setPaymentDate(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Amount (₹)</label>
            <input
              type="number"
              min="0"
              step="0.01"
              value={amount}
              onChange={(e) => setAmount(parseFloat(e.target.value) || 0)}
              placeholder="0.00"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Payment Mode</label>
            <select
              value={paymentMode}
              onChange={(e) => setPaymentMode(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              {PAYMENT_MODES.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Reference Number</label>
            <input
              type="text"
              value={referenceNumber}
              onChange={(e) => setReferenceNumber(e.target.value)}
              placeholder="UTR / Cheque / Transaction ID"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>

          <div className="space-y-2 md:col-span-1">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Description</label>
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Optional payment note..."
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>
        </div>

        {/* Allocations */}
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
          <div className="bg-slate-50 border-b border-slate-100 px-6 py-3.5 flex justify-between items-center">
            <div>
              <span className="font-semibold text-sm text-slate-700">
                {isReceipt ? "Invoice Allocations" : "Bill Allocations"}
              </span>
              <span className="ml-2 text-xs text-slate-400">(optional)</span>
            </div>
            <button
              type="button"
              onClick={addAllocation}
              className="inline-flex items-center gap-1.5 text-xs font-semibold text-brand-600 hover:text-brand-700 transition"
            >
              <Plus className="w-4 h-4" /> Add Allocation
            </button>
          </div>

          <div className="p-6 space-y-3">
            {allocations.length === 0 && (
              <p className="text-sm text-slate-400 text-center py-4">
                No allocations added. Click "Add Allocation" to link to specific {isReceipt ? "invoices" : "bills"}.
              </p>
            )}
            {allocations.map((alloc, idx) => (
              <div key={idx} className="flex items-center gap-4">
                <div className="flex-1">
                  <select
                    value={isReceipt ? alloc.invoice_id : alloc.bill_id}
                    onChange={(e) =>
                      updateAllocation(idx, isReceipt ? "invoice_id" : "bill_id", e.target.value)
                    }
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
                  >
                    <option value="">-- Select {isReceipt ? "Invoice" : "Bill"} --</option>
                    {isReceipt
                      ? outstandingInvoices.map((inv) => (
                          <option key={inv.id} value={inv.id}>
                            {inv.invoice_number} — Outstanding: {formatCurrency(inv.total - inv.amount_paid)}
                          </option>
                        ))
                      : outstandingBills.map((bill) => (
                          <option key={bill.id} value={bill.id}>
                            {bill.bill_number} — Outstanding: {formatCurrency(bill.total - bill.amount_paid)}
                          </option>
                        ))}
                  </select>
                </div>
                <div className="w-36">
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={alloc.amount}
                    onChange={(e) => updateAllocation(idx, "amount", parseFloat(e.target.value) || 0)}
                    placeholder="Amount"
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>
                <button
                  type="button"
                  onClick={() => removeAllocation(idx)}
                  className="p-1.5 text-slate-400 hover:text-rose-600 rounded hover:bg-rose-50 transition"
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            ))}
          </div>
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-3">
          <button
            type="button"
            onClick={() => onNavigate("payments")}
            className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saveMutation.isPending}
            className="px-6 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50"
          >
            {saveMutation.isPending ? "Saving..." : isReceipt ? "Save Receipt" : "Save Payment"}
          </button>
        </div>
      </form>
    </div>
  );
}
