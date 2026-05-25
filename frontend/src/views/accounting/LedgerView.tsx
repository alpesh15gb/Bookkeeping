import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, AlertTriangle } from "lucide-react";

interface LedgerViewProps {
  accountId: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail" | "ledger" | "trial_balance" | "profit_loss", accountId?: string) => void;
}

interface LedgerLine {
  entry_date: string;
  reference_number: string;
  description: string;
  debit_amount: number;
  credit_amount: number;
  narration: string;
  running_balance: number;
}

interface LedgerData {
  account_id: string;
  account_name: string;
  account_code: string;
  opening_balance: number;
  closing_balance: number;
  lines: LedgerLine[];
}

export default function LedgerView({ accountId, onNavigate }: LedgerViewProps) {
  const { data: ledger, isLoading, error } = useQuery<LedgerData>({
    queryKey: ["ledger", accountId],
    queryFn: async () => {
      const res = await apiClient.get(`/accounting/ledger/${accountId}`);
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

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (error || !ledger) {
    return (
      <div>
        <div className="flex items-center gap-3 mb-6">
          <button
            onClick={() => onNavigate("list")}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Ledger Statement</h1>
        </div>
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertTriangle className="w-5 h-5 flex-shrink-0" />
          <span>Error loading ledger. Please check API server.</span>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button
          onClick={() => onNavigate("list")}
          className="p-1.5 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-4 h-4" />
        </button>
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Ledger Statement</h1>
          <p className="text-xs text-zinc-500 mt-0.5">{ledger.account_name} ({ledger.account_code})</p>
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm space-y-1">
          <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Opening Balance</span>
          <p className="text-lg font-bold font-mono tracking-tight text-zinc-900">{formatCurrency(ledger.opening_balance)}</p>
        </div>
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm space-y-1">
          <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Closing Balance</span>
          <p className="text-lg font-bold font-mono tracking-tight text-zinc-900">{formatCurrency(ledger.closing_balance)}</p>
        </div>
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm space-y-1">
          <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Total Entries</span>
          <p className="text-lg font-bold font-mono tracking-tight text-zinc-900">{ledger.lines.length}</p>
        </div>
      </div>

      {ledger.lines.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-lg border border-zinc-200/80 shadow-sm">
          <h3 className="text-xs font-semibold text-zinc-700 uppercase tracking-wider">No Transactions Found</h3>
          <p className="text-xs text-zinc-400 mt-1">This account has no recorded transactions in the selected period.</p>
        </div>
      ) : (
        <div className="bg-white rounded-lg shadow-sm border border-zinc-200/80 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="financial-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Reference #</th>
                  <th>Description</th>
                  <th className="text-right">Debit</th>
                  <th className="text-right">Credit</th>
                  <th className="text-right">Running Balance</th>
                </tr>
              </thead>
              <tbody>
                {ledger.lines.map((line, idx) => (
                  <tr key={idx}>
                    <td className="text-zinc-500 text-xs">{new Date(line.entry_date).toLocaleDateString("en-IN")}</td>
                    <td className="font-mono font-medium text-zinc-900">{line.reference_number}</td>
                    <td className="text-zinc-700 text-xs font-medium">{line.description}</td>
                    <td className="numeric-val">
                      {line.debit_amount > 0 ? formatCurrency(line.debit_amount) : "—"}
                    </td>
                    <td className="numeric-val">
                      {line.credit_amount > 0 ? formatCurrency(line.credit_amount) : "—"}
                    </td>
                    <td className="numeric-val font-semibold text-zinc-900">
                      {formatCurrency(line.running_balance)}
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
