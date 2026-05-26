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
    <div className="space-y-6 relative pb-16">
      {/* Desktop Header */}
      <div className="hidden md:flex justify-between items-center pb-2 border-b border-zinc-200">
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => onNavigate("list")}
            className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
          >
            <ArrowLeft className="w-5 h-5 text-[#0B1B3D]" />
          </button>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">
            {ledger.account_name} <span className="text-sm font-normal text-zinc-500">(Party Ledger)</span>
          </h1>
        </div>
      </div>

      {/* Mobile Top Header */}
      <div className="md:hidden bg-[#0B1B3D] text-white p-4 -mx-4 -mt-4 mb-6 flex items-center justify-between border-b border-navy-800 shadow-md">
        <div className="flex items-center gap-3">
          <button
            onClick={() => onNavigate("list")}
            className="p-1 text-zinc-300 hover:text-[#DCA035] transition"
          >
            <ArrowLeft className="w-5 h-5 text-[#DCA035]" />
          </button>
          <div>
            <h1 className="text-sm font-bold text-white leading-tight">{ledger.account_name}</h1>
            <p className="text-[10px] text-[#DCA035] font-semibold tracking-wider">Party Ledger</p>
          </div>
        </div>
        <div className="flex items-center gap-3 text-zinc-300">
          <button className="p-1.5 hover:bg-white/5 rounded-full transition">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.94.725l.548 2.2a1 1 0 01-.321.988l-1.305.98a10.582 10.582 0 004.872 4.872l.98-1.305a1 1 0 01.988-.321l2.2.548a1 1 0 01.725.94V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
            </svg>
          </button>
          <button className="p-1.5 hover:bg-white/5 rounded-full transition">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z" />
            </svg>
          </button>
        </div>
      </div>

      {/* Gold Opening Balance Card */}
      <div className="bg-[#DCA035] text-navy-900 p-5 rounded-2xl shadow-md flex items-center justify-between">
        <div>
          <span className="text-[10px] font-bold text-navy-800 uppercase block tracking-wider">Opening Balance</span>
          <span className="text-2xl font-extrabold block mt-0.5">{formatCurrency(ledger.opening_balance)}</span>
        </div>
        <div className="flex flex-col items-center gap-1.5 text-navy-800">
          <div className="p-2 bg-navy-900 text-[#DCA035] rounded-full shadow-sm">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 6l3 1m0 0l-3 9a5.002 5.002 0 006.001 0M6 7l3 9M6 7l6-2m6 2l3-1m-3 1l-3 9a5.002 5.002 0 006.001 0M18 7l3 9m-3-9l-6-2m0-2v2m0 16V5m0 16H9m3 0h3" />
            </svg>
          </div>
          <span className="text-[10px] font-bold uppercase tracking-wider">Credit (Cr)</span>
        </div>
      </div>

      {/* Filter Options */}
      <div className="flex items-center justify-between bg-white px-4 py-3 rounded-xl border border-slate-100 shadow-sm text-xs text-slate-500">
        <div className="flex items-center gap-2">
          <svg className="w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
          <span className="font-bold text-slate-700">All Transactions</span>
        </div>
        <svg className="w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </div>

      {/* Transactions Table */}
      {ledger.lines.length === 0 ? (
        <div className="text-center py-10 bg-white rounded-xl border border-slate-100 shadow-sm text-xs text-slate-400">
          No transactions found.
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-[11px] border-collapse">
              <thead className="bg-[#0B1B3D] text-white font-bold">
                <tr>
                  <th className="px-3 py-2.5">Date</th>
                  <th className="px-3 py-2.5">Type</th>
                  <th className="px-3 py-2.5">Ref No.</th>
                  <th className="px-3 py-2.5 text-right">Debit (₹)</th>
                  <th className="px-3 py-2.5 text-right">Credit (₹)</th>
                  <th className="px-3 py-2.5 text-right">Balance (₹)</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 font-medium text-slate-700">
                {ledger.lines.map((line, idx) => {
                  const isInvoice = line.description.toLowerCase().includes("invoice");
                  const isPayment = line.description.toLowerCase().includes("payment");

                  return (
                    <tr key={idx} className="hover:bg-slate-50/50 transition">
                      <td className="px-3 py-4 text-slate-500 font-bold whitespace-nowrap">
                        {new Date(line.entry_date).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}
                      </td>
                      <td className="px-3 py-4">
                        <div className="flex flex-col items-center gap-1">
                          <div className={`p-1.5 rounded-full ${
                            isInvoice ? "bg-blue-50 text-blue-600" : isPayment ? "bg-emerald-50 text-emerald-600" : "bg-orange-50 text-orange-600"
                          }`}>
                            {isInvoice ? (
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                              </svg>
                            ) : isPayment ? (
                              <span className="text-[10px] font-extrabold">₹</span>
                            ) : (
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
                              </svg>
                            )}
                          </div>
                          <span className="text-[9px] font-bold text-slate-400 uppercase tracking-wider">{isInvoice ? "Invoice" : isPayment ? "Payment" : "Bill"}</span>
                        </div>
                      </td>
                      <td className="px-3 py-4 font-mono font-bold text-slate-900">{line.reference_number || "—"}</td>
                      <td className="px-3 py-4 text-right font-bold text-slate-800">
                        {line.debit_amount > 0 ? formatCurrency(line.debit_amount).replace("₹", "") : "—"}
                      </td>
                      <td className="px-3 py-4 text-right font-bold text-blue-600">
                        {line.credit_amount > 0 ? formatCurrency(line.credit_amount).replace("₹", "") : "—"}
                      </td>
                      <td className="px-3 py-4 text-right font-mono font-bold text-slate-800">
                        {formatCurrency(line.running_balance).replace("₹", "")} <span className="text-[9px] text-[#C98F2C]">Cr</span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Bottom Summary Card */}
      <div className="bg-white border border-slate-100 rounded-2xl p-4 shadow-sm grid grid-cols-3 divide-x text-center">
        <div>
          <span className="text-[8px] font-bold text-slate-400 block uppercase">Total Debit</span>
          <span className="text-xs font-bold text-blue-700 block mt-1">
            {formatCurrency(ledger.lines.reduce((sum, l) => sum + l.debit_amount, 0))}
          </span>
        </div>
        <div>
          <span className="text-[8px] font-bold text-slate-400 block uppercase">Total Credit</span>
          <span className="text-xs font-bold text-emerald-600 block mt-1">
            {formatCurrency(ledger.lines.reduce((sum, l) => sum + l.credit_amount, 0))}
          </span>
        </div>
        <div>
          <span className="text-[8px] font-bold text-slate-400 block uppercase">Current Balance</span>
          <span className="text-xs font-bold text-amber-600 block mt-1">
            {formatCurrency(ledger.closing_balance)} <span className="text-[8px]">Cr</span>
          </span>
        </div>
      </div>

      {/* Sticky Bottom Actions */}
      <div className="flex gap-4 border-t pt-4 border-slate-100">
        <button className="flex-1 bg-white hover:bg-slate-50 border text-navy-900 py-3 rounded-2xl text-xs font-bold shadow-sm transition flex items-center justify-center gap-1.5">
          <svg className="w-4 h-4 text-navy-900" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
          </svg>
          View Statement
        </button>
        <button className="flex-1 bg-navy-900 hover:bg-navy-850 text-white py-3 rounded-2xl text-xs font-bold shadow-sm transition flex items-center justify-center gap-1.5">
          <svg className="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
          </svg>
          Download
        </button>
      </div>
    </div>
  );
}
