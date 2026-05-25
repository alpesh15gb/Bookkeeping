import React from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, ShieldAlert, CheckCircle, XCircle } from "lucide-react";

interface PaymentDetailProps {
  paymentId: string;
  mode: "receipt" | "disbursement";
  onNavigate: (view: "payments") => void;
}

interface AllocationItem {
  id: string;
  invoice_id?: string;
  bill_id?: string;
  amount: number;
}

interface PaymentData {
  id: string;
  payment_number: string;
  payment_date: string;
  payment_mode: string;
  amount: number;
  reference_number?: string;
  description?: string;
  status: string;
  contact_id: string;
  allocations: AllocationItem[];
}

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(amount);

const getStatusBadge = (status: string) => {
  const base = "px-3 py-1 text-sm font-semibold rounded-full inline-flex items-center gap-1.5 border";
  switch (status?.toUpperCase()) {
    case "ACTIVE": return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    case "CANCELLED": return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    default: return `${base} bg-slate-100 text-slate-600 border-slate-200`;
  }
};

export default function PaymentDetail({ paymentId, mode, onNavigate }: PaymentDetailProps) {
  const queryClient = useQueryClient();
  const isReceipt = mode === "receipt";

  const { data: payment, isLoading, error } = useQuery<PaymentData>({
    queryKey: ["payment", mode, paymentId],
    queryFn: async () => {
      const endpoint = isReceipt ? `/payments/receipts/${paymentId}` : `/payments/disbursements/${paymentId}`;
      const res = await apiClient.get(endpoint);
      return res.data;
    },
  });

  const cancelMutation = useMutation({
    mutationFn: async () => {
      const endpoint = isReceipt ? `/payments/receipts/${paymentId}/cancel` : `/payments/disbursements/${paymentId}/cancel`;
      return apiClient.post(endpoint, {});
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["payment", mode, paymentId] });
      queryClient.invalidateQueries({ queryKey: ["payments-receipts"] });
      queryClient.invalidateQueries({ queryKey: ["payments-disbursements"] });
    },
  });

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (error || !payment) {
    return (
      <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
        <ShieldAlert className="w-5 h-5 flex-shrink-0" />
        <span>Error loading payment details.</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <button onClick={() => onNavigate("payments")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">{payment.payment_number}</h1>
          <p className="text-sm text-slate-500 mt-0.5">
            Date: {new Date(payment.payment_date).toLocaleDateString("en-IN")}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className={getStatusBadge(payment.status)}>{payment.status}</span>
          {payment.status !== "CANCELLED" && (
            <button
              onClick={() => {
                if (confirm(`Are you sure you want to cancel this ${isReceipt ? "receipt" : "payment"}? This will reverse ledger entries and document allocations.`)) {
                  cancelMutation.mutate();
                }
              }}
              disabled={cancelMutation.isPending}
              className="flex items-center gap-2 px-4 py-2 border border-rose-200 text-rose-700 hover:bg-rose-50 font-semibold text-sm rounded-lg transition disabled:opacity-50"
            >
              <XCircle className="w-4 h-4" />
              {cancelMutation.isPending ? "Cancelling..." : "Cancel Payment"}
            </button>
          )}
        </div>
      </div>

      {/* Details Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
        <div>
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Amount</p>
          <p className="text-xl font-bold text-slate-800">{formatCurrency(payment.amount)}</p>
        </div>
        <div>
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Payment Mode</p>
          <p className="text-sm font-semibold text-slate-800">{payment.payment_mode}</p>
        </div>
        <div>
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Reference Number</p>
          <p className="text-sm font-semibold text-slate-800">{payment.reference_number || "—"}</p>
        </div>
        {payment.description && (
          <div className="md:col-span-3 border-t border-slate-100 pt-4 mt-2">
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Description</p>
            <p className="text-sm text-slate-700">{payment.description}</p>
          </div>
        )}
      </div>

      {/* Allocations Table */}
      <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
        <div className="bg-slate-50 border-b border-slate-100 px-6 py-3.5">
          <span className="font-semibold text-sm text-slate-700">Document Allocations</span>
        </div>
        {payment.allocations.length === 0 ? (
          <div className="p-6 text-center text-sm text-slate-400">
            No document allocations recorded. This was registered as an unallocated advance payment.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">{isReceipt ? "Invoice ID" : "Bill ID"}</th>
                  <th className="px-6 py-3.5 text-right">Allocated Amount</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {payment.allocations.map((alloc) => (
                  <tr key={alloc.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono text-xs text-brand-700">
                      {isReceipt ? alloc.invoice_id : alloc.bill_id}
                    </td>
                    <td className="px-6 py-4 text-right font-bold text-slate-800">
                      {formatCurrency(alloc.amount)}
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
