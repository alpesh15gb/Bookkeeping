import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import DashboardSkeleton from "../../components/DashboardSkeleton";
import ErrorBanner from "../../components/ErrorBanner";

interface SalesSummary {
  total_sales: number;
  total_received: number;
  outstanding: number;
  total_gst_liability: number;
}

interface InvoiceListItem {
  id: string;
  invoice_number: string;
  contact_name: string;
  total: number;
  status: string;
  issue_date: string;
  amount_paid: number;
}

interface ExpenseItem {
  id: string;
  expense_number: string;
  total: number;
  status: string;
  expense_date: string;
  category_name: string | null;
}

interface BillListItem {
  id: string;
  total: number;
  status: string;
  issue_date: string;
}

interface SalesDashboardProps {
  onNavigate?: (view: string, id?: string) => void;
}

export default function SalesDashboard({ onNavigate }: SalesDashboardProps) {
  const [showBalances, setShowBalances] = useState(true);

  const { data: summary, isLoading: summaryLoading, error: summaryError } = useQuery<SalesSummary>({
    queryKey: ["sales-summary"],
    queryFn: async () => { const r = await apiClient.get("/sales/summary"); return r.data; },
    refetchInterval: 30000,
  });

  const { data: invoices = [], isLoading: invLoading, error: invError } = useQuery<InvoiceListItem[]>({
    queryKey: ["invoices"],
    queryFn: async () => { const r = await apiClient.get("/invoices"); return Array.isArray(r.data) ? r.data : []; },
    refetchInterval: 30000,
  });

  const { data: expenses = [], isLoading: expLoading, error: expError } = useQuery({
    queryKey: ["expenses"],
    queryFn: async () => { const r = await apiClient.get("/expenses"); return Array.isArray(r.data) ? r.data : []; },
    refetchInterval: 30000,
  });

  const { data: bills = [], isLoading: billsLoading, error: billsError } = useQuery<BillListItem[]>({
    queryKey: ["bills"],
    queryFn: async () => { const r = await apiClient.get("/bills"); return Array.isArray(r.data) ? r.data : []; },
    refetchInterval: 30000,
  });

  const isLoading = summaryLoading || invLoading || expLoading || billsLoading;
  const hasError = summaryError || invError || expError || billsError;

  const formatCurrency = (val: number) =>
    showBalances
      ? new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(val || 0)
      : "••••";

  const totalSalesVal = summary?.total_sales || 0;
  const totalGstLiability = summary?.total_gst_liability || 0;
  const outstandingVal = summary?.outstanding || 0;
  const cashReceivedVal = summary?.total_received || 0;
  const totalExpensesVal = expenses
    .filter((e) => e.status === "POSTED")
    .reduce((sum, e) => sum + e.total, 0);
  const totalPurchasesVal = bills
    .filter((b) => b.status !== "DRAFT" && b.status !== "CANCELLED")
    .reduce((s, b) => s + b.total, 0);
  const netProfit = totalSalesVal - totalExpensesVal - totalPurchasesVal;

  const recentInvoices = [...invoices]
    .sort((a, b) => new Date(b.issue_date).getTime() - new Date(a.issue_date).getTime())
    .slice(0, 5);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Dashboard</h1>
          <p className="text-sm text-zinc-500 mt-0.5">Financial overview for your business</p>
        </div>
        <button
          onClick={() => setShowBalances(!showBalances)}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-zinc-50 border border-zinc-200 rounded-lg text-xs font-semibold text-zinc-600 shadow-sm transition"
          aria-label={showBalances ? "Hide balances" : "Show balances"}
        >
          {showBalances ? (
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
            </svg>
          ) : (
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
            </svg>
          )}
          {showBalances ? "Hide" : "Show"}
        </button>
      </div>

      {isLoading ? (
        <DashboardSkeleton cards={4} />
      ) : hasError ? (
        <ErrorBanner message="Error loading dashboard data. Some metrics may be incomplete." />
      ) : (
        <>
          {/* KPI Cards */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <KpiCard
              label="Total Sales"
              value={formatCurrency(totalSalesVal)}
              subtitle="Revenue from invoices"
              color="emerald"
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
                </svg>
              }
            />
            <KpiCard
              label="Total Purchases"
              value={formatCurrency(totalPurchasesVal)}
              subtitle="Cost of goods / services"
              color="blue"
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
                </svg>
              }
            />
            <KpiCard
              label="Total Expenses"
              value={formatCurrency(totalExpensesVal)}
              subtitle="Operating & misc expenses"
              color="rose"
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
                </svg>
              }
            />
            <KpiCard
              label="GST Liability"
              value={formatCurrency(totalGstLiability)}
              subtitle="Net tax payable"
              color="amber"
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 14l6-6m-5.5.5h.01m4.99 5h.01M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z" />
                </svg>
              }
            />
          </div>

          {/* Second Row: Net Profit, Cash, Receivables, Payables */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <KpiCard
              label="Net Profit"
              value={formatCurrency(netProfit)}
              subtitle={netProfit >= 0 ? "Revenue - Expenses" : "Running at loss"}
              color={netProfit >= 0 ? "emerald" : "rose"}
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d={netProfit >= 0 ? "M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" : "M13 17h8m0 0v-8m0 8l-8-8-4 4-6-6"} />
                </svg>
              }
            />
            <KpiCard
              label="Cash Received"
              value={formatCurrency(cashReceivedVal)}
              subtitle="Total collections"
              color="violet"
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" />
                </svg>
              }
            />
            <KpiCard
              label="Outstanding"
              value={formatCurrency(outstandingVal)}
              subtitle="Unpaid invoices"
              color="orange"
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              }
            />
            <KpiCard
              label="Total Invoices"
              value={invoices.length.toString()}
              subtitle={`${invoices.filter(i => i.status === "DRAFT").length} draft`}
              color="slate"
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
              }
            />
          </div>

          {/* Quick Actions */}
          <div className="space-y-2">
            <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider border-l-2 border-brand-600 pl-2">Quick Actions</h3>
            <div className="grid grid-cols-4 lg:grid-cols-7 gap-2">
              {[
                { label: "Invoice", icon: "invoice", action: "invoices" },
                { label: "Estimate", icon: "estimate", action: "estimates" },
                { label: "Expense", icon: "expense", action: "expenses" },
                { label: "Bill", icon: "bill", action: "bills" },
                { label: "Payment", icon: "payment", action: "payments" },
                { label: "Contact", icon: "contact", action: "contacts" },
                { label: "Reports", icon: "report", action: "reports" },
              ].map((item) => (
                <button
                  key={item.action}
                  onClick={() => onNavigate?.(item.action)}
                  className="bg-white border border-slate-100 hover:border-brand-500 hover:shadow-md text-zinc-700 p-3 rounded-xl flex flex-col items-center justify-center gap-1.5 shadow-sm transition-all"
                >
                  <div className="p-1.5 bg-zinc-50 rounded-lg text-zinc-500">
                    {item.icon === "invoice" && (
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                      </svg>
                    )}
                    {item.icon === "estimate" && (
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                      </svg>
                    )}
                    {item.icon === "expense" && (
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
                      </svg>
                    )}
                    {item.icon === "bill" && (
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                      </svg>
                    )}
                    {item.icon === "payment" && (
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2z" />
                      </svg>
                    )}
                    {item.icon === "contact" && (
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z" />
                      </svg>
                    )}
                    {item.icon === "report" && (
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                      </svg>
                    )}
                  </div>
                  <span className="text-[10px] font-bold">{item.label}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Recent Transactions */}
          <div className="space-y-3">
            <div className="flex justify-between items-center">
              <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider border-l-2 border-brand-600 pl-2">Recent Transactions</h3>
              <button
                onClick={() => onNavigate?.("invoices")}
                className="text-[10px] text-brand-600 font-bold hover:text-brand-700 transition"
              >
                View All →
              </button>
            </div>
            <div className="bg-white border border-slate-100 rounded-xl shadow-sm divide-y divide-slate-50">
              {recentInvoices.length === 0 ? (
                <div className="text-center py-10 text-xs text-zinc-400">No transactions yet.</div>
              ) : (
                recentInvoices.map((inv) => (
                  <div key={inv.id} className="flex items-center justify-between p-3.5 hover:bg-zinc-50/50 transition">
                    <div className="flex items-center gap-3">
                      <div className={`p-1.5 rounded-full ${inv.status === "PAID" ? "bg-emerald-50 text-emerald-600" : inv.status === "CANCELLED" ? "bg-rose-50 text-rose-600" : "bg-amber-50 text-amber-600"}`}>
                        <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 11l5-5m0 0l5 5m-5-5v12" />
                        </svg>
                      </div>
                      <div>
                        <h4 className="text-xs font-bold text-zinc-800 leading-tight">{inv.contact_name}</h4>
                        <span className="text-[10px] text-zinc-400 block mt-0.5">
                          {inv.invoice_number} · {new Date(inv.issue_date).toLocaleDateString("en-IN", { day: "numeric", month: "short" })}
                        </span>
                      </div>
                    </div>
                    <div className="text-right">
                      <span className="text-xs font-extrabold text-zinc-800 block font-mono">{formatCurrency(inv.total)}</span>
                      <span className={`inline-flex px-1.5 py-0.5 rounded text-[8px] font-bold mt-0.5 ${
                        inv.status === "PAID" ? "bg-emerald-50 text-emerald-700" :
                        inv.status === "CANCELLED" ? "bg-rose-50 text-rose-700" :
                        "bg-amber-50 text-amber-700"
                      }`}>
                        {inv.status}
                      </span>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>

          {/* Summary Footer */}
          <div className="bg-white border border-slate-100 rounded-xl p-4 grid grid-cols-2 lg:grid-cols-4 gap-4 text-center shadow-sm">
            <div>
              <span className="text-[9px] font-bold text-zinc-400 uppercase block">Sales</span>
              <span className="text-sm font-bold text-emerald-700 block mt-0.5">{formatCurrency(totalSalesVal)}</span>
            </div>
            <div>
              <span className="text-[9px] font-bold text-zinc-400 uppercase block">Expenses</span>
              <span className="text-sm font-bold text-rose-700 block mt-0.5">{formatCurrency(totalExpensesVal)}</span>
            </div>
            <div>
              <span className="text-[9px] font-bold text-zinc-400 uppercase block">Net Profit</span>
              <span className={`text-sm font-bold block mt-0.5 ${netProfit >= 0 ? "text-emerald-700" : "text-rose-700"}`}>
                {formatCurrency(netProfit)}
              </span>
            </div>
            <div>
              <span className="text-[9px] font-bold text-zinc-400 uppercase block">GST Payable</span>
              <span className="text-sm font-bold text-amber-700 block mt-0.5">{formatCurrency(totalGstLiability)}</span>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function KpiCard({
  label,
  value,
  subtitle,
  color,
  icon,
}: {
  label: string;
  value: string;
  subtitle: string;
  color: string;
  icon: React.ReactNode;
}) {
  const colorMap: Record<string, { bg: string; icon: string; text: string }> = {
    emerald: { bg: "bg-emerald-50", icon: "text-emerald-600", text: "text-emerald-700" },
    blue: { bg: "bg-blue-50", icon: "text-blue-600", text: "text-blue-700" },
    rose: { bg: "bg-rose-50", icon: "text-rose-600", text: "text-rose-700" },
    amber: { bg: "bg-amber-50", icon: "text-amber-600", text: "text-amber-700" },
    violet: { bg: "bg-violet-50", icon: "text-violet-600", text: "text-violet-700" },
    orange: { bg: "bg-orange-50", icon: "text-orange-600", text: "text-orange-700" },
    slate: { bg: "bg-slate-50", icon: "text-slate-600", text: "text-slate-700" },
  };
  const c = colorMap[color] || colorMap.slate;

  return (
    <div className="bg-white border border-slate-100 rounded-xl p-4 shadow-sm flex items-start gap-3 hover:shadow-md transition-shadow">
      <div className={`p-2 ${c.bg} ${c.icon} rounded-xl`}>{icon}</div>
      <div className="min-w-0">
        <span className="text-[10px] font-bold text-zinc-400 uppercase block truncate">{label}</span>
        <span className="text-base font-extrabold text-zinc-900 block mt-0.5 font-mono tracking-tight">{value}</span>
        <span className={`text-[9px] font-bold ${c.text} block mt-0.5 truncate`}>{subtitle}</span>
      </div>
    </div>
  );
}
