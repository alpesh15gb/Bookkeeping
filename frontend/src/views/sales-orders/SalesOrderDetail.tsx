import React from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, ShieldAlert, CheckCircle, XCircle, Truck } from "lucide-react";

interface SalesOrderDetailProps {
  soId: string;
  onNavigate: (view: "sales_orders" | "sales_order_create" | "sales_order_detail", id?: string) => void;
}

interface SalesOrderLine {
  id: string;
  product_name: string;
  hsn_sac: string;
  quantity: number;
  rate: number;
  discount: number;
  subtotal: number;
  gst_rate: number;
  cgst_amount: number;
  sgst_amount: number;
  igst_amount: number;
  total: number;
}

interface SalesOrderData {
  id: string;
  so_number: string;
  order_date: string;
  due_date: string;
  status: string;
  pos_state_code: string;
  subtotal: number;
  discount_total: number;
  cgst_amount: number;
  sgst_amount: number;
  igst_amount: number;
  total: number;
  amount_advanced: number;
  lines: SalesOrderLine[];
  contact: {
    name: string;
    email?: string;
    phone?: string;
    gstin?: string;
  };
}

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(amount);

const getStatusBadge = (status: string) => {
  const base = "px-3 py-1 text-sm font-semibold rounded-full inline-flex items-center gap-1.5 border";
  switch (status?.toUpperCase()) {
    case "DRAFT": return `${base} bg-slate-100 text-slate-700 border-slate-200`;
    case "CONFIRMED": return `${base} bg-blue-50 text-blue-700 border-blue-200`;
    case "DELIVERED": return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
    case "CANCELLED": return `${base} bg-rose-50 text-rose-700 border-rose-200`;
    default: return `${base} bg-slate-100 text-slate-600 border-slate-200`;
  }
};

