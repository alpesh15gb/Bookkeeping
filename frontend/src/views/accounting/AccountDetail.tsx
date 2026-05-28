import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, BookOpen, Edit, ShieldAlert, TrendingUp, TrendingDown } from "lucide-react";

interface AccountDetailProps {
  accountId: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail" | "ledger" | "trial_balance" | "profit_loss", accountId?: string) => void;
}

interface AccountData {
  id: string;
  name: string;
  code: string;
  account_type: string;
  opening_balance: number;
  current_balance: number;
  description: string;
  is_active: boolean;
}

interface LedgerLine {
  id: string;
  date: string;
  reference: string;
  description: string;
  debit: number;
  credit: number;
  running_balance: number;
  entry_number?: string;
}

const formatCurrency = (amount: number) =>
  new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(amount);

const getAccountTypeBadge = (type: string) => {
  const colors: Record<string, string> = {
    ASSET: "bg-blue-50/50 text-blue-800 border-blue-200/60",
    LIABILITY: "bg-amber-50/50 text-amber-800 border-amber-200/60",
    EQUITY: "bg-purple-50/50 text-purple-800 border-purple-200/60",
    INCOME: "bg-emerald-50/50 text-emerald-800 border-emerald-200/60",
    EXPENSE: "bg-red-50/50 text-red-800 border-red-200/60",
  };
  return `badge ${colors[type?.toUpperCase()] || "badge-draft"}`;
};

export default function AccountDetail({ accountId, onNavigate }: AccountDetailProps) {
  const { data: account, isLoading: accountLoading, error: accountError } = useQuery<AccountData>({
    queryKey: ["account", accountId],
    queryFn: async () => {
      const res = await apiClient.get(`/accounting/accounts/${accountId}`);
      return res.data;
    },
  });

  const { data: ledgerData, isLoading: ledgerLoading } = useQuery<{ lines: LedgerLine[]; opening_balance?: number }>({
    queryKey: ["ledger", accountId],
    queryFn: async () => {
      const res = await apiClient.get(`/accounting/ledger/${accountId}`);
      return res.data;
    },
    enabled: !!accountId,
  });

  const ledgerLines = ledgerData?.lines || (Array.isArray(ledgerData) ? ledgerData as unknown as LedgerLine[] : []);

  if (accountLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-zinc-850"></div>
      </div>
    );
  }

  if (accountError || !account) {
    return (
      <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg text-xs font-semibold">
        <ShieldAlert className="w-5 h-5 flex-shrink-0" />
        <span>Error loading account details. Please check the API server.</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 pb-4 border-b border-zinc-200/60">
        <div className="flex items-center gap-3">
          <button
            onClick={() => onNavigate("list")}
            className="p-1.5 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
          >
            <ArrowLeft className="w-4 h-4" />
          </button>
          <div>
            <h1 className="text-xl font-bold tracking-tight text-zinc-900">{account.name}</h1>
            <p className="text-xs text-zinc-500 mt-0.5">Account Code: <span className="font-mono font-semibold">{account.code}</span></p>
          </div>
        </div>
        <div className="flex items-center gap-2 self-stretch sm:self-auto justify-end">
          <button
            onClick={() => onNavigate("ledger", accountId)}
            className="btn-secondary text-xs py-1.5 px-3"
          >
            <BookOpen className="w-3.5 h-3.5 text-zinc-500" />
            View Ledger
          </button>
          <button
            onClick={() => onNavigate("edit", accountId)}
            className="btn-primary text-xs py-1.5 px-3"
          >
            <Edit className="w-3.5 h-3.5" />
            Edit
          </button>
        </div>
      </div>

      {/* Account Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm p-4 space-y-2">
          <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Account Type</p>
          <div>
            <span className={getAccountTypeBadge(account.account_type)}>{account.account_type}</span>
          </div>
        </div>

        <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm p-4 space-y-1">
          <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Opening Balance</p>
          <p className="text-lg font-bold font-mono tracking-tight text-zinc-900">{formatCurrency(account.opening_balance || 0)}</p>
        </div>

        <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm p-4 space-y-1">
          <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Current Balance</p>
          <p className={`text-lg font-bold font-mono tracking-tight ${(account.current_balance || 0) >= 0 ? "text-emerald-700" : "text-red-700"}`}>
            {formatCurrency(account.current_balance || 0)}
          </p>
        </div>

        <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm p-4 space-y-2">
          <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Status</p>
          <div>
            <span className={`badge ${
              account.is_active
                ? "badge-paid"
                : "badge-draft"
            }`}>
              {account.is_active ? "Active" : "Inactive"}
            </span>
          </div>
        </div>
      </div>

      {/* Description */}
      {account.description && (
        <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm p-4 space-y-1">
          <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Description</p>
          <p className="text-xs text-zinc-600 font-medium">{account.description}</p>
        </div>
      )}

      {/* Recent Journal Entries */}
      <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm overflow-hidden">
        <div className="bg-zinc-50 border-b border-zinc-200 px-5 py-3 flex items-center justify-between">
          <span className="font-semibold text-xs uppercase tracking-wider text-zinc-500">Recent Journal Entries (Ledger)</span>
          <button
            onClick={() => onNavigate("ledger", accountId)}
            className="text-xs text-zinc-650 hover:text-zinc-900 font-semibold transition"
          >
            View Full Ledger →
          </button>
        </div>

        {ledgerLoading ? (
          <div className="flex justify-center items-center py-12">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-zinc-800"></div>
          </div>
        ) : ledgerLines.length === 0 ? (
          <div className="text-center py-12 text-xs text-zinc-400 font-medium">
            No journal entries found for this account.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="financial-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Reference</th>
                  <th>Description</th>
                  <th className="text-right">
                    <span className="flex items-center justify-end gap-1">
                      <TrendingUp className="w-3 h-3 text-emerald-500" /> Debit
                    </span>
                  </th>
                  <th className="text-right">
                    <span className="flex items-center justify-end gap-1">
                      <TrendingDown className="w-3 h-3 text-red-500" /> Credit
                    </span>
                  </th>
                  <th className="text-right">Balance</th>
                </tr>
              </thead>
              <tbody>
                {ledgerLines.slice(0, 20).map((line) => (
                  <tr key={line.id}>
                    <td className="text-zinc-500 text-xs">
                      {new Date(line.date).toLocaleDateString("en-IN")}
                    </td>
                    <td className="font-mono text-xs text-zinc-900">
                      {line.entry_number || line.reference || "—"}
                    </td>
                    <td className="text-zinc-700 text-xs font-medium max-w-xs truncate">{line.description || "—"}</td>
                    <td className="numeric-val font-semibold text-emerald-700">
                      {line.debit > 0 ? formatCurrency(line.debit) : "—"}
                    </td>
                    <td className="numeric-val font-semibold text-red-600">
                      {line.credit > 0 ? formatCurrency(line.credit) : "—"}
                    </td>
                    <td className={`numeric-val font-semibold ${
                      line.running_balance >= 0 ? "text-zinc-900" : "text-red-650"
                    }`}>
                      {formatCurrency(line.running_balance)}
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
