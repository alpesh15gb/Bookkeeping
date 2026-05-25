import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, AlertTriangle, Scale } from "lucide-react";

interface TrialBalanceProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail" | "ledger" | "trial_balance" | "profit_loss", accountId?: string) => void;
}

interface TrialBalanceLine {
  account_id: string;
  account_name: string;
  account_code: string;
  account_type: string;
  opening_balance: number;
  total_debits: number;
  total_credits: number;
  closing_balance: number;
}

interface TrialBalanceData {
  lines: TrialBalanceLine[];
  total_opening_debits: number;
  total_opening_credits: number;
  total_debits: number;
  total_credits: number;
  total_closing_debits: number;
  total_closing_credits: number;
}

export default function TrialBalance({ onNavigate }: TrialBalanceProps) {
  const { data: report, isLoading, error } = useQuery<TrialBalanceData>({
    queryKey: ["trial-balance"],
    queryFn: async () => {
      const res = await apiClient.get("/accounting/trial-balance");
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

  if (error || !report) {
    return (
      <div>
        <div className="flex items-center gap-3 mb-6">
          <button
            onClick={() => onNavigate("list")}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Trial Balance</h1>
        </div>
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertTriangle className="w-5 h-5 flex-shrink-0" />
          <span>Error loading trial balance. Please check API server.</span>
        </div>
      </div>
    );
  }

  const isBalanced =
    report.total_opening_debits === report.total_opening_credits &&
    report.total_debits === report.total_credits &&
    report.total_closing_debits === report.total_closing_credits;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button
          onClick={() => onNavigate("list")}
          className="p-1.5 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-4 h-4" />
        </button>
        <h1 className="text-xl font-bold tracking-tight text-zinc-900">Trial Balance</h1>
      </div>

      {!isBalanced && (
        <div className="flex items-center gap-3 p-4 bg-amber-50 border border-amber-200 text-amber-700 rounded-lg text-xs">
          <AlertTriangle className="w-5 h-5 flex-shrink-0" />
          <span className="font-semibold">Trial balance is <strong>not balanced</strong>. Please review the entries.</span>
        </div>
      )}

      {isBalanced && report.lines.length > 0 && (
        <div className="flex items-center gap-3 p-4 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-lg text-xs">
          <Scale className="w-5 h-5 flex-shrink-0" />
          <span className="font-semibold">Trial balance is balanced. Debits equal credits.</span>
        </div>
      )}

      {report.lines.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-lg border border-zinc-200/80 shadow-sm">
          <Scale className="w-12 h-12 text-zinc-300 mx-auto mb-3" />
          <h3 className="text-xs font-semibold text-zinc-700 uppercase tracking-wider">No Accounts Found</h3>
          <p className="text-xs text-zinc-400 mt-1">Add accounts and post transactions to view the trial balance.</p>
        </div>
      ) : (
        <div className="bg-white rounded-lg shadow-sm border border-zinc-200/80 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="financial-table">
              <thead>
                <tr>
                  <th>Account Name</th>
                  <th>Code</th>
                  <th>Type</th>
                  <th className="text-right">Opening Balance</th>
                  <th className="text-right">Total Debits</th>
                  <th className="text-right">Total Credits</th>
                  <th className="text-right">Closing Balance</th>
                </tr>
              </thead>
              <tbody>
                {report.lines.map((line) => (
                  <tr key={line.account_id}>
                    <td className="font-semibold text-zinc-800">{line.account_name}</td>
                    <td className="font-mono text-zinc-900 text-xs">{line.account_code}</td>
                    <td>
                      <span className="badge badge-draft text-[10px]">
                        {line.account_type}
                      </span>
                    </td>
                    <td className="numeric-val">{formatCurrency(line.opening_balance)}</td>
                    <td className="numeric-val">{formatCurrency(line.total_debits)}</td>
                    <td className="numeric-val">{formatCurrency(line.total_credits)}</td>
                    <td className="numeric-val font-semibold text-zinc-900">{formatCurrency(line.closing_balance)}</td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="total-row text-xs">
                <tr>
                  <td colSpan={3}>Totals ({report.lines.length} accounts)</td>
                  <td className="text-right font-mono text-zinc-700">
                    <div className="text-[10px] text-zinc-400">Dr: {formatCurrency(report.total_opening_debits)}</div>
                    <div>Cr: {formatCurrency(report.total_opening_credits)}</div>
                  </td>
                  <td className="numeric-val text-zinc-950 font-bold">{formatCurrency(report.total_debits)}</td>
                  <td className="numeric-val text-zinc-950 font-bold">{formatCurrency(report.total_credits)}</td>
                  <td className="text-right font-mono text-zinc-700">
                    <div className="text-[10px] text-zinc-400">Dr: {formatCurrency(report.total_closing_debits)}</div>
                    <div>Cr: {formatCurrency(report.total_closing_credits)}</div>
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