export default function SalesOrderDetail({ soId, onNavigate }: SalesOrderDetailProps) {
  const queryClient = useQueryClient();

  const { data: so, isLoading, error } = useQuery<SalesOrderData>({
    queryKey: ["sales-order", soId],
    queryFn: async () => {
      const res = await apiClient.get(`/sales-orders/${soId}`);
      return res.data;
    },
  });

  const confirmMutation = useMutation({
    mutationFn: async () => apiClient.post(`/sales-orders/${soId}/confirm`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["sales-order", soId] }),
  });

  const deliverMutation = useMutation({
    mutationFn: async () => apiClient.post(`/sales-orders/${soId}/deliver`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["sales-order", soId] }),
  });

  const cancelMutation = useMutation({
    mutationFn: async () => apiClient.post(`/sales-orders/${soId}/cancel`),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["sales-order", soId] }),
  });

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (error || !so) {
    return (
      <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
        <ShieldAlert className="w-5 h-5 flex-shrink-0" />
        <span>Error loading sales order details.</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <button onClick={() => onNavigate("sales_orders")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">{so.so_number}</h1>
          <p className="text-sm text-slate-500 mt-0.5">
            Customer: <span className="font-semibold">{so.contact?.name}</span>
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className={getStatusBadge(so.status)}>{so.status}</span>
          
          {so.status === "DRAFT" && (
            <button
              onClick={() => confirmMutation.mutate()}
              disabled={confirmMutation.isPending}
              className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold text-sm rounded-lg shadow-sm transition disabled:opacity-50"
            >
              <CheckCircle className="w-4 h-4" />
              {confirmMutation.isPending ? "Confirming..." : "Confirm Order"}
            </button>
          )}

          {(so.status === "DRAFT" || so.status === "CONFIRMED") && (
            <button
              onClick={() => deliverMutation.mutate()}
              disabled={deliverMutation.isPending}
              className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold text-sm rounded-lg shadow-sm transition disabled:opacity-50"
            >
              <Truck className="w-4 h-4" />
              {deliverMutation.isPending ? "Delivering..." : "Mark as Delivered"}
            </button>
          )}

          {so.status !== "CANCELLED" && so.status !== "DELIVERED" && (
            <button
              onClick={() => {
                if (confirm("Are you sure you want to cancel this sales order?")) {
                  cancelMutation.mutate();
                }
              }}
              disabled={cancelMutation.isPending}
              className="flex items-center gap-2 px-4 py-2 border border-rose-200 text-rose-700 hover:bg-rose-50 font-semibold text-sm rounded-lg transition disabled:opacity-50"
            >
              <XCircle className="w-4 h-4" />
              {cancelMutation.isPending ? "Cancelling..." : "Cancel"}
            </button>
          )}
        </div>
      </div>

      {/* Details cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
        <div>
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Order Date</p>
          <p className="text-sm font-semibold text-slate-800">{new Date(so.order_date).toLocaleDateString("en-IN")}</p>
        </div>
        <div>
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Expected Delivery Date</p>
          <p className="text-sm font-semibold text-slate-800">{new Date(so.due_date).toLocaleDateString("en-IN")}</p>
        </div>
        <div>
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Place of Supply</p>
          <p className="text-sm font-semibold text-slate-800">State Code: {so.pos_state_code}</p>
        </div>
        <div>
          <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-1">Total Amount</p>
          <p className="text-sm font-bold text-brand-900">{formatCurrency(so.total)}</p>
        </div>
      </div>

      {/* Line Items Table */}
      <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
        <div className="bg-slate-50 border-b border-slate-100 px-6 py-3.5">
          <span className="font-semibold text-sm text-slate-700">Line Items</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-left text-sm">
            <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
              <tr>
                <th className="px-6 py-3.5">Item</th>
                <th className="px-6 py-3.5">HSN/SAC</th>
                <th className="px-6 py-3.5 text-right">Qty</th>
                <th className="px-6 py-3.5 text-right">Rate</th>
                <th className="px-6 py-3.5 text-right">Subtotal</th>
                <th className="px-6 py-3.5 text-right">GST</th>
                <th className="px-6 py-3.5 text-right">Total</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {(so.lines || []).map((line) => (
                <tr key={line.id} className="hover:bg-slate-50/50 transition">
                  <td className="px-6 py-4 font-semibold text-slate-800">{line.product_name}</td>
                  <td className="px-6 py-4 font-mono text-slate-500">{line.hsn_sac}</td>
                  <td className="px-6 py-4 text-right text-slate-600">{line.quantity}</td>
                  <td className="px-6 py-4 text-right text-slate-600">{formatCurrency(line.rate)}</td>
                  <td className="px-6 py-4 text-right text-slate-600">{formatCurrency(line.subtotal)}</td>
                  <td className="px-6 py-4 text-right text-slate-500 text-xs">
                    {line.gst_rate}%
                    {line.cgst_amount > 0 && <div>C: {formatCurrency(line.cgst_amount)}</div>}
                    {line.igst_amount > 0 && <div>I: {formatCurrency(line.igst_amount)}</div>}
                  </td>
                  <td className="px-6 py-4 text-right font-bold text-slate-800">{formatCurrency(line.total)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Totals footer */}
        <div className="border-t border-slate-100 p-6 flex justify-end">
          <div className="w-64 space-y-2">
            <div className="flex justify-between text-sm text-slate-600">
              <span>Subtotal</span><span>{formatCurrency(so.subtotal)}</span>
            </div>
            {so.discount_total > 0 && (
              <div className="flex justify-between text-sm text-rose-600">
                <span>Discount</span><span>-{formatCurrency(so.discount_total)}</span>
              </div>
            )}
            {so.cgst_amount > 0 && (
              <div className="flex justify-between text-xs text-slate-500">
                <span>CGST</span><span>{formatCurrency(so.cgst_amount)}</span>
              </div>
            )}
            {so.sgst_amount > 0 && (
              <div className="flex justify-between text-xs text-slate-500">
                <span>SGST</span><span>{formatCurrency(so.sgst_amount)}</span>
              </div>
            )}
            {so.igst_amount > 0 && (
              <div className="flex justify-between text-xs text-slate-500">
                <span>IGST</span><span>{formatCurrency(so.igst_amount)}</span>
              </div>
            )}
            <div className="flex justify-between text-base font-bold text-slate-900 pt-2 border-t border-slate-100">
              <span>Grand Total</span><span className="text-brand-900">{formatCurrency(so.total)}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
