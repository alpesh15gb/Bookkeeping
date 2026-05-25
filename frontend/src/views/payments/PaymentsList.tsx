import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Eye, ShieldAlert, Banknote, ArrowDownCircle, ArrowUpCircle } from "lucide-react";

interface PaymentsListProps {
  onNavigate: (view: "payments" | "payment_receipt" | "payment_disbursement", id?: string) => void;
}

interface ReceiptItem {
  id: string;
  receipt_number: string;
  payment_date: string;
  contact_name: string;
  payment_mode: string;
  amount: number;
  status: string;
}

interface DisbursementItem {
  id: string;
  payment_number: string;
  payment_date: string;
  contact_name: string;
  payment_mode: string;
  amount: number;
  status: string;
}

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(amount);

const getStatusBadge = (status: string) => {
  const base = "px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center border";
  switch (status?.toUpperCase()) {
    case "CLEARED": return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    case "PENDING": return `${base} bg-amber-50 text-amber-700 border-amber-200`;
    case "BOUNCED": return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    case "CANCELLED": return `${base} bg-slate-100 text-slate-600 border-slate-200`;
    default: return `${base} bg-slate-100 text-slate-600 border-slate-200`;
  }
};

const getModeBadge = (mode: string) => {
  const colors: Record<string, string> = {
    CASH: "bg-green-50 text-green-700 border-green-200",
    BANK: "bg-blue-50 text-blue-700 border-blue-200",
    UPI: "bg-purple-50 text-purple-700 border-purple-200",
    POS: "bg-indigo-50 text-indigo-700 border-indigo-200",
    OTHER: "bg-slate-100 text-slate-600 border-slate-200",
  };
  return `px-2 py-0.5 text-xs font-semibold rounded border ${colors[mode?.toUpperCase()] || colors.OTHER}`;
};

