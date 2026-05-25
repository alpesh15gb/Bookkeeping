import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, TrendingUp, TrendingDown, AlertTriangle } from "lucide-react";

interface ProfitLossProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail" | "ledger" | "trial_balance" | "profit_loss", accountId?: string) => void;
}

interface ProfitLossLine {
  account_name: string;
  account_code: string;
  amount: number;
}

interface ProfitLossData {
  revenue_lines: ProfitLossLine[];
  total_revenue: number;
  expense_lines: ProfitLossLine[];
  total_expenses: number;
  net_profit: number;
}

export default function ProfitLoss({ onNavigate }: ProfitLossProps) {
  const { data: report, isLoading, error } = useQuery<ProfitLossData>({
    queryKey: ["profit-loss"],
    queryFn: async () => {
      const res = await apiClient.get("/accounting/profit-loss");
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
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Profit & Loss Statement</h1>
        </div>
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertTriangle className="w-5 h-5 flex-shrink-0" />
          <span>Error loading profit & loss statement. Please check API server.</span>
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
        <h1 className="text-xl font-bold tracking-tight text-zinc-900">Profit & Loss Statement</h1>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Revenue Section */}
        <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm overflow-hidden">
          <div className="bg-zinc-50 border-b border-zinc-200 px-5 py-3 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <TrendingUp className="w-4 h-4 text-emerald-600" />
              <h2 className="font-bold text-xs uppercase tracking-wider text-zinc-700">Revenue / Income</h2>
            </div>
            <span className="text-[10px] text-zinc-400 font-mono">Count: {report.revenue_lines.length}</span>
          </div>

          {report.revenue_lines.length === 0 ? (
            <div className="p-6 text-center text-xs text-zinc-400 font-medium">No revenue accounts found.</div>
          ) : (
            <div className="divide-y divide-zinc-100">
              {report.revenue_lines.map((line, idx) => (
                <div key={idx} className="flex justify-between items-center px-5 py-3 text-xs">
                  <div>
                    <span className="font-semibold text-zinc-800">{line.account_name}</span>
                    <span className="text-[10px] text-zinc-400 ml-2 font-mono">{line.account_code}</span>
                  </div>
                  <span className="font-mono font-semibold text-zinc-700">{formatCurrency(line.amount)}</span>
                </div>
              ))}
            </div>
          )}

          <div className="bg-zinc-50/50 border-t border-zinc-200 px-5 py-3 flex justify-between items-center font-bold text-xs text-zinc-800">
            <span>Total Revenue</span>
            <span className="text-zinc-950 font-mono">{formatCurrency(report.total_revenue)}</span>
          </div>
        </div>

        {/* Expense Section */}
        <div className="bg-white rounded-lg border border-zinc-200/80 shadow-sm overflow-hidden">
          <div className="bg-zinc-50 border-b border-zinc-200 px-5 py-3 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <TrendingDown className="w-4 h-4 text-red-600" />
              <h2 className="font-bold text-xs uppercase tracking-wider text-zinc-700">Expenses</h2>
            </div>
            <span className="text-[10px] text-zinc-400 font-mono">Count: {report.expense_lines.length}</span>
          </div>

          {report.expense_lines.length === 0 ? (
            <div className="p-6 text-center text-xs text-zinc-400 font-medium">No expense accounts found.</div>
          ) : (
            <div className="divide-y divide-zinc-100">
              {report.expense_lines.map((line, idx) => (
                <div key={idx} className="flex justify-between items-center px-5 py-3 text-xs">
                  <div>
                    <span className="font-semibold text-zinc-800">{line.account_name}</span>
                    <span className="text-[10px] text-zinc-400 ml-2 font-mono">{line.account_code}</span>
                  </div>
                  <span className="font-mono font-semibold text-zinc-700">{formatCurrency(line.amount)}</span>
                </div>
              ))}
            </div>
          )}

          <div className="bg-zinc-50/50 border-t border-zinc-200 px-5 py-3 flex justify-between items-center font-bold text-xs text-zinc-800">
            <span>Total Expenses</span>
            <span className="text-zinc-950 font-mono">{formatCurrency(report.total_expenses)}</span>
          </div>
        </div>
      </div>

      {/* Net Profit / Loss Card */}
      <div
        className={`rounded-lg border shadow-sm p-5 flex items-center justify-between ${
          report.net_profit >= 0
            ? "bg-emerald-50/55 border-emerald-200/60 text-emerald-800"
            : "bg-red-50/55 border-red-200/60 text-red-800"
        }`}
      >
        <div className="flex items-center gap-3">
          <div className={`p-2 rounded-md ${report.net_profit >= 0 ? "bg-emerald-100" : "bg-red-100"}`}>
            {report.net_profit >= 0 ? (
              <TrendingUp className="w-5 h-5 text-emerald-700" />
            ) : (
              <TrendingDown className="w-5 h-5 text-red-700" />
            )}
          </div>
          <div>
            <h2 className="text-xs font-bold uppercase tracking-wider">
              {report.net_profit >= 0 ? "Net Profit" : "Net Loss"}
            </h2>
            <p className="text-[11px] opacity-80 mt-0.5">
              {report.total_revenue > 0 || report.total_expenses > 0
                ? `Revenue of ${formatCurrency(report.total_revenue)} minus Expenses of ${formatCurrency(report.total_expenses)}`
                : "No activity recorded for the period."}
            </p>
          </div>
        </div>
        <span className="text-lg font-bold font-mono">{formatCurrency(Math.abs(report.net_profit))}</span>
      </div>
    </div>
  );
}
