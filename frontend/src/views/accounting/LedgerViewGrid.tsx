import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Download, Printer, Search } from "lucide-react";
import SyncfusionGrid from "../../components/SyncfusionGrid";

interface LedgerViewGridProps {
  accountId?: string;
  onNavigate: (view: any, id?: string) => void;
}

export default function LedgerViewGrid({ accountId: initialAccountId, onNavigate }: LedgerViewGridProps) {
  const [selectedAccountId, setSelectedAccountId] = useState(initialAccountId || "");
  const accountId = selectedAccountId || initialAccountId;

  const { data: accounts = [] } = useQuery<any[]>({
    queryKey: ["accounts-list"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/accounts");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const { data: account, isLoading: acctLoading } = useQuery<any>({
    queryKey: ["account", accountId],
    queryFn: async () => {
      const res = await apiClient.get(`/masters/accounts/${accountId}`);
      return res.data;
    },
    enabled: !!accountId,
  });

  const { data: ledgerResponse, isLoading } = useQuery<any>({
    queryKey: ["ledger-grid", accountId],
    queryFn: async () => {
      const res = await apiClient.get(`/accounting/ledger/${accountId}`);
      return res.data;
    },
    enabled: !!accountId,
  });

  const entries = Array.isArray(ledgerResponse) ? ledgerResponse : ledgerResponse?.entries || [];
  const openingBalance = ledgerResponse?.opening_balance || account?.opening_balance || 0;
  const closingBalance = ledgerResponse?.closing_balance || 0;

  const formatCurrency = (n: number) =>
    new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(n);

  const columns = [
    { field: "entry_date", headerText: "Date", width: "110", textAlign: "Left" as const, format: "dd/MMM/yyyy" },
    { field: "source_type", headerText: "Type", width: "100", textAlign: "Left" as const },
    { field: "reference_number", headerText: "Ref #", width: "140", textAlign: "Left" as const },
    { field: "description", headerText: "Description", width: "220", textAlign: "Left" as const },
    { field: "debit", headerText: "Debit", width: "130", textAlign: "Right" as const, format: "c" },
    { field: "credit", headerText: "Credit", width: "130", textAlign: "Right" as const, format: "c" },
    { field: "balance", headerText: "Balance", width: "130", textAlign: "Right" as const, format: "c" },
  ];

  let runningBalance = openingBalance;
  const data = entries.map((e: any) => {
    const debit = e.direction === "DEBIT" ? e.amount : 0;
    const credit = e.direction === "CREDIT" ? e.amount : 0;
    runningBalance += debit - credit;
    return {
      entry_date: e.entry_date ? new Date(e.entry_date) : null,
      source_type: e.source_type || e.source_type_display || "-",
      reference_number: e.reference_number || "-",
      description: e.description || "-",
      debit,
      credit,
      balance: runningBalance,
    };
  });

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
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">
            {account?.name || "Ledger"}
          </h1>
          <p className="text-xs text-zinc-500 mt-0.5">{account?.code ? `${account.code} — ${account.account_type}` : "Select an account below"}</p>
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

      {!accountId && (
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-5">
          <label className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-2 block">Select Account</label>
          <div className="relative">
            <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
            <select
              value={selectedAccountId}
              onChange={(e) => setSelectedAccountId(e.target.value)}
              className="w-full pl-9 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm appearance-none bg-white"
            >
              <option value="">— Choose an account —</option>
              {accounts.map((acc: any) => (
                <option key={acc.id} value={acc.id}>
                  {acc.code} — {acc.name} ({acc.account_type})
                </option>
              ))}
            </select>
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-4">
          <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Opening Balance</p>
          <p className="text-lg font-bold text-zinc-800 mt-1">{formatCurrency(openingBalance)}</p>
        </div>
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-4">
          <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Debit Total</p>
          <p className="text-lg font-bold text-zinc-800 mt-1">{formatCurrency(data.reduce((s: number, r: any) => s + r.debit, 0))}</p>
        </div>
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-4">
          <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Credit Total</p>
          <p className="text-lg font-bold text-zinc-800 mt-1">{formatCurrency(data.reduce((s: number, r: any) => s + r.credit, 0))}</p>
        </div>
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-4">
          <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wider">Closing Balance</p>
          <p className="text-lg font-bold text-zinc-800 mt-1">{formatCurrency(closingBalance || runningBalance)}</p>
        </div>
      </div>

      <div className="ej-grid-custom">
        <SyncfusionGrid
          dataSource={data}
          columns={columns}
          allowPaging={true}
          allowSorting={true}
          allowExcelExport={true}
          allowPdfExport={true}
          toolbar={["ExcelExport", "PdfExport", "Search"]}
          pageSettings={{ pageSize: 25, pageSizes: [10, 25, 50, 100] }}
        />
      </div>
    </div>
  );
}
