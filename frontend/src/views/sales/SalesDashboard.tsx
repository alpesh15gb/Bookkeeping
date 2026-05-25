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

export default function SalesDashboard() {
  // Fetch summary cards data
  const { data: summary } = useQuery<SalesSummary>({
    queryKey: ["sales-summary"],
    queryFn: async () => {
      const res = await apiClient.get("/sales/summary");
      return res.data;
    }
  });

  // Fetch Invoices list
  const { data: invoices = [] } = useQuery<InvoiceListItem[]>({
    queryKey: ["invoices"],
    queryFn: async () => {
      const res = await apiClient.get("/invoices");
      return Array.isArray(res.data) ? res.data : [];
    }
  });

  // Fetch Bills list
  const { data: bills = [] } = useQuery<BillListItem[]>({
    queryKey: ["bills"],
    queryFn: async () => {
      const res = await apiClient.get("/bills");
      return Array.isArray(res.data) ? res.data : [];
    }
  });

  // Fetch Receipts list
  const { data: receipts = [] } = useQuery<ReceiptItem[]>({
    queryKey: ["payments-receipts"],
    queryFn: async () => {
      const res = await apiClient.get("/payments/receipts");
      return Array.isArray(res.data) ? res.data : [];
    }
  });

  // Fetch Disbursements list
  const { data: disbursements = [] } = useQuery<DisbursementItem[]>({
    queryKey: ["payments-disbursements"],
    queryFn: async () => {
      const res = await apiClient.get("/payments/disbursements");
      return Array.isArray(res.data) ? res.data : [];
    }
  });

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
    <div className="space-y-6">
      {/* Title Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 pb-3">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900 font-sans">Dashboard</h1>
        </div>
        <button
          onClick={handleExportCSV}
          disabled={recentInvoices.length === 0}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-zinc-50 text-zinc-700 border border-zinc-200 rounded-lg text-xs font-semibold shadow-sm transition"
        >
          <Download className="w-3.5 h-3.5" /> Export Report
        </button>
      </div>

      {/* Analytics KPI summary cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        {/* Total Sales Card */}
        <div className="bg-[#F0FDF4] border border-green-100 rounded-2xl p-5 shadow-[0_2px_8px_-3px_rgba(0,0,0,0.02)] flex items-center gap-4">
          <div className="p-3 bg-white text-green-600 rounded-full shadow-sm flex-shrink-0">
            <TrendingUp className="w-6 h-6" />
          </div>
          <div className="space-y-0.5">
            <span className="text-[11px] font-semibold text-zinc-500 block">Total Sales</span>
            <span className="text-2xl font-bold text-green-700 tracking-tight block">
              {formatCardCurrency(totalSalesVal)}
            </span>
            {renderTrendText(salesTrend)}
          </div>
        </div>

        {/* Total Purchases Card */}
        <div className="bg-[#EFF6FF] border border-blue-100 rounded-2xl p-5 shadow-[0_2px_8px_-3px_rgba(0,0,0,0.02)] flex items-center gap-4">
          <div className="p-3 bg-white text-blue-600 rounded-full shadow-sm flex-shrink-0">
            <ShoppingCart className="w-6 h-6" />
          </div>
          <div className="space-y-0.5">
            <span className="text-[11px] font-semibold text-zinc-500 block">Total Purchases</span>
            <span className="text-2xl font-bold text-blue-700 tracking-tight block">
              {formatCardCurrency(totalPurchasesVal)}
            </span>
            {renderTrendText(purchasesTrend)}
          </div>
        </div>

        {/* Total Expenses Card */}
        <div className="bg-[#FFF7ED] border border-orange-100 rounded-2xl p-5 shadow-[0_2px_8px_-3px_rgba(0,0,0,0.02)] flex items-center gap-4">
          <div className="p-3 bg-white text-orange-500 rounded-full shadow-sm flex-shrink-0">
            <FileText className="w-6 h-6" />
          </div>
          <div className="space-y-0.5">
            <span className="text-[11px] font-semibold text-zinc-500 block">Total Expenses</span>
            <span className="text-2xl font-bold text-orange-600 tracking-tight block">
              {formatCardCurrency(totalExpensesVal)}
            </span>
            {renderTrendText(expensesTrend)}
          </div>
        </div>

        {/* Cash in Hand Card */}
        <div className="bg-[#FEFCE8] border border-yellow-100 rounded-2xl p-5 shadow-[0_2px_8px_-3px_rgba(0,0,0,0.02)] flex items-center gap-4">
          <div className="p-3 bg-white text-amber-600 rounded-full shadow-sm flex-shrink-0">
            <Banknote className="w-6 h-6" />
          </div>
          <div className="space-y-0.5">
            <span className="text-[11px] font-semibold text-zinc-500 block">Cash in Hand</span>
            <span className="text-2xl font-bold text-amber-700 tracking-tight block">
              {formatCardCurrency(cashInHandVal)}
            </span>
            {renderTrendText(cashTrend)}
          </div>
        </div>
      </div>

      {/* Middle Grid - Recent Invoices & SVG Line Chart */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Recent Invoices list */}
        <div className="bg-white p-5 rounded-2xl border border-zinc-200 shadow-sm space-y-4">
          <div className="flex justify-between items-center pb-2">
            <h3 className="font-bold text-sm text-zinc-800">Recent Invoices</h3>
            <button className="text-xs text-brand-500 hover:text-brand-600 font-semibold flex items-center gap-0.5">
              View All <ArrowUpRight className="w-3.5 h-3.5" />
            </button>
          </div>

          {recentInvoices.length === 0 ? (
            <div className="text-center py-16 text-zinc-400 font-medium text-xs">
              No recent invoices found. Create an invoice to begin.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs border-collapse">
                <thead>
                  <tr className="bg-zinc-50 text-zinc-500 border-b border-zinc-100">
                    <th className="px-3 py-2.5 font-bold">Invoice #</th>
                    <th className="px-3 py-2.5 font-bold">Customer</th>
                    <th className="px-3 py-2.5 text-right font-bold">Amount</th>
                    <th className="px-3 py-2.5 text-center font-bold">Status</th>
                    <th className="px-3 py-2.5 font-bold">Date</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-50">
                  {recentInvoices.map((inv) => (
                    <tr key={inv.id} className="hover:bg-zinc-50/50 transition">
                      <td className="px-3 py-3 font-mono font-semibold text-zinc-700">{inv.invoice_number}</td>
                      <td className="px-3 py-3 font-semibold text-zinc-900">{inv.contact_name}</td>
                      <td className="px-3 py-3 text-right font-mono font-bold text-zinc-800">
                        {formatTableCurrency(inv.total)}
                      </td>
                      <td className="px-3 py-3 text-center">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-[10px] font-bold border ${
                          inv.status.toLowerCase() === "paid"
                            ? "bg-green-50 text-green-700 border-green-200"
                            : "bg-amber-50 text-amber-700 border-amber-200"
                        }`}>
                          {inv.status}
                        </span>
                      </td>
                      <td className="px-3 py-3 text-zinc-500">
                        {new Date(inv.issue_date).toLocaleDateString("en-IN", {
                          day: "numeric",
                          month: "short",
                          year: "numeric"
                        })}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="pt-2 text-center border-t border-zinc-100">
            <button className="text-xs text-brand-500 hover:text-brand-600 font-semibold inline-flex items-center gap-1">
              View All Invoices <ArrowUpRight className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        {/* SVG Multi-Line Chart (Recent Transactions) */}
        <div className="bg-white p-5 rounded-2xl border border-zinc-200 shadow-sm space-y-4">
          <div className="flex justify-between items-center pb-2">
            <h3 className="font-bold text-sm text-zinc-800">Recent Transactions</h3>
            <button className="inline-flex items-center gap-1 px-2.5 py-1 bg-white hover:bg-zinc-50 text-zinc-600 border border-zinc-200 rounded-lg text-[10px] font-bold shadow-sm transition">
              Last 7 Days <ChevronDown className="w-3.5 h-3.5 text-zinc-400" />
            </button>
          </div>

          {/* Legend */}
          <div className="flex items-center gap-4 text-[10px] font-bold text-zinc-500 pl-2">
            <div className="flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-full bg-[#10b981]" />
              <span>Sales</span>
            </div>
            <div className="flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-full bg-[#3b82f6]" />
              <span>Purchases</span>
            </div>
            <div className="flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-full bg-[#f97316]" />
              <span>Expenses</span>
            </div>
          </div>

          {/* SVG Chart */}
          <div className="w-full relative h-[190px]">
            <svg viewBox="0 0 500 200" className="w-full h-full font-mono text-[9px] text-zinc-400 select-none">
              {/* Horizontal Grid lines */}
              <line x1="45" y1="20" x2="480" y2="20" stroke="#f4f4f5" strokeWidth="1" />
              <line x1="45" y1="60" x2="480" y2="60" stroke="#f4f4f5" strokeWidth="1" />
              <line x1="45" y1="100" x2="480" y2="100" stroke="#f4f4f5" strokeWidth="1" strokeDasharray="3 3" />
              <line x1="45" y1="140" x2="480" y2="140" stroke="#f4f4f5" strokeWidth="1" />
              <line x1="45" y1="170" x2="480" y2="170" stroke="#e4e4e7" strokeWidth="1" />

              {/* Y Axis Labels */}
              {yLabels.map((val, idx) => (
                <text key={idx} x="40" y={yLabelPositions[idx]} textAnchor="end" fill="#a1a1aa" className="font-bold">
                  {formatTableCurrency(val)}
                </text>
              ))}

              {/* X Axis Labels */}
              {dailyData.map((d, i) => (
                <text key={i} x={getXCoordinate(i)} y="188" textAnchor="middle" fill="#a1a1aa" className="font-bold">
                  {d.label}
                </text>
              ))}

              {/* Data paths (drawn dynamically using coordinates computed from DB entries) */}
              <path
                d={salesPath}
                fill="none"
                stroke="#10b981"
                strokeWidth="2.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              {dailyData.map((d, i) => (
                <circle key={`sales-pt-${i}`} cx={getXCoordinate(i)} cy={getYCoordinate(d.sales)} r="3.5" fill="#10b981" />
              ))}

              <path
                d={purchasesPath}
                fill="none"
                stroke="#3b82f6"
                strokeWidth="2"
                strokeDasharray="4 4"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              {dailyData.map((d, i) => (
                <circle key={`purchases-pt-${i}`} cx={getXCoordinate(i)} cy={getYCoordinate(d.purchases)} r="3" fill="#3b82f6" />
              ))}

              <path
                d={expensesPath}
                fill="none"
                stroke="#f97316"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
              {dailyData.map((d, i) => (
                <circle key={`expenses-pt-${i}`} cx={getXCoordinate(i)} cy={getYCoordinate(d.expenses)} r="3" fill="#f97316" />
              ))}
            </svg>
          </div>
        </div>
      </div>
    </div>
  );
}
