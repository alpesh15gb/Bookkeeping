import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import PageHeader from "../../components/PageHeader";
import MetricCard from "../../components/MetricCard";
import AppCard from "../../components/AppCard";
import SectionHeader from "../../components/SectionHeader";
import StatusBadge from "../../components/StatusBadge";
import AmountText from "../../components/AmountText";
import LoadingSpinner from "../../components/LoadingSpinner";
import ErrorBanner from "../../components/ErrorBanner";
import EmptyState from "../../components/EmptyState";
import { formatIndianCurrency } from "../../lib/utils";
import {
  TrendingUp,
  ShoppingCart,
  CreditCard,
  FileText,
  DollarSign,
  BarChart3,
  Users,
  ArrowRight,
  Eye,
  EyeOff,
  Landmark,
  Archive,
} from "lucide-react";

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

const QUICK_ACTIONS = [
  { label: "New Invoice", icon: FileText, view: "invoice_create", desc: "Create sales invoice" },
  { label: "New Bill", icon: ShoppingCart, view: "bill_create", desc: "Record vendor bill" },
  { label: "New Expense", icon: CreditCard, view: "expense_create", desc: "Log an expense" },
  { label: "Receive Payment", icon: DollarSign, view: "payment_receipt", desc: "Record payment in" },
  { label: "New Contact", icon: Users, view: "contact_create", desc: "Add customer/vendor" },
  { label: "View Reports", icon: BarChart3, view: "reports", desc: "GST & financial reports" },
];

