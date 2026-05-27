import React, { useState, useEffect } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Save } from "lucide-react";
import { useUnsavedChangesWarning } from "../../hooks/useUnsavedChangesWarning";

const GST_RATES = [0, 5, 12, 18, 28];

interface ExpenseFormProps {
  editId?: string;
  onNavigate: (view: "expense_list" | "expense_create" | "expense_edit" | "expense_detail", expenseId?: string) => void;
  onSuccess: () => void;
}

interface ExpenseCategory {
  id: string;
  name: string;
}

interface Account {
  id: string;
  name: string;
  account_type: string;
}

interface PreviewData {
  amount: number;
  gst_rate: number;
  cgst_amount: number;
  sgst_amount: number;
  total: number;
}

export default function ExpenseForm({ editId, onNavigate, onSuccess }: ExpenseFormProps) {
  const isEdit = Boolean(editId);

  const [categoryId, setCategoryId] = useState("");
  const [bankAccountId, setBankAccountId] = useState("");
  const [expenseDate, setExpenseDate] = useState(new Date().toISOString().split("T")[0]);
  const [vendorName, setVendorName] = useState("");
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [gstRate, setGstRate] = useState("0");
  const [showNewCat, setShowNewCat] = useState(false);
  const [newCatName, setNewCatName] = useState("");

  const hasUnsavedChanges = categoryId !== "" || amount !== "";
  useUnsavedChangesWarning(hasUnsavedChanges);

  const { data: preview } = useQuery<PreviewData>({
    queryKey: ["expense-preview", amount, gstRate],
    queryFn: async () => {
      if (!amount || parseFloat(amount) <= 0) return null;
      const res = await apiClient.post("/expenses/preview", {
        amount: parseFloat(amount),
        gst_rate: parseFloat(gstRate),
      });
      return res.data;
    },
    enabled: !!amount && parseFloat(amount) > 0,
  });

  const { data: categories = [] } = useQuery<ExpenseCategory[]>({
    queryKey: ["expense-categories"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/expense-categories");
      return res.data;
    },
  });

  const { data: accounts = [] } = useQuery<Account[]>({
    queryKey: ["accounts"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/accounts");
      return res.data;
    },
  });

  const cashBankAccounts = accounts.filter(
    (a) => a.account_type === "ASSET" && (a.name.startsWith("Cash") || a.name.startsWith("Bank"))
  );

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
      setBankAccountId(existingExpense.bank_account_id || "");
      setExpenseDate(existingExpense.expense_date);
      setVendorName(existingExpense.vendor_name || "");
      setDescription(existingExpense.description || "");
      setAmount(String(existingExpense.amount));
      setGstRate(String(existingExpense.gst_rate || "0"));
    }
  }, [existingExpense]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        expense_category_id: categoryId,
        bank_account_id: bankAccountId || undefined,
        expense_date: expenseDate,
        vendor_name: vendorName || undefined,
        description: description || undefined,
        amount: parseFloat(amount),
        gst_rate: parseFloat(gstRate),
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
    if (!categoryId || !expenseDate || !amount) {
      setError("Please fill in all required fields.");
      return;
    }
    saveMutation.mutate();
  };

  const [error, setError] = useState("");
  const queryClient = useQueryClient();

  const createCatMutation = useMutation({
    mutationFn: async () => {
      const r = await apiClient.post("/masters/expense-categories", { name: newCatName });
      return r.data;
    },
    onSuccess: (data) => {
      setCategoryId(data.id);
      setNewCatName("");
      setShowNewCat(false);
      queryClient.invalidateQueries({ queryKey: ["expense-categories"] });
    },
    onError: (err: any) => setError(err.response?.data?.detail || "Failed to create category."),
  });

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button
          onClick={() => onNavigate("expense_list")}
          className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">
            {isEdit ? "Edit Expense" : "Record Expense"}
          </h1>
          <p className="text-xs text-zinc-500 mt-0.5">This will be posted to the general ledger.</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="bg-white rounded-xl shadow-sm border border-slate-100 p-6 space-y-5">
        {error && (
          <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
            <svg className="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
            </svg>
            <span className="text-sm">{error}</span>
          </div>
        )}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Expense Category</label>
            <button type="button" onClick={() => setShowNewCat(true)} className="text-[10px] text-brand-600 font-semibold hover:text-brand-700 transition">+ Add New</button>
          </div>
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

        {/* New Category Modal */}
        {showNewCat && (
          <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={() => setShowNewCat(false)}>
            <div className="bg-white rounded-2xl shadow-xl p-6 max-w-sm w-full" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-sm font-bold text-zinc-900 mb-3">New Expense Category</h3>
              <input
                type="text"
                value={newCatName}
                onChange={(e) => setNewCatName(e.target.value)}
                placeholder="e.g. Petrol, Travel, Rent..."
                className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 mb-4"
                autoFocus
              />
              <div className="flex justify-end gap-2">
                <button onClick={() => setShowNewCat(false)} className="px-3 py-2 text-xs font-semibold text-zinc-600 hover:bg-zinc-50 rounded-lg transition">Cancel</button>
                <button
                  onClick={() => createCatMutation.mutate()}
                  disabled={createCatMutation.isPending || !newCatName.trim()}
                  className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-xs font-semibold disabled:opacity-50 transition"
                >
                  {createCatMutation.isPending ? "Creating..." : "Create"}
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="space-y-2">
          <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Bank / Cash Account (optional)</label>
          <select
            value={bankAccountId}
            onChange={(e) => setBankAccountId(e.target.value)}
            className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
          >
            <option value="">Default (Cash on Hand)</option>
            {cashBankAccounts.map((acct) => (
              <option key={acct.id} value={acct.id}>{acct.name}</option>
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
          <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">GST Rate</label>
          <div className="flex gap-2 flex-wrap">
            {GST_RATES.map((rate) => (
              <button
                key={rate}
                type="button"
                onClick={() => setGstRate(String(rate))}
                className={`px-4 py-2 rounded-lg text-xs font-semibold border transition ${
                  String(gstRate) === String(rate)
                    ? "bg-brand-600 text-white border-brand-600"
                    : "bg-white text-slate-600 border-slate-200 hover:border-brand-300"
                }`}
              >
                {rate === 0 ? "NIL" : `GST ${rate}%`}
              </button>
            ))}
          </div>
        </div>

        {preview && (
          <div className="bg-slate-50 border border-slate-200 rounded-lg p-4 space-y-2">
            <h4 className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Expense Preview</h4>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <div className="text-slate-500">Amount (excl. tax):</div>
              <div className="text-right font-mono font-semibold text-slate-800">₹ {Number(preview.amount).toFixed(2)}</div>
              <div className="text-slate-500">CGST:</div>
              <div className="text-right font-mono text-slate-600">₹ {Number(preview.cgst_amount).toFixed(2)}</div>
              <div className="text-slate-500">SGST:</div>
              <div className="text-right font-mono text-slate-600">₹ {Number(preview.sgst_amount).toFixed(2)}</div>
              <div className="text-slate-500 font-semibold border-t border-slate-200 pt-1">Total:</div>
              <div className="text-right font-mono font-bold text-brand-700 border-t border-slate-200 pt-1">₹ {Number(preview.total).toFixed(2)}</div>
            </div>
          </div>
        )}

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
