import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, FileText, Eye, Edit, ShieldAlert } from "lucide-react";

interface InvoiceListProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail", invoiceId?: string) => void;
}

interface InvoiceListItem {
  id: string;
  invoice_number: string;
  issue_date: string;
  due_date: string;
  status: string;
  total: number;
  amount_paid: number;
  contact_name: string;
  created_at: string;
}

export default function InvoiceList({ onNavigate }: InvoiceListProps) {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("ALL");

  // Fetch Invoices using TanStack Query
  const { data: invoices = [], isLoading, error, refetch } = useQuery<InvoiceListItem[]>({
    queryKey: ["invoices"],
    queryFn: async () => {
      // Send tenant header dummy as set in standard client
      const res = await apiClient.get("/invoices");
      return res.data;
    },
  });

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 2,
    }).format(amount);
  };

  const getStatusBadge = (status: string) => {
    const s = status.toUpperCase();
    if (s === "DRAFT") return <span className="badge badge-draft">Draft</span>;
    if (s === "SENT" || s === "UNPAID") return <span className="badge badge-sent">Sent</span>;
    if (s === "PARTIALLY_PAID") return <span className="badge badge-partially_paid">Partially Paid</span>;
    if (s === "PAID") return <span className="badge badge-paid">Paid</span>;
    if (s === "CANCELLED") return <span className="badge badge-cancelled">Cancelled</span>;
    return <span className="badge badge-draft">{status}</span>;
  };

  // Filter list locally for fast interactivity
  const filteredInvoices = invoices.filter((inv) => {
    const matchesSearch =
      inv.invoice_number.toLowerCase().includes(search.toLowerCase()) ||
      inv.contact_name.toLowerCase().includes(search.toLowerCase());
    const matchesStatus = statusFilter === "ALL" || inv.status.toUpperCase() === statusFilter;
    return matchesSearch && matchesStatus;
  });

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 pb-4 border-b border-zinc-200/60">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Invoices</h1>
          <p className="text-xs text-zinc-500 mt-1">Manage client bills, GST rates splits, and payment collections.</p>
        </div>
        <button
          onClick={() => onNavigate("create")}
          className="btn-primary"
        >
          <Plus className="w-4 h-4" />
          Create Invoice
        </button>
      </div>

      {/* Filter Toolbar */}
      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-lg shadow-sm border border-zinc-200/80">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4.5 w-4.5 text-zinc-400" />
          <input
            type="text"
            placeholder="Search by invoice number or customer name..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="form-input pl-10 pr-4"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="form-select sm:w-48"
        >
          <option value="ALL">All Statuses</option>
          <option value="DRAFT">Draft</option>
          <option value="SENT">Sent / Unpaid</option>
          <option value="PARTIALLY_PAID">Partially Paid</option>
          <option value="PAID">Paid</option>
          <option value="CANCELLED">Cancelled</option>
        </select>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-zinc-800"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span className="text-xs font-semibold">Error loading invoices. Please check API server.</span>
        </div>
      ) : filteredInvoices.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-lg border border-zinc-200/80 shadow-sm">
          <FileText className="w-12 h-12 text-zinc-300 mx-auto mb-3" />
          <h3 className="text-xs font-semibold text-zinc-700 uppercase tracking-wider">No Invoices Found</h3>
          <p className="text-xs text-zinc-400 mt-1">Try resetting filters or create a new invoice to get started.</p>
        </div>
      ) : (
        <div className="bg-white rounded-lg shadow-sm border border-zinc-200/80 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="financial-table">
              <thead>
                <tr>
                  <th>Invoice #</th>
                  <th>Customer</th>
                  <th>Date</th>
                  <th>Due Date</th>
                  <th className="text-right">Total</th>
                  <th className="text-right">Paid</th>
                  <th>Status</th>
                  <th className="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredInvoices.map((inv) => (
                  <tr key={inv.id}>
                    <td className="font-mono font-medium text-zinc-900">{inv.invoice_number}</td>
                    <td className="font-semibold text-zinc-800">{inv.contact_name}</td>
                    <td className="text-zinc-500 text-xs">{new Date(inv.issue_date).toLocaleDateString("en-IN")}</td>
                    <td className="text-zinc-500 text-xs">{new Date(inv.due_date).toLocaleDateString("en-IN")}</td>
                    <td className="numeric-val font-semibold">{formatCurrency(inv.total)}</td>
                    <td className="numeric-val text-zinc-500">{formatCurrency(inv.amount_paid)}</td>
                    <td>{getStatusBadge(inv.status)}</td>
                    <td className="text-right">
                      <div className="inline-flex items-center gap-2 justify-end">
                        <button
                          onClick={() => onNavigate("detail", inv.id)}
                          title="View Details"
                          className="p-1 text-zinc-400 hover:text-zinc-800 hover:bg-zinc-100 rounded transition"
                        >
                          <Eye className="w-3.5 h-3.5" />
                        </button>
                        {inv.status.toUpperCase() === "DRAFT" && (
                          <button
                            onClick={() => onNavigate("edit", inv.id)}
                            title="Edit Draft"
                            className="p-1 text-zinc-400 hover:text-amber-700 hover:bg-amber-50 rounded transition"
                          >
                            <Edit className="w-3.5 h-3.5" />
                          </button>
                        )}
                      </div>
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
