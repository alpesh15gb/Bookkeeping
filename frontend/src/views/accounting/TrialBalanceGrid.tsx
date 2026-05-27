import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Printer, Download, CheckCircle, XCircle } from "lucide-react";
import SyncfusionGrid from "../../components/SyncfusionGrid";

interface TrialBalanceGridProps {
  onNavigate: (view: any, id?: string) => void;
}

export default function TrialBalanceGrid({ onNavigate }: TrialBalanceGridProps) {
  const { data, isLoading, error } = useQuery<any>({
    queryKey: ["trial-balance-grid"],
    queryFn: async () => {
      const res = await apiClient.get("/accounting/trial-balance");
      return res.data;
    },
  });

  const accounts = Array.isArray(data) ? data : data?.accounts || [];
  const totalDebit = data?.total_debit || accounts.reduce((s: number, a: any) => s + (a.debit || 0), 0);
  const totalCredit = data?.total_credit || accounts.reduce((s: number, a: any) => s + (a.credit || 0), 0);
  const isBalanced = Math.abs(totalDebit - totalCredit) < 0.01;

  const formatCurrency = (n: number) =>
    new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(n);

  const columns = [
    { field: "account_name", headerText: "Account Name", width: "220", textAlign: "Left" as const },
    { field: "code", headerText: "Code", width: "100", textAlign: "Left" as const },
    { field: "account_type", headerText: "Type", width: "110", textAlign: "Left" as const },
    { field: "opening_balance", headerText: "Opening Bal", width: "130", textAlign: "Right" as const, format: "c" },
    { field: "debit", headerText: "Debit", width: "130", textAlign: "Right" as const, format: "c" },
    { field: "credit", headerText: "Credit", width: "130", textAlign: "Right" as const, format: "c" },
    { field: "closing_balance", headerText: "Closing Bal", width: "130", textAlign: "Right" as const, format: "c" },
  ];

  const dataSource = accounts.map((a: any) => ({
    account_name: a.name || a.account_name,
    code: a.code,
    account_type: a.type || a.account_type,
    opening_balance: a.opening_balance || 0,
    debit: a.debit || 0,
    credit: a.credit || 0,
    closing_balance: a.closing_balance || a.current_balance || 0,
  }));

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button
          onClick={() => onNavigate("accounts")}
          className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1">
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Trial Balance</h1>
          <p className="text-xs text-zinc-500 mt-0.5">Verify debit and credit totals are in balance.</p>
        </div>
        <div className="flex items-center gap-2">
          <button className="inline-flex items-center gap-1 px-3 py-1.5 border border-zinc-200 bg-white text-zinc-700 rounded-lg text-xs font-semibold hover:bg-zinc-50 transition">
            <Printer className="w-3.5 h-3.5" /> Print
          </button>
          <button className="inline-flex items-center gap-1 px-3 py-1.5 border border-zinc-200 bg-white text-zinc-700 rounded-lg text-xs font-semibold hover:bg-zinc-50 transition">
            <Download className="w-3.5 h-3.5" /> Export
          </button>
        </div>
      </div>

      <div className={`flex items-center gap-3 p-4 rounded-lg border ${isBalanced ? "bg-emerald-50 border-emerald-200 text-emerald-700" : "bg-rose-50 border-rose-200 text-rose-700"}`}>
        {isBalanced ? <CheckCircle className="w-5 h-5" /> : <XCircle className="w-5 h-5" />}
        <div>
          <span className="text-sm font-bold">{isBalanced ? "Balanced" : "Out of Balance"}</span>
          <span className="text-xs ml-2 opacity-75">
            Debit: {formatCurrency(totalDebit)} — Credit: {formatCurrency(totalCredit)}
          </span>
        </div>
      </div>

      <div className="ej-grid-custom">
        <SyncfusionGrid
          dataSource={dataSource}
          columns={columns}
          allowPaging={true}
          allowSorting={true}
          allowFiltering={true}
          allowGrouping={true}
          allowExcelExport={true}
          allowPdfExport={true}
          toolbar={["ExcelExport", "PdfExport", "Search"]}
          pageSettings={{ pageSize: 25, pageSizes: [10, 25, 50, 100] }}
        />
      </div>
    </div>
  );
}