export default function PaymentsList({ onNavigate }: PaymentsListProps) {
  const [activeTab, setActiveTab] = useState<"receipts" | "disbursements">("receipts");

  const { data: receipts = [], isLoading: receiptsLoading, error: receiptsError } = useQuery<ReceiptItem[]>({
    queryKey: ["payments-receipts"],
    queryFn: async () => {
      const res = await apiClient.get("/payments/receipts");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const { data: disbursements = [], isLoading: disbursementsLoading, error: disbursementsError } = useQuery<DisbursementItem[]>({
    queryKey: ["payments-disbursements"],
    queryFn: async () => {
      const res = await apiClient.get("/payments/disbursements");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const isLoading = activeTab === "receipts" ? receiptsLoading : disbursementsLoading;
  const error = activeTab === "receipts" ? receiptsError : disbursementsError;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Payments</h1>
          <p className="text-sm text-slate-500">Track customer receipts and vendor payment disbursements.</p>
        </div>
        <button
          onClick={() => onNavigate(activeTab === "receipts" ? "payment_receipt" : "payment_disbursement")}
          className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold transition"
        >
          <Plus className="w-4 h-4" />
          {activeTab === "receipts" ? "New Receipt" : "New Payment"}
        </button>
      </div>

      {/* Tabs */}
      <div className="bg-white rounded-xl shadow-sm border border-slate-100">
        <div className="flex border-b border-slate-100">
          <button
            onClick={() => setActiveTab("receipts")}
            className={`flex items-center gap-2 px-6 py-4 text-sm font-semibold transition border-b-2 -mb-px ${
              activeTab === "receipts"
                ? "border-brand-500 text-brand-700"
                : "border-transparent text-slate-500 hover:text-slate-800"
            }`}
          >
            <ArrowDownCircle className="w-4 h-4" />
            Customer Receipts
            <span className="ml-1 px-2 py-0.5 text-xs bg-emerald-100 text-emerald-700 rounded-full">
              {receipts.length}
            </span>
          </button>
          <button
            onClick={() => setActiveTab("disbursements")}
            className={`flex items-center gap-2 px-6 py-4 text-sm font-semibold transition border-b-2 -mb-px ${
              activeTab === "disbursements"
                ? "border-brand-500 text-brand-700"
                : "border-transparent text-slate-500 hover:text-slate-800"
            }`}
          >
            <ArrowUpCircle className="w-4 h-4" />
            Vendor Payments
            <span className="ml-1 px-2 py-0.5 text-xs bg-amber-100 text-amber-700 rounded-full">
              {disbursements.length}
            </span>
          </button>
        </div>

        {isLoading ? (
          <div className="flex justify-center items-center py-20">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
          </div>
        ) : error ? (
          <div className="flex items-center gap-3 m-6 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
            <ShieldAlert className="w-5 h-5 flex-shrink-0" />
            <span>Error loading payments data. Check API server.</span>
          </div>
        ) : activeTab === "receipts" ? (
          receipts.length === 0 ? (
            <div className="text-center py-16">
              <Banknote className="w-12 h-12 text-slate-300 mx-auto mb-3" />
              <h3 className="text-sm font-semibold text-slate-700">No Customer Receipts</h3>
              <p className="text-xs text-slate-500 mt-1">Record a receipt to track customer payments.</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-left text-sm">
                <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                  <tr>
                    <th className="px-6 py-3.5">Receipt #</th>
                    <th className="px-6 py-3.5">Date</th>
                    <th className="px-6 py-3.5">Customer</th>
                    <th className="px-6 py-3.5">Mode</th>
                    <th className="px-6 py-3.5">Amount</th>
                    <th className="px-6 py-3.5">Status</th>
                    <th className="px-6 py-3.5 text-right">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {receipts.map((r) => (
                    <tr key={r.id} className="hover:bg-slate-50/50 transition">
                      <td className="px-6 py-4 font-mono font-medium text-brand-900">{r.receipt_number}</td>
                      <td className="px-6 py-4 text-slate-500">
                        {new Date(r.payment_date).toLocaleDateString("en-IN")}
                      </td>
                      <td className="px-6 py-4 font-semibold text-slate-800">{r.contact_name}</td>
                      <td className="px-6 py-4">
                        <span className={getModeBadge(r.payment_mode)}>{r.payment_mode}</span>
                      </td>
                      <td className="px-6 py-4 font-semibold text-emerald-700">{formatCurrency(r.amount)}</td>
                      <td className="px-6 py-4">
                        <span className={getStatusBadge(r.status)}>{r.status}</span>
                      </td>
                      <td className="px-6 py-4 text-right">
                        <button
                          onClick={() => onNavigate("payment_receipt", r.id)}
                          title="View Receipt"
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
          )
        ) : disbursements.length === 0 ? (
          <div className="text-center py-16">
            <Banknote className="w-12 h-12 text-slate-300 mx-auto mb-3" />
            <h3 className="text-sm font-semibold text-slate-700">No Vendor Payments</h3>
            <p className="text-xs text-slate-500 mt-1">Record a payment to track vendor disbursements.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">Payment #</th>
                  <th className="px-6 py-3.5">Date</th>
                  <th className="px-6 py-3.5">Vendor</th>
                  <th className="px-6 py-3.5">Mode</th>
                  <th className="px-6 py-3.5">Amount</th>
                  <th className="px-6 py-3.5">Status</th>
                  <th className="px-6 py-3.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {disbursements.map((d) => (
                  <tr key={d.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-medium text-brand-900">{d.payment_number}</td>
                    <td className="px-6 py-4 text-slate-500">
                      {new Date(d.payment_date).toLocaleDateString("en-IN")}
                    </td>
                    <td className="px-6 py-4 font-semibold text-slate-800">{d.contact_name}</td>
                    <td className="px-6 py-4">
                      <span className={getModeBadge(d.payment_mode)}>{d.payment_mode}</span>
                    </td>
                    <td className="px-6 py-4 font-semibold text-amber-700">{formatCurrency(d.amount)}</td>
                    <td className="px-6 py-4">
                      <span className={getStatusBadge(d.status)}>{d.status}</span>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <button
                        onClick={() => onNavigate("payment_disbursement", d.id)}
                        title="View Payment"
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
        )}
      </div>
    </div>
  );
}
