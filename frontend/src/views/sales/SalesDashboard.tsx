import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { 
  TrendingUp, 
  ShoppingCart, 
  FileText, 
  Banknote,
  Download,
  ChevronDown,
  ArrowUpRight
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

interface BillListItem {
  id: string;
  total: number;
  status: string;
  issue_date: string;
}

interface ReceiptItem {
  id: string;
  amount: number;
  status: string;
  payment_date: string;
}

interface DisbursementItem {
  id: string;
  amount: number;
  status: string;
  payment_date: string;
}

// Helpers for local timezone safe dates
const getLocalDateString = (d: Date) => {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
};

const getLocalDateLabel = (d: Date) => {
  return d.toLocaleDateString("en-IN", { day: "numeric", month: "short" });
};

const getLast7Days = () => {
  const days = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    days.push(d);
  }
  return days;
};

interface SalesDashboardProps {
  onNavigate?: (view: string, id?: string) => void;
}

export default function SalesDashboard({ onNavigate }: SalesDashboardProps) {
  // Fetch summary cards data
  const { data: summary, isLoading: summaryLoading, error: summaryError } = useQuery<SalesSummary>({
    queryKey: ["sales-summary"],
    queryFn: async () => {
      const res = await apiClient.get("/sales/summary");
      return res.data;
    },
    refetchInterval: 30000,
  });

  // Fetch Invoices list
  const { data: invoices = [], isLoading: invLoading, error: invError } = useQuery<InvoiceListItem[]>({
    queryKey: ["invoices"],
    queryFn: async () => {
      const res = await apiClient.get("/invoices");
      return Array.isArray(res.data) ? res.data : [];
    },
    refetchInterval: 30000,
  });

  // Fetch Bills list
  const { data: bills = [], isLoading: billsLoading, error: billsError } = useQuery<BillListItem[]>({
    queryKey: ["bills"],
    queryFn: async () => {
      const res = await apiClient.get("/bills");
      return Array.isArray(res.data) ? res.data : [];
    },
    refetchInterval: 30000,
  });

  // Fetch Receipts list
  const { data: receipts = [], isLoading: recLoading, error: recError } = useQuery<ReceiptItem[]>({
    queryKey: ["payments-receipts"],
    queryFn: async () => {
      const res = await apiClient.get("/payments/receipts");
      return Array.isArray(res.data) ? res.data : [];
    },
    refetchInterval: 30000,
  });

  // Fetch Disbursements list
  const { data: disbursements = [], isLoading: disbLoading, error: disbError } = useQuery<DisbursementItem[]>({
    queryKey: ["payments-disbursements"],
    queryFn: async () => {
      const res = await apiClient.get("/payments/disbursements");
      return Array.isArray(res.data) ? res.data : [];
    },
    refetchInterval: 30000,
  });

  const isLoading = summaryLoading || invLoading || billsLoading || recLoading || disbLoading;
  const hasError = summaryError || invError || billsError || recError || disbError;

  // Format currency with Indian formatting and no decimals
  const formatCardCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 0,
    }).format(val || 0);
  };

  const formatTableCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 0,
    }).format(val || 0);
  };

  // 1. Dynamic Calculations from DB
  const totalSalesVal = summary?.total_sales || 0;
  const totalPurchasesVal = bills
    .filter(b => b.status.toUpperCase() !== "DRAFT")
    .reduce((sum, b) => sum + b.total, 0);
  const totalExpensesVal = disbursements
    .filter(d => d.status.toUpperCase() !== "CANCELLED")
    .reduce((sum, d) => sum + d.amount, 0);
  const cashInHandVal = summary?.total_received || 0;

  // 2. Month-over-Month Trend Math
  const now = new Date();
  const thisMonthKey = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0");
  
  const lastMonthDate = new Date();
  lastMonthDate.setMonth(now.getMonth() - 1);
  const lastMonthKey = lastMonthDate.getFullYear() + "-" + String(lastMonthDate.getMonth() + 1).padStart(2, "0");

  const getMonthlySales = (monthKey: string) => {
    return invoices
      .filter(i => i.issue_date && i.issue_date.startsWith(monthKey) && ["SENT", "PARTIALLY_PAID", "PAID"].includes(i.status.toUpperCase()))
      .reduce((sum, i) => sum + i.total, 0);
  };

  const getMonthlyPurchases = (monthKey: string) => {
    return bills
      .filter(b => b.issue_date && b.issue_date.startsWith(monthKey) && b.status.toUpperCase() !== "DRAFT")
      .reduce((sum, b) => sum + b.total, 0);
  };

  const getMonthlyExpenses = (monthKey: string) => {
    return disbursements
      .filter(d => d.payment_date && d.payment_date.startsWith(monthKey) && d.status.toUpperCase() !== "CANCELLED")
      .reduce((sum, d) => sum + d.amount, 0);
  };

  const getMonthlyCash = (monthKey: string) => {
    return invoices
      .filter(i => i.issue_date && i.issue_date.startsWith(monthKey))
      .reduce((sum, i) => sum + (i.amount_paid || 0), 0);
  };

  // Compute MoM percentage changes
  const calcTrend = (cur: number, prev: number) => {
    if (prev <= 0) return null;
    return ((cur - prev) / prev) * 100;
  };

  const salesTrend = calcTrend(getMonthlySales(thisMonthKey), getMonthlySales(lastMonthKey));
  const purchasesTrend = calcTrend(getMonthlyPurchases(thisMonthKey), getMonthlyPurchases(lastMonthKey));
  const expensesTrend = calcTrend(getMonthlyExpenses(thisMonthKey), getMonthlyExpenses(lastMonthKey));
  const cashTrend = calcTrend(getMonthlyCash(thisMonthKey), getMonthlyCash(lastMonthKey));

  const renderTrendText = (trend: number | null) => {
    if (trend === null) return <span className="text-zinc-400">No comparison data</span>;
    if (trend > 0) {
      return (
        <span className="text-green-600 font-medium flex items-center gap-0.5">
          <span>↗ {trend.toFixed(1)}%</span> <span className="text-zinc-400">from last month</span>
        </span>
      );
    }
    if (trend < 0) {
      return (
        <span className="text-red-500 font-medium flex items-center gap-0.5">
          <span>↘ {Math.abs(trend).toFixed(1)}%</span> <span className="text-zinc-400">from last month</span>
        </span>
      );
    }
    return (
      <span className="text-zinc-500 font-medium flex items-center gap-0.5">
        <span>0.0% change</span> <span className="text-zinc-400">from last month</span>
      </span>
    );
  };

  // 3. Dynamic Daily Chart Data (Last 7 Days)
  const dailyData = getLast7Days().map(dateObj => {
    const dateKey = getLocalDateString(dateObj);
    const label = getLocalDateLabel(dateObj);
    
    const sales = invoices
      .filter(i => i.issue_date && i.issue_date.startsWith(dateKey) && ["SENT", "PARTIALLY_PAID", "PAID"].includes(i.status.toUpperCase()))
      .reduce((sum, i) => sum + i.total, 0);
      
    const purchases = bills
      .filter(b => b.issue_date && b.issue_date.startsWith(dateKey) && b.status.toUpperCase() !== "DRAFT")
      .reduce((sum, b) => sum + b.total, 0);
      
    const expenses = disbursements
      .filter(d => d.payment_date && d.payment_date.startsWith(dateKey) && d.status.toUpperCase() !== "CANCELLED")
      .reduce((sum, d) => sum + d.amount, 0);
      
    return { label, sales, purchases, expenses };
  });

  // Calculate dynamic maximum ceiling for scaling the SVG chart lines
  const maxVal = Math.max(
    ...dailyData.map(d => Math.max(d.sales, d.purchases, d.expenses)),
    10000 // Minimum chart scale height of 10,000 INR
  );

  const getYCoordinate = (val: number) => {
    return 170 - (val / maxVal) * 150;
  };

  const getXCoordinate = (idx: number) => {
    return 70 + idx * 65;
  };

  // Generate SVG lines coordinates
  const salesPath = dailyData.map((d, i) => `${i === 0 ? 'M' : 'L'} ${getXCoordinate(i)} ${getYCoordinate(d.sales)}`).join(" ");
  const purchasesPath = dailyData.map((d, i) => `${i === 0 ? 'M' : 'L'} ${getXCoordinate(i)} ${getYCoordinate(d.purchases)}`).join(" ");
  const expensesPath = dailyData.map((d, i) => `${i === 0 ? 'M' : 'L'} ${getXCoordinate(i)} ${getYCoordinate(d.expenses)}`).join(" ");

  const yLabels = [
    maxVal,
    maxVal * 0.75,
    maxVal * 0.50,
    maxVal * 0.25,
    0
  ];
  const yLabelPositions = [23, 63, 103, 143, 173];

  // 4. Sorted Recent Invoices List
  const recentInvoices = [...invoices]
    .sort((a, b) => new Date(b.issue_date).getTime() - new Date(a.issue_date).getTime())
    .slice(0, 5);

  const handleExportCSV = () => {
    const headers = "Invoice #,Customer,Amount (INR),Status,Date\n";
    const rows = recentInvoices.map(r => 
      `"${r.invoice_number}","${r.contact_name}",${r.total},"${r.status}","${r.issue_date}"`
    ).join("\n");
    
    const blob = new Blob([headers + rows], { type: "text/csv" });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `sales_dashboard_export_${new Date().toISOString().split("T")[0]}.csv`;
    link.click();
    window.URL.revokeObjectURL(url);
  };
  return (
    <div className="space-y-6 max-w-full overflow-hidden">
      {/* Mobile Top Header */}
      <div className="md:hidden bg-[#0B1B3D] text-white p-4 -mx-4 -mt-4 mb-6 flex items-center justify-between border-b border-navy-800 shadow-lg">
        <div>
          <h2 className="text-sm font-bold text-white leading-tight">Dashboard</h2>
        </div>
      </div>

      {/* Dashboard Section Title */}
      <div className="flex items-center gap-2 border-b pb-2">
        <div className="grid grid-cols-2 gap-0.5 w-4 h-4 text-navy-900">
          <span className="bg-navy-900 rounded-sm" />
          <span className="bg-navy-900 rounded-sm" />
          <span className="bg-navy-900 rounded-sm" />
          <span className="bg-navy-900 rounded-sm" />
        </div>
        <h1 className="text-xl font-bold text-navy-900">Dashboard</h1>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-[#DCA035]"></div>
        </div>
      ) : hasError ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <svg className="w-5 h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <span className="text-xs font-semibold">Error loading dashboard data. Please check API server.</span>
        </div>
      ) : (
      <>
      {/* MoM Analytics KPI Cards */}
      <div className="grid grid-cols-2 gap-4">
        {/* Total Sales Card */}
        <div className="bg-white border border-slate-100 rounded-2xl p-4 shadow-sm flex items-start gap-3 relative overflow-hidden">
          <div className="p-2 bg-emerald-50 text-emerald-600 rounded-xl">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z" />
            </svg>
          </div>
          <div>
            <span className="text-[10px] font-bold text-slate-400 block uppercase">Total Sales</span>
            <span className="text-sm font-bold text-emerald-700 block mt-0.5">
              {formatCardCurrency(totalSalesVal)}
            </span>
            <span className="text-[9px] text-emerald-600 font-bold block mt-1">
              {salesTrend !== null ? `${salesTrend > 0 ? '↑' : '↓'} ${Math.abs(salesTrend).toFixed(1)}% this month` : "No prior data"}
            </span>
          </div>
        </div>

        {/* Total Purchases Card */}
        <div className="bg-white border border-slate-100 rounded-2xl p-4 shadow-sm flex items-start gap-3 relative overflow-hidden">
          <div className="p-2 bg-orange-50 text-orange-600 rounded-xl">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
            </svg>
          </div>
          <div>
            <span className="text-[10px] font-bold text-slate-400 block uppercase">Total Purchases</span>
            <span className="text-sm font-bold text-orange-700 block mt-0.5">
              {formatCardCurrency(totalPurchasesVal)}
            </span>
            <span className="text-[9px] text-orange-600 font-bold block mt-1">
              {purchasesTrend !== null ? `${purchasesTrend > 0 ? '↑' : '↓'} ${Math.abs(purchasesTrend).toFixed(1)}% this month` : "No prior data"}
            </span>
          </div>
        </div>

        {/* Total Expenses Card */}
        <div className="bg-white border border-slate-100 rounded-2xl p-4 shadow-sm flex items-start gap-3 relative overflow-hidden">
          <div className="p-2 bg-rose-50 text-rose-600 rounded-xl">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
            </svg>
          </div>
          <div>
            <span className="text-[10px] font-bold text-slate-400 block uppercase">Total Expenses</span>
            <span className="text-sm font-bold text-rose-700 block mt-0.5">
              {formatCardCurrency(totalExpensesVal)}
            </span>
            <span className="text-[9px] text-rose-600 font-bold block mt-1">
              {expensesTrend !== null ? `${expensesTrend > 0 ? '↑' : '↓'} ${Math.abs(expensesTrend).toFixed(1)}% this month` : "No prior data"}
            </span>
          </div>
        </div>

        {/* Cash in Hand Card */}
        <div className="bg-white border border-slate-100 rounded-2xl p-4 shadow-sm flex items-start gap-3 relative overflow-hidden">
          <div className="p-2 bg-blue-50 text-blue-600 rounded-xl">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" />
            </svg>
          </div>
          <div>
            <span className="text-[10px] font-bold text-slate-400 block uppercase">Total Received</span>
            <span className="text-sm font-bold text-blue-700 block mt-0.5">
              {formatCardCurrency(cashInHandVal)}
            </span>
            <span className="text-[9px] text-zinc-400 font-bold block mt-1">
              As on today
            </span>
          </div>
        </div>
      </div>

      {/* Quick Actions Panel */}
      <div className="space-y-2">
        <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider border-l-2 border-[#DCA035] pl-2">Quick Actions</h3>
        <div className="grid grid-cols-4 gap-2">
          {/* Add Invoice */}
          <button
            onClick={() => onNavigate?.("invoices")}
            className="bg-[#0B1B3D] text-white p-3 rounded-2xl flex flex-col items-center justify-center gap-1.5 shadow hover:bg-navy-800 transition"
          >
            <div className="p-1 text-[#DCA035]">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 13h6m-3-3v6m5 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
            </div>
            <span className="text-[9px] font-bold">Add Invoice</span>
          </button>

          {/* Add Expense */}
          <button
            onClick={() => onNavigate?.("expenses")}
            className="bg-[#0B1B3D] text-white p-3 rounded-2xl flex flex-col items-center justify-center gap-1.5 shadow hover:bg-navy-800 transition"
          >
            <div className="p-1 text-[#DCA035]">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <span className="text-[9px] font-bold">Add Expense</span>
          </button>

          {/* Add Party */}
          <button
            onClick={() => onNavigate?.("contacts")}
            className="bg-[#0B1B3D] text-white p-3 rounded-2xl flex flex-col items-center justify-center gap-1.5 shadow hover:bg-navy-800 transition"
          >
            <div className="p-1 text-[#DCA035]">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
              </svg>
            </div>
            <span className="text-[9px] font-bold">Add Party</span>
          </button>

          {/* View Reports */}
          <button
            onClick={() => onNavigate?.("reports")}
            className="bg-[#0B1B3D] text-white p-3 rounded-2xl flex flex-col items-center justify-center gap-1.5 shadow hover:bg-navy-800 transition"
          >
            <div className="p-1 text-[#DCA035]">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
              </svg>
            </div>
            <span className="text-[9px] font-bold">View Reports</span>
          </button>
        </div>
      </div>

      {/* Recent Transactions list */}
      <div className="space-y-3 pb-6">
        <div className="flex justify-between items-center">
          <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider border-l-2 border-[#DCA035] pl-2">Recent Transactions</h3>
          <button className="text-[10px] text-[#DCA035] font-bold flex items-center">View All <span className="ml-0.5">›</span></button>
        </div>

        <div className="bg-white border border-slate-100 rounded-2xl p-2 shadow-sm divide-y divide-slate-50">
          {recentInvoices.length === 0 ? (
            <div className="text-center py-10 text-xs text-slate-400">No transactions recorded yet.</div>
          ) : (
            recentInvoices.map((inv) => (
              <div key={inv.id} className="flex items-center justify-between p-3">
                <div className="flex items-center gap-3">
                  <div className="p-2 bg-emerald-50 text-emerald-600 rounded-full">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 11l5-5m0 0l5 5m-5-5v12" />
                    </svg>
                  </div>
                  <div>
                    <h4 className="text-xs font-bold text-slate-800 leading-tight">Invoice to {inv.contact_name}</h4>
                    <span className="text-[9px] text-slate-400 block mt-0.5">
                      {new Date(inv.issue_date).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" })}
                    </span>
                  </div>
                </div>
                <div className="text-right">
                  <span className="text-xs font-extrabold text-emerald-700 block">{formatTableCurrency(inv.total)}</span>
                  <span className="inline-flex px-1.5 py-0.5 rounded text-[8px] font-bold bg-green-50 text-green-700 border border-green-200 mt-0.5">Sale</span>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
      </>
      )}
    </div>
  );
}
