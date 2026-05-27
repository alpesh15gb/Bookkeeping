import React, { useState, useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, Receipt, ShieldAlert, Eye } from "lucide-react";
import Pagination from "../../components/Pagination";

interface ExpenseListProps {
  onNavigate: (view: "expense_list" | "expense_create" | "expense_edit" | "expense_detail", expenseId?: string) => void;
}

interface ExpenseListItem {
  id: string;
  expense_number: string;
  expense_date: string;
  vendor_name: string | null;
  description: string | null;
  amount: number;
  total: number;
  status: string;
  category_name: string | null;
  created_at: string;
}

export default function ExpenseList({ onNavigate }: ExpenseListProps) {
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const itemsPerPage = 20;

  const { data: expenses = [], isLoading, error } = useQuery<ExpenseListItem[]>({
    queryKey: ["expenses"],
    queryFn: async () => {
      const res = await apiClient.get("/expenses");
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

  const filteredExpenses = expenses.filter((e) => {
    const q = search.toLowerCase();
    return (
      e.expense_number.toLowerCase().includes(q) ||
      (e.vendor_name || "").toLowerCase().includes(q) ||
      (e.description || "").toLowerCase().includes(q) ||
      (e.category_name || "").toLowerCase().includes(q)
    );
  });

  const totalPages = Math.ceil(filteredExpenses.length / itemsPerPage);
  const paginatedExpenses = filteredExpenses.slice((page - 1) * itemsPerPage, page * itemsPerPage);

  useEffect(() => setPage(1), [search]);

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Expenses</h1>
          <p className="text-sm text-slate-500">Manage business expenses and post to ledger.</p>
        </div>
        <button
          onClick={() => onNavigate("expense_create")}
          className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold transition"
        >
          <Plus className="w-4 h-4" />
          Add Expense
        </button>
      </div>

      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4.5 w-4.5 text-slate-400" />
          <input
            type="text"
            placeholder="Search by number, vendor, description or category..."
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
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span>Error loading expenses. Please check API server.</span>
        </div>
      ) : filteredExpenses.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <Receipt className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Expenses Found</h3>
          <p className="text-xs text-slate-500 mt-1">Create a new expense to get started.</p>
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">Expense #</th>
                  <th className="px-6 py-3.5">Date</th>
                  <th className="px-6 py-3.5">Category</th>
                  <th className="px-6 py-3.5">Vendor</th>
                  <th className="px-6 py-3.5">Description</th>
                  <th className="px-6 py-3.5 text-right">Amount</th>
                  <th className="px-6 py-3.5">Status</th>
                  <th className="px-6 py-3.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {paginatedExpenses.map((e) => (
                  <tr key={e.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-semibold text-slate-800">{e.expense_number}</td>
                    <td className="px-6 py-4 text-slate-500">{new Date(e.expense_date).toLocaleDateString("en-IN")}</td>
                    <td className="px-6 py-4">
                      <span className="px-2 py-0.5 text-xs font-semibold rounded-full bg-orange-50 text-orange-700 border border-orange-200">
                        {e.category_name || "—"}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-slate-600">{e.vendor_name || "—"}</td>
                    <td className="px-6 py-4 text-slate-500 max-w-[200px] truncate">{e.description || "—"}</td>
                    <td className="px-6 py-4 text-right font-semibold font-mono text-slate-800">{formatCurrency(e.total)}</td>
                    <td className="px-6 py-4">
                      <span className={`px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center gap-1 ${
                        e.status === "POSTED"
                          ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                          : e.status === "DRAFT"
                          ? "bg-amber-50 text-amber-700 border border-amber-200"
                          : "bg-rose-50 text-rose-700 border border-rose-200"
                      }`}>
                        {e.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <div className="inline-flex items-center gap-2">
                        <button
                          onClick={() => onNavigate("expense_detail", e.id)}
                          title="View Details"
                          aria-label="View expense details"
                          className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        {e.status === "DRAFT" && (
                          <button
                            onClick={() => onNavigate("expense_edit", e.id)}
                            title="Edit Expense"
                            aria-label="Edit expense"
                            className="p-1 text-slate-400 hover:text-amber-600 hover:bg-slate-100 rounded transition"
                          >
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                            </svg>
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination currentPage={page} totalPages={totalPages} onPageChange={setPage} totalItems={filteredExpenses.length} pageSize={itemsPerPage} />
        </div>
      )}
    </div>
  );
}
