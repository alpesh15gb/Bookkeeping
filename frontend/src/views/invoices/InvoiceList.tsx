import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, FileText, Eye, Edit, ShieldAlert, SlidersHorizontal, ChevronDown } from "lucide-react";

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
  const [currentPage, setCurrentPage] = useState(1);
  const itemsPerPage = 8;

  // Fetch Invoices with server-side pagination
  const { data: invoicesResponse, isLoading, error } = useQuery<
    { items: InvoiceListItem[]; total: number; page: number; limit: number }
  >({
    queryKey: ["invoices", currentPage, search, statusFilter],
    queryFn: async () => {
      const res = await apiClient.get("/invoices", {
        params: {
          page: currentPage,
          limit: itemsPerPage,
          search: search || undefined,
          status: statusFilter !== "ALL" ? statusFilter : undefined,
        }
      });
      return res.data;
    },
  });

  const invoices = invoicesResponse?.items || [];
  const totalItems = invoicesResponse?.total || 0;
  const totalPages = Math.max(1, Math.ceil(totalItems / itemsPerPage));
  const startIndex = (currentPage - 1) * itemsPerPage;

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 0,
    }).format(amount);
  };

  const getStatusBadge = (status: string) => {
    const s = status.toUpperCase();
    if (s === "PAID") {
      return (
        <span className="inline-flex items-center px-2.5 py-0.5 rounded text-xs font-semibold bg-emerald-50 border border-emerald-200 text-emerald-700">
          Paid
        </span>
      );
    }
    if (s === "CANCELLED") {
      return (
        <span className="inline-flex items-center px-2.5 py-0.5 rounded text-xs font-semibold bg-rose-50 border border-rose-200 text-rose-700">
          Cancelled
        </span>
      );
    }
    // Draft, Sent, Unpaid, Partially Paid maps to Unpaid badge
    return (
      <span className="inline-flex items-center px-2.5 py-0.5 rounded text-xs font-semibold bg-amber-50 border border-amber-200 text-amber-700">
        Unpaid
      </span>
    );
  };

  const handlePageChange = (page: number) => {
    if (page >= 1 && page <= totalPages) {
      setCurrentPage(page);
    }
  };

  return (
    <div className="space-y-5">
      {/* Title Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 pb-2">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Invoices</h1>
          <p className="text-sm text-zinc-500 mt-0.5">Manage sales invoices and GST compliance.</p>
        </div>
        <button
          onClick={() => onNavigate("create")}
          className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition"
        >
          <Plus className="w-4 h-4" />
          Create Invoice
        </button>
      </div>

      {/* Filter Toolbar */}
      <div className="flex flex-col md:flex-row gap-3 items-center justify-between">
        {/* Search */}
        <div className="relative w-full md:max-w-xs">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            placeholder="Search invoices by number or customer..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setCurrentPage(1);
            }}
            className="w-full pl-9 pr-4 py-2 border border-zinc-200 rounded-lg text-xs focus:outline-none focus:ring-2 focus:ring-brand-500 placeholder-zinc-400"
          />
        </div>

        {/* Filter Pills */}
        <div className="flex flex-wrap items-center gap-2 w-full md:w-auto">
          <button
            onClick={() => { setStatusFilter("ALL"); setCurrentPage(1); }}
            className={`px-4.5 py-1.5 rounded-lg text-xs font-semibold border transition ${
              statusFilter === "ALL"
                ? "bg-brand-900 border-brand-900 text-white shadow-sm"
                : "bg-white border-zinc-200 text-zinc-600 hover:bg-zinc-50"
            }`}
          >
            All
          </button>
          <button
            onClick={() => { setStatusFilter("PAID"); setCurrentPage(1); }}
            className={`px-4.5 py-1.5 rounded-lg text-xs font-semibold border transition ${
              statusFilter === "PAID"
                ? "bg-green-50/50 border-green-500 text-green-700 shadow-sm"
                : "bg-white border-zinc-200 text-zinc-600 hover:bg-zinc-50"
            }`}
          >
            Paid
          </button>
          <button
            onClick={() => { setStatusFilter("UNPAID"); setCurrentPage(1); }}
            className={`px-4.5 py-1.5 rounded-lg text-xs font-semibold border transition ${
              statusFilter === "UNPAID"
                ? "bg-amber-50/50 border-amber-500 text-amber-700 shadow-sm"
                : "bg-white border-zinc-200 text-zinc-600 hover:bg-zinc-50"
            }`}
          >
            Unpaid
          </button>
          <button
            onClick={() => { setStatusFilter("CANCELLED"); setCurrentPage(1); }}
            className={`px-4.5 py-1.5 rounded-lg text-xs font-semibold border transition ${
              statusFilter === "CANCELLED"
                ? "bg-red-50/50 border-red-500 text-red-700 shadow-sm"
                : "bg-white border-zinc-200 text-zinc-600 hover:bg-zinc-50"
            }`}
          >
            Cancelled
          </button>
        </div>

        {/* Filters dropdown button */}
        <button className="hidden md:inline-flex items-center gap-1 px-3 py-2 bg-white hover:bg-zinc-50 text-zinc-700 border border-zinc-200 rounded-lg text-xs font-semibold shadow-sm transition">
          <SlidersHorizontal className="w-3.5 h-3.5 text-zinc-500" /> Filters <ChevronDown className="w-3 h-3 text-zinc-400" />
        </button>
      </div>

      {/* Table content */}
      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span className="text-xs font-semibold">Error loading invoices. Please check API server.</span>
        </div>
      ) : invoices.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-zinc-200 shadow-sm">
          <FileText className="w-12 h-12 text-zinc-300 mx-auto mb-3" />
          <h3 className="text-xs font-semibold text-zinc-700 uppercase tracking-wider">No Invoices Found</h3>
          <p className="text-xs text-zinc-400 mt-1">Try resetting filters or create a new invoice to get started.</p>
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-zinc-200 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs border-collapse">
              <thead>
                <tr className="bg-zinc-50 text-zinc-500 border-b border-zinc-100 font-semibold">
                  <th className="px-4 py-3 font-semibold uppercase tracking-wider">Invoice #</th>
                  <th className="px-4 py-3 font-semibold uppercase tracking-wider">Customer Name</th>
                  <th className="px-4 py-3 font-semibold uppercase tracking-wider">Date</th>
                  <th className="px-4 py-3 font-semibold uppercase tracking-wider text-right">Amount</th>
                  <th className="px-4 py-3 font-semibold uppercase tracking-wider text-right">Paid</th>
                  <th className="px-4 py-3 font-semibold uppercase tracking-wider text-right font-mono">Total</th>
                  <th className="px-4 py-3 font-semibold uppercase tracking-wider text-center">Status</th>
                  <th className="px-4 py-3 font-semibold uppercase tracking-wider text-center">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-100">
                {invoices.map((inv) => (
                  <tr key={inv.id} className="hover:bg-zinc-50/40 transition">
                    <td className="px-4 py-3.5 font-mono font-medium text-zinc-900">{inv.invoice_number}</td>
                    <td className="px-4 py-3.5 font-bold text-zinc-850">{inv.contact_name}</td>
                    <td className="px-4 py-3.5 text-zinc-500 font-medium">
                      {new Date(inv.issue_date).toLocaleDateString("en-IN", {
                        day: "2-digit",
                        month: "short",
                        year: "numeric"
                      })}
                    </td>
                    <td className="px-4 py-3.5 text-right font-mono font-medium text-zinc-600">
                      {formatCurrency(inv.total - inv.amount_paid)}
                    </td>
                    <td className="px-4 py-3.5 text-right font-mono font-medium text-green-600">
                      {formatCurrency(inv.amount_paid)}
                    </td>
                    <td className="px-4 py-3.5 text-right font-mono font-bold text-zinc-900">
                      {formatCurrency(inv.total)}
                    </td>
                    <td className="px-4 py-3.5 text-center">{getStatusBadge(inv.status)}</td>
                    <td className="px-4 py-3.5 text-center">
                      <div className="inline-flex items-center gap-2 justify-center">
                        <button
                          onClick={() => onNavigate("detail", inv.id)}
                          className="border border-blue-200 bg-blue-50/20 hover:bg-blue-50 text-blue-600 px-2.5 py-1 rounded text-[11px] font-semibold inline-flex items-center gap-1 transition shadow-sm"
                        >
                          <Eye className="w-3.5 h-3.5" /> View
                        </button>
                        <button
                          onClick={() => onNavigate("edit", inv.id)}
                          className="border border-zinc-200 bg-white hover:bg-zinc-50 text-zinc-600 px-2.5 py-1 rounded text-[11px] font-semibold inline-flex items-center gap-1 transition shadow-sm"
                        >
                          <Edit className="w-3.5 h-3.5" /> Edit
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination bar */}
          <div className="px-6 py-4 border-t border-zinc-100 flex items-center justify-between">
            <span className="text-xs text-zinc-500 font-medium">
              Showing {totalItems > 0 ? startIndex + 1 : 0} to {Math.min(startIndex + itemsPerPage, totalItems)} of {totalItems} invoices
            </span>
            <div className="inline-flex items-center gap-1">
              <button
                onClick={() => handlePageChange(currentPage - 1)}
                disabled={currentPage === 1}
                className="px-2.5 py-1.5 border border-zinc-200 bg-white text-zinc-500 rounded-lg text-xs font-semibold hover:bg-zinc-50 disabled:opacity-40 transition"
              >
                &lt; Previous
              </button>
              <span className="px-3 py-1.5 text-xs font-bold text-zinc-700">
                Page {currentPage} of {totalPages}
              </span>
              <button
                onClick={() => handlePageChange(currentPage + 1)}
                disabled={currentPage === totalPages}
                className="px-2.5 py-1.5 border border-zinc-200 bg-white text-zinc-500 rounded-lg text-xs font-semibold hover:bg-zinc-50 disabled:opacity-40 transition"
              >
                Next &gt;
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