export default function SalesDashboard({ onNavigate }: SalesDashboardProps) {
  const [showBalances, setShowBalances] = useState(true);

  const { data: summary, isLoading: summaryLoading, error: summaryError } = useQuery<SalesSummary>({
    queryKey: ["sales-summary"],
    queryFn: async () => { const r = await apiClient.get("/sales/summary"); return r.data; },
    refetchInterval: 30000,
  });

  const { data: invoices = [], isLoading: invLoading } = useQuery<InvoiceListItem[]>({
    queryKey: ["invoices"],
    queryFn: async () => { const r = await apiClient.get("/invoices"); return Array.isArray(r.data) ? r.data : []; },
    refetchInterval: 30000,
  });

  const { data: expenses = [], isLoading: expLoading } = useQuery<ExpenseItem[]>({
    queryKey: ["expenses"],
    queryFn: async () => { const r = await apiClient.get("/expenses"); return Array.isArray(r.data) ? r.data : []; },
    refetchInterval: 30000,
  });

  const { data: bills = [], isLoading: billsLoading } = useQuery<BillListItem[]>({
    queryKey: ["bills"],
    queryFn: async () => { const r = await apiClient.get("/bills"); return Array.isArray(r.data) ? r.data : []; },
    refetchInterval: 30000,
  });

  const isLoading = summaryLoading || invLoading || expLoading || billsLoading;
  const hasError = summaryError;

  const totalSalesVal = summary?.total_sales || 0;
  const totalGstLiability = summary?.total_gst_liability || 0;
  const outstandingVal = summary?.outstanding || 0;
  const cashReceivedVal = summary?.total_received || 0;
  const totalExpensesVal = expenses
    .filter((e) => e.status === "POSTED")
    .reduce((sum, e) => sum + (e.total || 0), 0);
  const totalPurchasesVal = bills
    .filter((b) => b.status !== "DRAFT" && b.status !== "CANCELLED")
    .reduce((s, b) => s + (b.total || 0), 0);
  const netProfit = totalSalesVal - totalExpensesVal - totalPurchasesVal;

  const draftInvoices = invoices.filter((i) => i.status === "DRAFT").length;
  const overdueInvoices = invoices.filter((i) => i.status === "OVERDUE").length;

  const recentInvoices = [...invoices]
    .sort((a, b) => new Date(b.issue_date).getTime() - new Date(a.issue_date).getTime())
    .slice(0, 5);

  if (isLoading) {
    return (
      <div className="space-y-6">
        <PageHeader title="Dashboard" subtitle="Financial overview for your business" />
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="bg-white rounded-xl border border-zinc-200 p-5 animate-pulse">
              <div className="h-3 w-20 bg-zinc-200 rounded mb-4" />
              <div className="h-7 w-32 bg-zinc-100 rounded" />
            </div>
          ))}
        </div>
        <LoadingSpinner message="Loading dashboard data..." />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Dashboard"
        subtitle="Financial overview for your business"
        actions={[
          {
            label: showBalances ? "Hide Balances" : "Show Balances",
            icon: showBalances ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />,
            onClick: () => setShowBalances(!showBalances),
            variant: "secondary",
          },
        ]}
      />

      {hasError && (
        <ErrorBanner message="Error loading sales summary data. Some metrics may be incomplete." />
      )}

      {/* Row 1: Revenue & Sales KPIs */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricCard
          label="Total Sales"
          value={showBalances ? totalSalesVal : 0}
          icon={TrendingUp}
          iconColor="#10b981"
          trend={4.2}
        />
        <MetricCard
          label="Total Purchases"
          value={showBalances ? totalPurchasesVal : 0}
          icon={ShoppingCart}
          iconColor="#3b82f6"
        />
        <MetricCard
          label="Total Expenses"
          value={showBalances ? totalExpensesVal : 0}
          icon={CreditCard}
          iconColor="#ef4444"
        />
        <MetricCard
          label="GST Liability"
          value={showBalances ? totalGstLiability : 0}
          icon={Landmark}
          iconColor="#f59e0b"
          subtext="Net tax payable"
        />
      </div>

      {/* Row 2: Financial Health */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricCard
          label="Net Profit"
          value={showBalances ? netProfit : 0}
          icon={netProfit >= 0 ? TrendingUp : TrendingUp}
          iconColor={netProfit >= 0 ? "#10b981" : "#ef4444"}
          subtext={netProfit >= 0 ? "Revenue exceeds costs" : "Running at a loss"}
        />
        <MetricCard
          label="Cash Received"
          value={showBalances ? cashReceivedVal : 0}
          icon={DollarSign}
          iconColor="#8b5cf6"
          subtext="Total collections this period"
        />
        <MetricCard
          label="Outstanding"
          value={showBalances ? outstandingVal : 0}
          icon={Archive}
          iconColor="#ea580c"
          subtext={`${overdueInvoices} overdue`}
        />
        <MetricCard
          label="Invoices"
          value={showBalances ? draftInvoices : 0}
          icon={FileText}
          iconColor="#71717a"
          subtext={`${draftInvoices} draft, ${invoices.length} total`}
        />
      </div>

      {/* Quick Actions */}
      <AppCard padding="default">
        <SectionHeader title="Quick Actions" />
        <div className="grid grid-cols-3 lg:grid-cols-6 gap-3">
          {QUICK_ACTIONS.map((action) => (
            <button
              key={action.view}
              onClick={() => onNavigate?.(action.view)}
              className="flex flex-col items-center gap-2 p-3 rounded-xl border border-zinc-100 hover:border-brand-gold/40 hover:bg-brand-gold-light/50 transition group"
            >
              <div className="w-10 h-10 rounded-xl bg-zinc-50 flex items-center justify-center group-hover:bg-brand-gold-light transition">
                <action.icon className="w-5 h-5 text-zinc-500 group-hover:text-brand-gold transition" />
              </div>
              <div className="text-center">
                <p className="text-xs font-semibold text-zinc-700 group-hover:text-zinc-900 leading-none">
                  {action.label}
                </p>
                <p className="text-[10px] text-zinc-400 mt-0.5">{action.desc}</p>
              </div>
            </button>
          ))}
        </div>
      </AppCard>

      {/* Recent Invoices */}
      <AppCard padding="none">
        <div className="px-6 pt-5 pb-3 flex items-center justify-between">
          <h3 className="text-[15px] font-semibold text-zinc-900">Recent Invoices</h3>
          <button
            onClick={() => onNavigate?.("invoices")}
            className="inline-flex items-center gap-1 text-xs font-semibold text-brand-gold hover:text-brand-gold-hover transition"
          >
            View All <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </div>
        {recentInvoices.length === 0 ? (
          <EmptyState
            icon={FileText}
            title="No invoices yet"
            description="Create your first GST invoice to start tracking sales."
            action={{
              label: "Create Invoice",
              onClick: () => onNavigate?.("invoice_create"),
            }}
          />
        ) : (
          <div className="divide-y divide-zinc-100">
            {recentInvoices.map((inv) => (
              <div
                key={inv.id}
                className="flex items-center justify-between px-6 py-3.5 hover:bg-surface-hover transition cursor-pointer"
                onClick={() => onNavigate?.("invoice_detail", inv.id)}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${
                    inv.status === "PAID" ? "bg-emerald-500" :
                    inv.status === "CANCELLED" ? "bg-red-500" :
                    inv.status === "OVERDUE" ? "bg-red-500" :
                    "bg-amber-500"
                  }`} />
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-zinc-800 truncate">{inv.contact_name || "Unknown Customer"}</p>
                    <p className="text-xs text-zinc-400 font-mono">
                      {inv.invoice_number} · {new Date(inv.issue_date).toLocaleDateString("en-IN", { day: "numeric", month: "short" })}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-3 flex-shrink-0">
                  <AmountText value={inv.total} size="sm" compact />
                  <StatusBadge status={inv.status.toLowerCase()} />
                </div>
              </div>
            ))}
          </div>
        )}
      </AppCard>

      {/* Summary Footer */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { label: "Sales Revenue", value: totalSalesVal, color: "text-emerald-600", bg: "bg-emerald-50" },
          { label: "Expenses", value: totalExpensesVal, color: "text-red-600", bg: "bg-red-50" },
          { label: "Net Profit", value: netProfit, color: netProfit >= 0 ? "text-emerald-600" : "text-red-600", bg: netProfit >= 0 ? "bg-emerald-50" : "bg-red-50" },
          { label: "GST Payable", value: totalGstLiability, color: "text-amber-600", bg: "bg-amber-50" },
        ].map((item) => (
          <AppCard key={item.label} padding="sm" className="text-center">
            <p className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider mb-1">{item.label}</p>
            <p className={`text-sm font-bold font-mono ${item.color}`}>
              {item.value !== 0 ? formatIndianCurrency(item.value) : "—"}
            </p>
          </AppCard>
        ))}
      </div>
    </div>
  );
}
