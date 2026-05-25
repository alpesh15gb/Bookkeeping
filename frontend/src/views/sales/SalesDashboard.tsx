import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { 
  TrendingUp, 
  CheckCircle2, 
  AlertCircle, 
  FileText, 
  ArrowRightLeft, 
  Download 
} from "lucide-react";

interface SalesSummary {
  total_sales: number;
  total_received: number;
  outstanding: number;
  total_gst_liability: number;
}

interface CustomerWiseSale {
  customer_name: string;
  invoice_count: number;
  taxable_amount: number;
  tax_amount: number;
  total_sales: number;
}

interface PeriodWiseSale {
  period: string;
  invoice_count: number;
  total_sales: number;
}

export default function SalesDashboard() {
  // Fetch summary cards data
  const { data: summary } = useQuery<SalesSummary>({
    queryKey: ["sales-summary"],
    queryFn: async () => {
      const res = await apiClient.get("/sales/summary");
      return res.data;
    }
  });

  // Fetch customer-wise sales
  const { data: customerSales = [] } = useQuery<CustomerWiseSale[]>({
    queryKey: ["sales-customer-wise"],
    queryFn: async () => {
      const res = await apiClient.get("/sales/customer-wise");
      return res.data;
    }
  });

  // Fetch period-wise monthly sales
  const { data: periodSales = [] } = useQuery<PeriodWiseSale[]>({
    queryKey: ["sales-period-wise"],
    queryFn: async () => {
      const res = await apiClient.get("/sales/period-wise");
      return res.data;
    }
  });

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 2,
    }).format(val || 0);
  };

  const handleExportCSV = () => {
    // Generate CSV content of customer sales
    const headers = "Customer Name,Invoices Count,Taxable Val (INR),Tax Amt (INR),Total Sales (INR)\n";
    const rows = customerSales.map(c => 
      `"${c.customer_name}",${c.invoice_count},${c.taxable_amount},${c.tax_amount},${c.total_sales}`
    ).join("\n");
    
    const blob = new Blob([headers + rows], { type: "text/csv" });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `customer_sales_report_${new Date().toISOString().split("T")[0]}.csv`;
    link.click();
    window.URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-6">
      {/* Title Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 pb-4 border-b border-zinc-200/60">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Sales Dashboard</h1>
          <p className="text-xs text-zinc-500 mt-1">Track company turnover, tax collections, and receivable balances.</p>
        </div>
        <button
          onClick={handleExportCSV}
          disabled={customerSales.length === 0}
          className="btn-secondary text-xs py-1.5 px-3"
        >
          <Download className="w-3.5 h-3.5" /> Export Report
        </button>
      </div>

      {/* Analytics summary cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Total Sales Card */}
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm flex items-start justify-between">
          <div className="space-y-1">
            <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Total Sales</span>
            <span className="text-lg font-bold font-mono tracking-tight text-zinc-900 block">
              {formatCurrency(summary?.total_sales || 0)}
            </span>
          </div>
          <div className="p-2 bg-zinc-50 text-zinc-500 border border-zinc-200/60 rounded-lg">
            <TrendingUp className="w-4 h-4" />
          </div>
        </div>

        {/* Total Collected Card */}
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm flex items-start justify-between">
          <div className="space-y-1">
            <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Total Collected</span>
            <span className="text-lg font-bold font-mono tracking-tight text-zinc-900 block">
              {formatCurrency(summary?.total_received || 0)}
            </span>
          </div>
          <div className="p-2 bg-zinc-50 text-zinc-500 border border-zinc-200/60 rounded-lg">
            <CheckCircle2 className="w-4 h-4" />
          </div>
        </div>

        {/* Outstanding Receivables Card */}
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm flex items-start justify-between">
          <div className="space-y-1">
            <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Outstanding</span>
            <span className="text-lg font-bold font-mono tracking-tight text-zinc-900 block">
              {formatCurrency(summary?.outstanding || 0)}
            </span>
          </div>
          <div className="p-2 bg-zinc-50 text-zinc-500 border border-zinc-200/60 rounded-lg">
            <AlertCircle className="w-4 h-4" />
          </div>
        </div>

        {/* GST Liability Card */}
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm flex items-start justify-between">
          <div className="space-y-1">
            <span className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">GST Liability</span>
            <span className="text-lg font-bold font-mono tracking-tight text-zinc-900 block">
              {formatCurrency(summary?.total_gst_liability || 0)}
            </span>
          </div>
          <div className="p-2 bg-zinc-50 text-zinc-500 border border-zinc-200/60 rounded-lg">
            <ArrowRightLeft className="w-4 h-4" />
          </div>
        </div>
      </div>

      {/* Detailed Aggregated tables */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Customer-wise sales summary */}
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm space-y-4">
          <div className="flex justify-between items-center pb-3 border-b border-zinc-100">
            <h3 className="font-semibold text-xs uppercase tracking-wider text-zinc-500">Top Customer Sales Ranking</h3>
            <span className="text-[10px] text-zinc-400 font-mono">Count: {customerSales.length}</span>
          </div>

          {customerSales.length === 0 ? (
            <div className="text-center py-12 text-zinc-400 text-xs font-medium">
              No sales recorded for this tenant yet.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="financial-table">
                <thead>
                  <tr>
                    <th>Customer</th>
                    <th className="text-center">Invoices</th>
                    <th className="text-right">Taxable Val</th>
                    <th className="text-right">Tax Value</th>
                    <th className="text-right">Total Sales</th>
                  </tr>
                </thead>
                <tbody>
                  {customerSales.map((c, idx) => (
                    <tr key={idx}>
                      <td className="font-medium text-zinc-900">{c.customer_name}</td>
                      <td className="text-center font-mono text-zinc-500">{c.invoice_count}</td>
                      <td className="numeric-val">{formatCurrency(c.taxable_amount)}</td>
                      <td className="numeric-val">{formatCurrency(c.tax_amount)}</td>
                      <td className="numeric-val font-semibold text-zinc-950">{formatCurrency(c.total_sales)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Period-wise monthly performance */}
        <div className="bg-white p-5 rounded-lg border border-zinc-200/80 shadow-sm space-y-4">
          <div className="flex justify-between items-center pb-3 border-b border-zinc-100">
            <h3 className="font-semibold text-xs uppercase tracking-wider text-zinc-500">Monthly Turnover Aggregation</h3>
            <span className="text-[10px] text-zinc-400 font-mono">FY 2026-27</span>
          </div>

          {periodSales.length === 0 ? (
            <div className="text-center py-12 text-zinc-400 text-xs font-medium">
              No sales transaction history found.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="financial-table">
                <thead>
                  <tr>
                    <th>Period (Month)</th>
                    <th className="text-center">Invoices Count</th>
                    <th className="text-right">Gross Sales Volume</th>
                  </tr>
                </thead>
                <tbody>
                  {periodSales.map((p, idx) => (
                    <tr key={idx}>
                      <td className="font-mono text-zinc-900">{p.period}</td>
                      <td className="text-center font-mono text-zinc-500">{p.invoice_count}</td>
                      <td className="numeric-val font-semibold text-zinc-950">{formatCurrency(p.total_sales)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
