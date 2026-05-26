import React, { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, BookOpen, Eye, Edit, ShieldAlert, RotateCcw } from "lucide-react";

interface AccountListProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail" | "ledger" | "trial_balance" | "profit_loss", accountId?: string) => void;
}

interface AccountItem {
  id: string;
  name: string;
  code: string;
  account_type: string;
  parent_id: string | null;
  parent_name?: string;
  opening_balance: number;
  current_balance: number;
  is_active: boolean;
  created_at: string;
}

const ACCOUNT_TYPES = ["ALL", "ASSET", "LIABILITY", "EQUITY", "REVENUE", "EXPENSE"];

export default function AccountList({ onNavigate }: AccountListProps) {
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("ALL");

  const queryClient = useQueryClient();

  const { data: accounts = [], isLoading, error } = useQuery<AccountItem[]>({
    queryKey: ["accounts"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/accounts");
      return res.data;
    },
  });

  const [recalcState, setRecalcState] = useState<"idle" | "loading" | "done" | "error">("idle");

  const handleRecalculate = async () => {
    setRecalcState("loading");
    try {
      await apiClient.post("/accounting/recalculate-balances");
      setRecalcState("done");
      queryClient.invalidateQueries({ queryKey: ["accounts"] });
      setTimeout(() => setRecalcState("idle"), 3000);
    } catch {
      setRecalcState("error");
      setTimeout(() => setRecalcState("idle"), 3000);
    }
  };

  const formatCurrency = (amount: number | string) => {
    if (typeof amount === "string") amount = parseFloat(amount);
    if (typeof amount !== "number" || isNaN(amount)) amount = 0;
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 2,
    }).format(amount);
  };

  const filteredAccounts = accounts.filter((acc) => {
    const matchesSearch =
      acc.name.toLowerCase().includes(search.toLowerCase()) ||
      acc.code.toLowerCase().includes(search.toLowerCase());
    const matchesType = typeFilter === "ALL" || acc.account_type === typeFilter;
    return matchesSearch && matchesType;
  });

  const totals = filteredAccounts.reduce(
    (acc, curr) => ({
      openingBalance: acc.openingBalance + (Number(curr.opening_balance) || 0),
      currentBalance: acc.currentBalance + (Number(curr.current_balance) || 0),
    }),
    { openingBalance: 0, currentBalance: 0 }
  );

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Chart of Accounts</h1>
          <p className="text-sm text-slate-500">Manage your company's chart of accounts and view ledgers.</p>
        </div>
        <div className="flex gap-2">
          <button
            onClick={handleRecalculate}
            disabled={recalcState === "loading"}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg font-semibold text-sm transition ${
              recalcState === "done"
                ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                : recalcState === "error"
                ? "bg-rose-50 text-rose-700 border border-rose-200"
                : "border border-slate-200 text-slate-700 hover:bg-slate-50"
            }`}
          >
            <RotateCcw className={`w-4 h-4 ${recalcState === "loading" ? "animate-spin" : ""}`} />
            {recalcState === "loading" ? "Recalculating..." : recalcState === "done" ? "Done!" : recalcState === "error" ? "Failed" : "Recalculate"}
          </button>
          <button
            onClick={() => onNavigate("trial_balance")}
            className="flex items-center gap-2 px-4 py-2 border border-slate-200 text-slate-700 hover:bg-slate-50 rounded-lg font-semibold text-sm transition"
          >
            <BookOpen className="w-4 h-4" />
            Trial Balance
          </button>
          <button
            onClick={() => onNavigate("profit_loss")}
            className="flex items-center gap-2 px-4 py-2 border border-slate-200 text-slate-700 hover:bg-slate-50 rounded-lg font-semibold text-sm transition"
          >
            <BookOpen className="w-4 h-4" />
            P&L
          </button>
          <button
            onClick={() => onNavigate("create")}
            className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold transition"
          >
            <Plus className="w-4 h-4" />
            Create Account
          </button>
        </div>
      </div>

      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4.5 w-4.5 text-slate-400" />
          <input
            type="text"
            placeholder="Search by account name or code..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm"
          />
        </div>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
        >
          {ACCOUNT_TYPES.map((t) => (
            <option key={t} value={t}>
              {t === "ALL" ? "All Types" : t.charAt(0) + t.slice(1).toLowerCase()}
            </option>
          ))}
        </select>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span>Error loading accounts. Please check API server.</span>
        </div>
      ) : filteredAccounts.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <BookOpen className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Accounts Found</h3>
          <p className="text-xs text-slate-500 mt-1">Try resetting filters or create a new account to get started.</p>
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">Code</th>
                  <th className="px-6 py-3.5">Name</th>
                  <th className="px-6 py-3.5">Type</th>
                  <th className="px-6 py-3.5">Parent</th>
                  <th className="px-6 py-3.5 text-right">Opening Balance</th>
                  <th className="px-6 py-3.5 text-right">Current Balance</th>
                  <th className="px-6 py-3.5">Status</th>
                  <th className="px-6 py-3.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredAccounts.map((acc) => (
                  <tr key={acc.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-medium text-brand-900">{acc.code}</td>
                    <td className="px-6 py-4 font-semibold text-slate-800">{acc.name}</td>
                    <td className="px-6 py-4">
                      <span className="px-2.5 py-1 text-xs font-semibold rounded-full bg-slate-100 text-slate-700 border border-slate-200">
                        {acc.account_type}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-slate-500">{acc.parent_name || "—"}</td>
                    <td className="px-6 py-4 text-right text-slate-600">{formatCurrency(acc.opening_balance)}</td>
                    <td className="px-6 py-4 text-right font-semibold text-slate-800">{formatCurrency(acc.current_balance)}</td>
                    <td className="px-6 py-4">
                      <span
                        className={`px-2.5 py-1 text-xs font-semibold rounded-full ${
                          acc.is_active
                            ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                            : "bg-rose-50 text-rose-700 border border-rose-200"
                        }`}
                      >
                        {acc.is_active ? "Active" : "Inactive"}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <div className="inline-flex items-center gap-2">
                        <button
                          onClick={() => onNavigate("ledger", acc.id)}
                          title="View Ledger"
                          className="p-1 text-slate-400 hover:text-indigo-600 hover:bg-slate-100 rounded transition"
                        >
                          <BookOpen className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => onNavigate("detail", acc.id)}
                          title="View Details"
                          className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => onNavigate("edit", acc.id)}
                          title="Edit"
                          className="p-1 text-slate-400 hover:text-amber-600 hover:bg-slate-100 rounded transition"
                        >
                          <Edit className="w-4 h-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="bg-slate-50 border-t border-slate-200 font-semibold text-slate-700">
                <tr>
                  <td className="px-6 py-3.5" colSpan={4}>Totals ({filteredAccounts.length} accounts)</td>
                  <td className="px-6 py-3.5 text-right">{formatCurrency(totals.openingBalance)}</td>
                  <td className="px-6 py-3.5 text-right">{formatCurrency(totals.currentBalance)}</td>
                  <td className="px-6 py-3.5" colSpan={2}></td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
