import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Search, Eye, AlertCircle, FileSpreadsheet } from "lucide-react";

interface SalesTransactionsListProps {
  onNavigateToInvoice: (invoiceId: string) => void;
}

interface SalesTransaction {
  id: string;
  invoice_number: string;
  issue_date: string;
  customer_name: string;
  subtotal: number;
  tax_total: number;
  total: number;
  amount_paid: number;
  status: string;
}

export default function SalesTransactionsList({ onNavigateToInvoice }: SalesTransactionsListProps) {
  const [search, setSearch] = useState("");

  // Fetch Sales Transactions (excludes Drafts)
  const { data: transactions = [], isLoading, error } = useQuery<SalesTransaction[]>({
    queryKey: ["sales-transactions"],
    queryFn: async () => {
      const res = await apiClient.get("/sales/transactions");
      return res.data;
    }
  });

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
    }).format(val);
  };

  const getStatusBadge = (status: string) => {
    const base = "px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center gap-1 border";
    switch (status.toUpperCase()) {
      case "SENT":
      case "UNPAID":
        return `${base} bg-amber-50 text-amber-700 border-amber-200`;
      case "PARTIALLY_PAID":
        return `${base} bg-indigo-50 text-indigo-700 border-indigo-200`;
      case "PAID":
        return `${base} bg-emerald-50 text-emerald-700 border-emerald-200`;
      default:
        return `${base} bg-slate-50 text-slate-700 border-slate-200`;
    }
  };

  const filteredTransactions = transactions.filter(t => 
    t.invoice_number.toLowerCase().includes(search.toLowerCase()) ||
    t.customer_name.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">Sales Transactions Register</h1>
        <p className="text-sm text-slate-500">Audit sales transactions history and payment settlements.</p>
      </div>

      {/* Filter and search toolbar */}
      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4.5 w-4.5 text-slate-400" />
          <input
            type="text"
            placeholder="Search transactions by invoice # or customer..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm"
          />
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0" />
          <span>Error loading transaction registry from API.</span>
        </div>
      ) : filteredTransactions.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <FileSpreadsheet className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Transactions Found</h3>
          <p className="text-xs text-slate-500 mt-1">Finalize draft invoices to record actual sales entries.</p>
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">Invoice #</th>
                  <th className="px-6 py-3.5">Customer Name</th>
                  <th className="px-6 py-3.5">Date</th>
                  <th className="px-6 py-3.5 text-right">Taxable Amount</th>
                  <th className="px-6 py-3.5 text-right">GST Tax</th>
                  <th className="px-6 py-3.5 text-right">Total Invoice</th>
                  <th className="px-6 py-3.5 text-right">Settled Amount</th>
                  <th className="px-6 py-3.5">Status</th>
                  <th className="px-6 py-3.5 text-right">Link</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredTransactions.map((t) => (
                  <tr key={t.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-medium text-brand-900">{t.invoice_number}</td>
                    <td className="px-6 py-4 font-semibold text-slate-800">{t.customer_name}</td>
                    <td className="px-6 py-4 text-slate-500">{new Date(t.issue_date).toLocaleDateString("en-IN")}</td>
                    <td className="px-6 py-4 text-right text-slate-700 font-mono">{formatCurrency(t.subtotal)}</td>
                    <td className="px-6 py-4 text-right text-slate-600 font-mono">{formatCurrency(t.tax_total)}</td>
                    <td className="px-6 py-4 text-right font-bold text-slate-800 font-mono">{formatCurrency(t.total)}</td>
                    <td className="px-6 py-4 text-right text-slate-500 font-mono">{formatCurrency(t.amount_paid)}</td>
                    <td className="px-6 py-4">{getStatusBadge(t.status)}</td>
                    <td className="px-6 py-4 text-right">
                      <button
                        onClick={() => onNavigateToInvoice(t.id)}
                        title="View Original Invoice"
                        className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition inline-flex items-center gap-1.5 text-xs font-semibold"
                      >
                        <Eye className="w-4 h-4" /> View Invoice
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
