import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Save } from "lucide-react";

interface ExpenseFormProps {
  editId?: string;
  onNavigate: (view: "expense_list" | "expense_create" | "expense_edit" | "expense_detail", expenseId?: string) => void;
  onSuccess: () => void;
}

interface ExpenseCategory {
  id: string;
  name: string;
}

export default function ExpenseForm({ editId, onNavigate, onSuccess }: ExpenseFormProps) {
  const isEdit = Boolean(editId);

  const [categoryId, setCategoryId] = useState("");
  const [expenseDate, setExpenseDate] = useState(new Date().toISOString().split("T")[0]);
  const [vendorName, setVendorName] = useState("");
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");

  const { data: categories = [] } = useQuery<ExpenseCategory[]>({
    queryKey: ["expense-categories"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/expense-categories");
      return res.data;
    },
  });

  const { data: existingExpense } = useQuery({
    queryKey: ["expense", editId],
    queryFn: async () => {
      const res = await apiClient.get(`/expenses/${editId}`);
      return res.data;
    },
    enabled: isEdit,
  });

  useEffect(() => {
    if (existingExpense) {
      setCategoryId(existingExpense.expense_category_id);
      setExpenseDate(existingExpense.expense_date);
      setVendorName(existingExpense.vendor_name || "");
      setDescription(existingExpense.description || "");
      setAmount(String(existingExpense.amount));
    }
  }, [existingExpense]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        expense_category_id: categoryId,
        expense_date: expenseDate,
        vendor_name: vendorName || undefined,
        description: description || undefined,
        amount: parseFloat(amount),
      };
      if (isEdit) {
        await apiClient.put(`/expenses/${editId}`, payload);
      } else {
        await apiClient.post("/expenses", payload);
      }
    },
    onSuccess: () => onSuccess(),
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!categoryId || !expenseDate || !amount) return;
    saveMutation.mutate();
  };

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button
          onClick={() => onNavigate("expense_list")}
          className="p-1.5 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-4 h-4" />
        </button>
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">
            {isEdit ? "Edit Expense" : "Record Expense"}
          </h1>
          <p className="text-xs text-zinc-500 mt-0.5">This will be posted to the general ledger.</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="bg-white rounded-xl shadow-sm border border-slate-100 p-6 space-y-5">
        <div className="space-y-2">
          <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Expense Category</label>
          <select
            value={categoryId}
            onChange={(e) => setCategoryId(e.target.value)}
            className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            required
          >
            <option value="">Select category...</option>
            {categories.map((cat) => (
              <option key={cat.id} value={cat.id}>{cat.name}</option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Expense Date</label>
            <input
              type="date"
              value={expenseDate}
              onChange={(e) => setExpenseDate(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Amount (₹)</label>
            <input
              type="number"
              min="0.01"
              step="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono"
              required
            />
          </div>
        </div>

        <div className="space-y-2">
          <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Vendor Name (optional)</label>
          <input
            type="text"
            value={vendorName}
            onChange={(e) => setVendorName(e.target.value)}
            placeholder="e.g. Rent paid to landlord"
            className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
        </div>

        <div className="space-y-2">
          <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Description (optional)</label>
          <textarea
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Enter expense description..."
            className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 resize-none"
          />
        </div>

        <div className="flex justify-end gap-3 pt-2">
          <button
            type="button"
            onClick={() => onNavigate("expense_list")}
            className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saveMutation.isPending}
            className="px-6 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50 flex items-center gap-1.5"
          >
            <Save className="w-4 h-4" />
            {saveMutation.isPending ? "Saving..." : isEdit ? "Update Expense" : "Save Expense"}
          </button>
        </div>
      </form>
    </div>
  );
}
