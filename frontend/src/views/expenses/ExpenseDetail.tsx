import React from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Send, Edit, Trash2 } from "lucide-react";

interface ExpenseDetailProps {
  expenseId: string;
  onNavigate: (view: "expense_list" | "expense_create" | "expense_edit" | "expense_detail", expenseId?: string) => void;
}

export default function ExpenseDetail({ expenseId, onNavigate }: ExpenseDetailProps) {
  const queryClient = useQueryClient();

  const { data: expense, isLoading } = useQuery({
    queryKey: ["expense", expenseId],
    queryFn: async () => {
      const res = await apiClient.get(`/expenses/${expenseId}`);
      return res.data;
    },
  });

  const postMutation = useMutation({
    mutationFn: async () => {
      await apiClient.post(`/expenses/${expenseId}/post`);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["expense"] });
      queryClient.invalidateQueries({ queryKey: ["expenses"] });
    },
  });

  const deleteMutation = useMutation({
    mutationFn: async () => {
      await apiClient.delete(`/expenses/${expenseId}`);
    },
    onSuccess: () => {
      onNavigate("expense_list");
    },
  });

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 2,
    }).format(amount);
  };

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (!expense) {
    return (
      <div className="text-center py-20 text-slate-500">
        <p>Expense not found.</p>
        <button onClick={() => onNavigate("expense_list")} className="text-brand-600 font-semibold mt-2 hover:underline">
          Back to Expenses
        </button>
      </div>
    );
  }

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      <div className="flex items-center justify-between pb-4 border-b border-zinc-200/60">
        <div className="flex items-center gap-3">
          <button
          onClick={() => onNavigate("expense_list")}
          className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h1 className="text-xl font-bold tracking-tight text-zinc-900">
              Expense {expense.expense_number}
            </h1>
            <p className="text-xs text-zinc-500 mt-0.5">{expense.description || "No description"}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {expense.status === "DRAFT" && (
            <>
              <button
                onClick={() => onNavigate("expense_edit", expenseId)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-zinc-50 text-zinc-700 border border-zinc-200 rounded-lg text-xs font-semibold shadow-sm transition"
              >
                <Edit className="w-3.5 h-3.5" /> Edit
              </button>
              <button
                onClick={() => { if (confirm("Post this expense to the ledger?")) postMutation.mutate(); }}
                disabled={postMutation.isPending}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-xs font-semibold shadow-sm transition disabled:opacity-50"
              >
                <Send className="w-3.5 h-3.5" /> {postMutation.isPending ? "Posting..." : "Post to Ledger"}
              </button>
              <button
                onClick={() => { if (confirm("Delete this expense?")) deleteMutation.mutate(); }}
                className="p-1.5 text-zinc-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition"
              >
                <Trash2 className="w-4 h-4" />
              </button>
            </>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-5 space-y-4">
          <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider">Expense Details</h3>

          <div className="space-y-3">
            <div>
              <span className="text-[10px] font-bold text-zinc-400 uppercase block">Expense Number</span>
              <p className="text-sm font-mono font-semibold text-zinc-900 mt-0.5">{expense.expense_number}</p>
            </div>
            <div>
              <span className="text-[10px] font-bold text-zinc-400 uppercase block">Date</span>
              <p className="text-sm font-semibold text-zinc-900 mt-0.5">
                {new Date(expense.expense_date).toLocaleDateString("en-IN", { day: "numeric", month: "long", year: "numeric" })}
              </p>
            </div>
            <div>
              <span className="text-[10px] font-bold text-zinc-400 uppercase block">Category</span>
              <span className="mt-0.5 inline-flex px-2 py-0.5 text-xs font-semibold rounded-full bg-orange-50 text-orange-700 border border-orange-200">
                {expense.category_name || "—"}
              </span>
            </div>
            <div>
              <span className="text-[10px] font-bold text-zinc-400 uppercase block">Vendor</span>
              <p className="text-sm font-semibold text-zinc-900 mt-0.5">{expense.vendor_name || "—"}</p>
            </div>
            <div>
              <span className="text-[10px] font-bold text-zinc-400 uppercase block">Description</span>
              <p className="text-sm text-zinc-700 mt-0.5">{expense.description || "—"}</p>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-slate-100 p-5 space-y-4">
          <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider">Accounting</h3>

          <div className="space-y-3">
            <div>
              <span className="text-[10px] font-bold text-zinc-400 uppercase block">Amount</span>
              <p className="text-2xl font-bold text-zinc-900 mt-0.5">{formatCurrency(expense.amount)}</p>
            </div>
            <div>
              <span className="text-[10px] font-bold text-zinc-400 uppercase block">Status</span>
              <span className={`mt-0.5 inline-flex px-2.5 py-1 text-xs font-semibold rounded-full ${
                expense.status === "POSTED"
                  ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                  : expense.status === "DRAFT"
                  ? "bg-amber-50 text-amber-700 border border-amber-200"
                  : "bg-rose-50 text-rose-700 border border-rose-200"
              }`}>
                {expense.status}
              </span>
            </div>
            {expense.status === "POSTED" && (
              <div className="p-3 bg-emerald-50 border border-emerald-100 rounded-lg">
                <p className="text-xs text-emerald-700 font-semibold flex items-center gap-1.5">
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  Posted to ledger. Account balances have been updated.
                </p>
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="text-xs text-zinc-400">
        Created: {new Date(expense.created_at).toLocaleString("en-IN")}
        {expense.updated_at !== expense.created_at && (
          <> · Updated: {new Date(expense.updated_at).toLocaleString("en-IN")}</>
        )}
      </div>
    </div>
  );
}
