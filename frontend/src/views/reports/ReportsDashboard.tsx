import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import {
  ArrowLeft,
  BarChart3,
  BookOpen,
  TrendingUp,
  DollarSign,
  Clock,
  Receipt,
  FileSpreadsheet,
  AlertTriangle,
  PieChart,
} from "lucide-react";

type ReportView =
  | "dashboard"
  | "balance_sheet"
  | "gstr1"
  | "gstr3b"
  | "aging_receivables"
  | "aging_payables"
  | "cash_flow"
  | "outstanding_receivables"
  | "outstanding_payables"
  | "sales_analytics"
  | "purchase_analytics";

interface ReportsDashboardProps {
  onNavigate: (view: ReportView, reportType?: string) => void;
}

interface BalanceSheetItem {
  account_name: string;
  account_code: string;
  account_type: string;
  balance: number;
}

interface BalanceSheetSection {
  items: BalanceSheetItem[];
  total: number;
}

interface BalanceSheetData {
  as_of_date: string;
  assets: BalanceSheetSection;
  liabilities: BalanceSheetSection;
  equity: BalanceSheetSection;
  total_liabilities_and_equity: number;
  is_balanced: boolean;
}

interface GSTR3BData {
  period_start: string;
  period_end: string;
  outward_taxable_supplies: {
    taxable_value: number;
    integrated_tax: number;
    central_tax: number;
    state_ut_tax: number;
    cess: number;
  };
  net_tax_payable_igst: number;
  net_tax_payable_cgst: number;
  net_tax_payable_sgst: number;
  net_tax_payable_cess: number;
}

interface AgingBucket {
  label: string;
  amount: number;
}

interface AgingLine {
  contact_id: string;
  contact_name: string;
  total_outstanding: number;
  buckets: AgingBucket[];
}

interface AgingReportData {
  as_of_date: string;
  report_type: string;
  lines: AgingLine[];
  total_outstanding: number;
  bucket_totals: AgingBucket[];
}

interface CashFlowItem {
  label: string;
  amount: number;
}

interface CashFlowSection {
  section: string;
  items: CashFlowItem[];
  net: number;
}

interface CashFlowData {
  period_start: string;
  period_end: string;
  operating_activities: CashFlowSection;
  investing_activities: CashFlowSection;
  financing_activities: CashFlowSection;
  net_change_in_cash: number;
  opening_cash_balance: number;
  closing_cash_balance: number;
}

interface OutstandingInvoice {
  invoice_id: string;
  invoice_number: string;
  contact_name: string;
  issue_date: string;
  due_date: string;
  total: number;
  amount_paid: number;
  outstanding: number;
  days_overdue: number;
}

interface OutstandingARData {
  as_of_date: string;
  invoices: OutstandingInvoice[];
  total_outstanding: number;
}

const formatCurrency = (val: number) => {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2,
  }).format(val ?? 0);
};

const formatDate = (dateStr: string) => {
  return new Date(dateStr).toLocaleDateString("en-IN");
};

function LoadingSpinner() {
  return (
    <div className="flex justify-center items-center py-20">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
    </div>
  );
}

function ErrorBanner({ message }: { message?: string }) {
  return (
    <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
      <AlertTriangle className="w-5 h-5 flex-shrink-0" />
      <span>{message || "Error loading report. Please check API server."}</span>
    </div>
  );
}

function EmptyState({ icon: Icon, title, message }: { icon: any; title: string; message?: string }) {
  return (
    <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
      <Icon className="w-12 h-12 text-slate-300 mx-auto mb-3" />
      <h3 className="text-sm font-semibold text-slate-700">{title}</h3>
      {message && <p className="text-xs text-slate-500 mt-1">{message}</p>}
    </div>
  );
}

interface ReportCardConfig {
  key: ReportView;
  icon: any;
  title: string;
  description: string;
  section: string;
  color: string;
}

const reportCards: ReportCardConfig[] = [
  { key: "balance_sheet", icon: BookOpen, title: "Balance Sheet", description: "Assets, liabilities, and equity snapshot", section: "Financial Reports", color: "bg-blue-50 text-blue-600" },
  { key: "cash_flow", icon: TrendingUp, title: "Cash Flow Statement", description: "Operating, investing, and financing activities", section: "Financial Reports", color: "bg-emerald-50 text-emerald-600" },
  { key: "gstr1", icon: FileSpreadsheet, title: "GSTR-1", description: "Outward supply summary for GST return", section: "GST Returns", color: "bg-indigo-50 text-indigo-600" },
  { key: "gstr3b", icon: Receipt, title: "GSTR-3B", description: "Monthly summary return and tax payable", section: "GST Returns", color: "bg-violet-50 text-violet-600" },
  { key: "aging_receivables", icon: Clock, title: "AR Aging", description: "Receivables aging by bucket periods", section: "Aging Reports", color: "bg-amber-50 text-amber-600" },
  { key: "aging_payables", icon: Clock, title: "AP Aging", description: "Payables aging by bucket periods", section: "Aging Reports", color: "bg-orange-50 text-orange-600" },
  { key: "outstanding_receivables", icon: DollarSign, title: "Outstanding Receivables", description: "Overdue invoices and recovery tracking", section: "Outstanding", color: "bg-rose-50 text-rose-600" },
  { key: "outstanding_payables", icon: DollarSign, title: "Outstanding Payables", description: "Pending payments to vendors", section: "Outstanding", color: "bg-red-50 text-red-600" },
  { key: "sales_analytics", icon: BarChart3, title: "Sales Analytics", description: "Revenue trends and sales performance", section: "Analytics", color: "bg-cyan-50 text-cyan-600" },
  { key: "purchase_analytics", icon: PieChart, title: "Purchase Analytics", description: "Spending patterns and vendor analysis", section: "Analytics", color: "bg-purple-50 text-purple-600" },
];

const sections = ["Financial Reports", "GST Returns", "Aging Reports", "Outstanding", "Analytics"];

function DashboardGrid({ onSelect }: { onSelect: (view: ReportView) => void }) {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">Reports &amp; GST</h1>
        <p className="text-sm text-slate-500 mt-1">Financial reports, GST returns, aging summaries, and analytics.</p>
      </div>

      {sections.map((section) => {
        const cards = reportCards.filter((c) => c.section === section);
        if (cards.length === 0) return null;
        return (
          <div key={section}>
            <h2 className="text-xs font-bold uppercase tracking-wider text-slate-400 mb-3">{section}</h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
              {cards.map((card) => (
                <button
                  key={card.key}
                  onClick={() => onSelect(card.key)}
                  className="bg-white p-5 rounded-xl border border-slate-100 shadow-sm hover:shadow-md hover:border-slate-200 transition text-left group"
                >
                  <div className={`h-10 w-10 ${card.color} rounded-lg flex items-center justify-center mb-3`}>
                    <card.icon className="w-5 h-5" />
                  </div>
                  <h3 className="text-sm font-bold text-slate-800 group-hover:text-brand-600 transition">{card.title}</h3>
                  <p className="text-xs text-slate-400 mt-1">{card.description}</p>
                </button>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

interface DateRangePickerProps {
  startDate: string;
  endDate: string;
  onStartChange: (d: string) => void;
  onEndChange: (d: string) => void;
}

function DateRangePicker({ startDate, endDate, onStartChange, onEndChange }: DateRangePickerProps) {
  return (
    <div className="flex items-center gap-3">
      <div>
        <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1">Start Date</label>
        <input
          type="date"
          value={startDate}
          onChange={(e) => onStartChange(e.target.value)}
          className="px-3 py-1.5 text-sm border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
        />
      </div>
      <div>
        <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1">End Date</label>
        <input
          type="date"
          value={endDate}
          onChange={(e) => onEndChange(e.target.value)}
          className="px-3 py-1.5 text-sm border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
        />
      </div>
    </div>
  );
}

function AsOfDatePicker({ asOfDate, onChange }: { asOfDate: string; onChange: (d: string) => void }) {
  return (
    <div>
      <label className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1">As Of Date</label>
      <input
        type="date"
        value={asOfDate}
        onChange={(e) => onChange(e.target.value)}
        className="px-3 py-1.5 text-sm border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
      />
    </div>
  );
}

function BalanceSheetView({ onBack }: { onBack: () => void }) {
  const today = new Date().toISOString().split("T")[0];
  const [asOfDate, setAsOfDate] = useState(today);

  const { data, isLoading, error } = useQuery<BalanceSheetData>({
    queryKey: ["report-balance-sheet", asOfDate],
    queryFn: async () => {
      const res = await apiClient.get("/reports/balance-sheet", { params: { as_of_date: asOfDate } });
      return res.data;
    },
  });

  if (isLoading) return <LoadingSpinner />;
  if (error || !data) return <ErrorBanner />;

  const renderSection = (title: string, section: BalanceSheetSection) => (
    <div className="mb-6">
      <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 mb-2">{title}</h3>
      <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
        <table className="w-full text-sm border-collapse">
          <thead className="bg-slate-50 text-slate-500 font-semibold text-xs">
            <tr>
              <th className="px-4 py-2.5 text-left">Account</th>
              <th className="px-4 py-2.5 text-left">Code</th>
              <th className="px-4 py-2.5 text-left">Type</th>
              <th className="px-4 py-2.5 text-right">Balance</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {section.items.length === 0 ? (
              <tr>
                <td colSpan={4} className="px-4 py-6 text-center text-slate-400 text-xs">No accounts in this category.</td>
              </tr>
            ) : (
              section.items.map((item, idx) => (
                <tr key={idx} className="hover:bg-slate-50/50">
                  <td className="px-4 py-2.5 font-semibold text-slate-800">{item.account_name}</td>
                  <td className="px-4 py-2.5 font-mono text-brand-900 text-xs">{item.account_code}</td>
                  <td className="px-4 py-2.5">
                    <span className="px-2 py-0.5 text-[10px] font-semibold rounded-full bg-slate-100 text-slate-600">{item.account_type}</span>
                  </td>
                  <td className="px-4 py-2.5 text-right font-semibold text-slate-800">{formatCurrency(item.balance)}</td>
                </tr>
              ))
            )}
          </tbody>
          <tfoot className="bg-slate-50 border-t-2 border-slate-200">
            <tr>
              <td colSpan={3} className="px-4 py-3 font-bold text-slate-700 text-xs uppercase">Total {title}</td>
              <td className="px-4 py-3 text-right font-bold text-slate-900">{formatCurrency(section.total)}</td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-xl font-bold text-slate-900">Balance Sheet</h1>
          <p className="text-xs text-slate-400">As of {formatDate(data.as_of_date)}</p>
        </div>
        <div className="ml-auto">
          <AsOfDatePicker asOfDate={asOfDate} onChange={setAsOfDate} />
        </div>
        {data.is_balanced && (
          <span className="px-2.5 py-1 text-xs font-semibold rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
            Balanced
          </span>
        )}
      </div>

      {renderSection("Assets", data.assets)}
      {renderSection("Liabilities", data.liabilities)}
      {renderSection("Equity", data.equity)}

      <div className="flex justify-between items-center px-4 py-3 bg-slate-50 rounded-xl border border-slate-200">
        <span className="text-sm font-bold text-slate-700">Total Liabilities &amp; Equity</span>
        <span className="text-sm font-bold text-slate-900">{formatCurrency(data.total_liabilities_and_equity)}</span>
      </div>
    </div>
  );
}

function GSTR3BView({ onBack }: { onBack: () => void }) {
  const today = new Date();
  const firstDayOfMonth = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().split("T")[0];
  const lastDayOfMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).toISOString().split("T")[0];
  const [startDate, setStartDate] = useState(firstDayOfMonth);
  const [endDate, setEndDate] = useState(lastDayOfMonth);

  const { data, isLoading, error } = useQuery<GSTR3BData>({
    queryKey: ["report-gstr3b", startDate, endDate],
    queryFn: async () => {
      const res = await apiClient.get("/reports/gst/gstr3b", { params: { start_date: startDate, end_date: endDate } });
      return res.data;
    },
  });

  if (isLoading) return <LoadingSpinner />;
  if (error || !data) return <ErrorBanner />;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-xl font-bold text-slate-900">GSTR-3B Summary</h1>
          <p className="text-xs text-slate-400">{formatDate(data.period_start)} — {formatDate(data.period_end)}</p>
        </div>
        <div className="ml-auto">
          <DateRangePicker startDate={startDate} endDate={endDate} onStartChange={setStartDate} onEndChange={setEndDate} />
        </div>
      </div>

      <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-4">
        <h2 className="text-xs font-bold uppercase tracking-wider text-slate-400">Outward Taxable Supplies</h2>
        <table className="w-full text-sm border-collapse">
          <thead className="bg-slate-50 text-slate-500 font-semibold text-xs">
            <tr>
              <th className="px-4 py-2.5 text-left">Component</th>
              <th className="px-4 py-2.5 text-right">Amount</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            <tr><td className="px-4 py-2.5 font-semibold text-slate-800">Taxable Value</td><td className="px-4 py-2.5 text-right font-semibold">{formatCurrency(data.outward_taxable_supplies.taxable_value)}</td></tr>
            <tr><td className="px-4 py-2.5 text-slate-600">Integrated Tax (IGST)</td><td className="px-4 py-2.5 text-right">{formatCurrency(data.outward_taxable_supplies.integrated_tax)}</td></tr>
            <tr><td className="px-4 py-2.5 text-slate-600">Central Tax (CGST)</td><td className="px-4 py-2.5 text-right">{formatCurrency(data.outward_taxable_supplies.central_tax)}</td></tr>
            <tr><td className="px-4 py-2.5 text-slate-600">State/UT Tax (SGST)</td><td className="px-4 py-2.5 text-right">{formatCurrency(data.outward_taxable_supplies.state_ut_tax)}</td></tr>
            <tr><td className="px-4 py-2.5 text-slate-600">Cess</td><td className="px-4 py-2.5 text-right">{formatCurrency(data.outward_taxable_supplies.cess)}</td></tr>
          </tbody>
        </table>
      </div>

      <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-4">
        <h2 className="text-xs font-bold uppercase tracking-wider text-slate-400">Net Tax Payable</h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div className="p-4 bg-slate-50 rounded-lg">
            <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">IGST</span>
            <span className="text-lg font-bold text-slate-800 block mt-1">{formatCurrency(data.net_tax_payable_igst)}</span>
          </div>
          <div className="p-4 bg-slate-50 rounded-lg">
            <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">CGST</span>
            <span className="text-lg font-bold text-slate-800 block mt-1">{formatCurrency(data.net_tax_payable_cgst)}</span>
          </div>
          <div className="p-4 bg-slate-50 rounded-lg">
            <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">SGST</span>
            <span className="text-lg font-bold text-slate-800 block mt-1">{formatCurrency(data.net_tax_payable_sgst)}</span>
          </div>
          <div className="p-4 bg-slate-50 rounded-lg">
            <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">Cess</span>
            <span className="text-lg font-bold text-slate-800 block mt-1">{formatCurrency(data.net_tax_payable_cess)}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function CashFlowView({ onBack }: { onBack: () => void }) {
  const today = new Date();
  const firstDayOfYear = new Date(today.getFullYear(), 0, 1).toISOString().split("T")[0];
  const [startDate, setStartDate] = useState(firstDayOfYear);
  const [endDate, setEndDate] = useState(today.toISOString().split("T")[0]);

  const { data, isLoading, error } = useQuery<CashFlowData>({
    queryKey: ["report-cash-flow", startDate, endDate],
    queryFn: async () => {
      const res = await apiClient.get("/reports/cash-flow", { params: { start_date: startDate, end_date: endDate } });
      return res.data;
    },
  });

  if (isLoading) return <LoadingSpinner />;
  if (error || !data) return <ErrorBanner />;

  const renderSection = (title: string, section: CashFlowSection) => (
    <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
      <div className="px-4 py-3 bg-slate-50 border-b border-slate-100">
        <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400">{title}</h3>
      </div>
      <table className="w-full text-sm border-collapse">
        <tbody className="divide-y divide-slate-100">
          {section.items.map((item, idx) => (
            <tr key={idx} className="hover:bg-slate-50/50">
              <td className="px-4 py-2.5 text-slate-700">{item.label}</td>
              <td className="px-4 py-2.5 text-right font-semibold text-slate-800">{formatCurrency(item.amount)}</td>
            </tr>
          ))}
        </tbody>
        <tfoot className="bg-slate-50 border-t-2 border-slate-200">
          <tr>
            <td className="px-4 py-3 font-bold text-slate-700 text-xs uppercase">Net {title}</td>
            <td className="px-4 py-3 text-right font-bold text-slate-900">{formatCurrency(section.net)}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-xl font-bold text-slate-900">Cash Flow Statement</h1>
          <p className="text-xs text-slate-400">{formatDate(data.period_start)} — {formatDate(data.period_end)}</p>
        </div>
        <div className="ml-auto">
          <DateRangePicker startDate={startDate} endDate={endDate} onStartChange={setStartDate} onEndChange={setEndDate} />
        </div>
      </div>

      {renderSection("Operating Activities", data.operating_activities)}
      {renderSection("Investing Activities", data.investing_activities)}
      {renderSection("Financing Activities", data.financing_activities)}

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="p-4 bg-white rounded-xl border border-slate-100 shadow-sm">
          <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">Opening Balance</span>
          <span className="text-lg font-bold text-slate-800 mt-1 block">{formatCurrency(data.opening_cash_balance)}</span>
        </div>
        <div className="p-4 bg-white rounded-xl border border-slate-100 shadow-sm">
          <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">Net Change</span>
          <span className="text-lg font-bold text-slate-800 mt-1 block">{formatCurrency(data.net_change_in_cash)}</span>
        </div>
        <div className="p-4 bg-brand-50 rounded-xl border border-brand-100 shadow-sm">
          <span className="text-[10px] font-bold text-brand-600 uppercase tracking-wider block">Closing Balance</span>
          <span className="text-lg font-bold text-brand-900 mt-1 block">{formatCurrency(data.closing_cash_balance)}</span>
        </div>
      </div>
    </div>
  );
}

function OutstandingInvoicesView({ onBack, type }: { onBack: () => void; type: "receivables" | "payables" }) {
  const endpoint = type === "receivables" ? "/reports/outstanding/receivables" : "/reports/outstanding/payables";
  const queryKey = type === "receivables" ? "report-outstanding-receivables" : "report-outstanding-payables";
  const title = type === "receivables" ? "Outstanding Receivables" : "Outstanding Payables";
  const emptyMsg = type === "receivables" ? "No outstanding receivables." : "No outstanding payables.";

  const today = new Date().toISOString().split("T")[0];
  const [asOfDate, setAsOfDate] = useState(today);

  const { data, isLoading, error } = useQuery<OutstandingARData>({
    queryKey: [queryKey, asOfDate],
    queryFn: async () => {
      const res = await apiClient.get(endpoint, { params: { as_of_date: asOfDate } });
      return res.data;
    },
  });

  if (isLoading) return <LoadingSpinner />;
  if (error || !data) return <ErrorBanner />;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-xl font-bold text-slate-900">{title}</h1>
          <p className="text-xs text-slate-400">As of {formatDate(data.as_of_date)}</p>
        </div>
        <div className="ml-auto">
          <AsOfDatePicker asOfDate={asOfDate} onChange={setAsOfDate} />
        </div>
        <span className="ml-auto text-lg font-bold text-slate-900">{formatCurrency(data.total_outstanding)}</span>
      </div>

      {data.invoices.length === 0 ? (
        <EmptyState icon={DollarSign} title={emptyMsg} />
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">Invoice #</th>
                  <th className="px-6 py-3.5">{type === "receivables" ? "Customer" : "Vendor"}</th>
                  <th className="px-6 py-3.5">Issue Date</th>
                  <th className="px-6 py-3.5">Due Date</th>
                  <th className="px-6 py-3.5 text-right">Total</th>
                  <th className="px-6 py-3.5 text-right">Paid</th>
                  <th className="px-6 py-3.5 text-right">Outstanding</th>
                  <th className="px-6 py-3.5 text-right">Days Overdue</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {data.invoices.map((inv) => (
                  <tr key={inv.invoice_id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-mono font-medium text-brand-900">{inv.invoice_number}</td>
                    <td className="px-6 py-4 font-semibold text-slate-800">{inv.contact_name}</td>
                    <td className="px-6 py-4 text-slate-500">{formatDate(inv.issue_date)}</td>
                    <td className="px-6 py-4 text-slate-500">{formatDate(inv.due_date)}</td>
                    <td className="px-6 py-4 text-right text-slate-600">{formatCurrency(inv.total)}</td>
                    <td className="px-6 py-4 text-right text-slate-500">{formatCurrency(inv.amount_paid)}</td>
                    <td className="px-6 py-4 text-right font-bold text-rose-600">{formatCurrency(inv.outstanding)}</td>
                    <td className="px-6 py-4 text-right">
                      <span className={`px-2 py-0.5 text-xs font-semibold rounded-full ${inv.days_overdue > 30 ? "bg-rose-50 text-rose-700" : inv.days_overdue > 0 ? "bg-amber-50 text-amber-700" : "bg-slate-100 text-slate-500"}`}>
                        {inv.days_overdue > 0 ? `${inv.days_overdue}d` : "Current"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function AgingReportView({ onBack, type }: { onBack: () => void; type: "receivables" | "payables" }) {
  const endpoint = type === "receivables" ? "/reports/aging/receivables" : "/reports/aging/payables";
  const queryKey = type === "receivables" ? "report-aging-receivables" : "report-aging-payables";
  const title = type === "receivables" ? "AR Aging Report" : "AP Aging Report";

  const today = new Date().toISOString().split("T")[0];
  const [asOfDate, setAsOfDate] = useState(today);

  const { data, isLoading, error } = useQuery<AgingReportData>({
    queryKey: [queryKey, asOfDate],
    queryFn: async () => {
      const res = await apiClient.get(endpoint, { params: { as_of_date: asOfDate } });
      return res.data;
    },
  });

  if (isLoading) return <LoadingSpinner />;
  if (error || !data) return <ErrorBanner />;

  const bucketLabels = data.bucket_totals.map((b) => b.label);

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-xl font-bold text-slate-900">{title}</h1>
          <p className="text-xs text-slate-400">As of {formatDate(data.as_of_date)}</p>
        </div>
        <div className="ml-auto">
          <AsOfDatePicker asOfDate={asOfDate} onChange={setAsOfDate} />
        </div>
        <span className="ml-auto text-lg font-bold text-slate-900">{formatCurrency(data.total_outstanding)}</span>
      </div>

      {data.lines.length === 0 ? (
        <EmptyState icon={Clock} title="No aging data available." />
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">{type === "receivables" ? "Customer" : "Vendor"}</th>
                  <th className="px-6 py-3.5 text-right">Total Outstanding</th>
                  {bucketLabels.map((label, idx) => (
                    <th key={idx} className="px-4 py-3.5 text-right">{label}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {data.lines.map((line) => (
                  <tr key={line.contact_id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-semibold text-slate-800">{line.contact_name}</td>
                    <td className="px-6 py-4 text-right font-bold text-slate-800">{formatCurrency(line.total_outstanding)}</td>
                    {line.buckets.map((bucket, idx) => (
                      <td key={idx} className="px-4 py-4 text-right text-slate-600">{formatCurrency(bucket.amount)}</td>
                    ))}
                  </tr>
                ))}
              </tbody>
              <tfoot className="bg-slate-50 border-t-2 border-slate-200 font-semibold">
                <tr>
                  <td className="px-6 py-3.5 text-slate-700 text-xs uppercase">Total</td>
                  <td className="px-6 py-3.5 text-right text-slate-900">{formatCurrency(data.total_outstanding)}</td>
                  {data.bucket_totals.map((bt, idx) => (
                    <td key={idx} className="px-4 py-3.5 text-right text-slate-900">{formatCurrency(bt.amount)}</td>
                  ))}
                </tr>
              </tfoot>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function GenericReportView({ onBack, endpoint, queryKey, title, startDate, endDate }: {
  onBack: () => void;
  endpoint: string;
  queryKey: string;
  title: string;
  startDate?: string;
  endDate?: string;
}) {
  const today = new Date();
  const firstDayOfYear = new Date(today.getFullYear(), 0, 1).toISOString().split("T")[0];
  const firstDayOfMonth = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().split("T")[0];
  const lastDayOfMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).toISOString().split("T")[0];

  const [localStartDate, setLocalStartDate] = useState(startDate || firstDayOfMonth);
  const [localEndDate, setLocalEndDate] = useState(endDate || lastDayOfMonth);
  const activeStart = startDate ?? localStartDate;
  const activeEnd = endDate ?? localEndDate;

  const { data, isLoading, error } = useQuery<any>({
    queryKey: [queryKey, activeStart, activeEnd],
    queryFn: async () => {
      const res = await apiClient.get(endpoint, { params: { start_date: activeStart, end_date: activeEnd } });
      return res.data;
    },
  });

  if (isLoading) return <LoadingSpinner />;
  if (error) return <ErrorBanner />;
  if (!data) return <EmptyState icon={BarChart3} title="No data available." />;

  const renderData = (obj: any, depth = 0): React.JSX.Element => {
    if (depth > 2) return <span className="text-slate-600 text-xs">{String(obj)}</span>;

    if (Array.isArray(obj)) {
      if (obj.length === 0) return <span className="text-slate-400 text-xs">No data</span>;
      const keys = Object.keys(obj[0] || {});
      return (
        <div className="overflow-x-auto">
          <table className="w-full text-xs border-collapse">
            <thead className="bg-slate-50 text-slate-500 font-semibold">
              <tr>
                {keys.map((k) => (
                  <th key={k} className="px-3 py-2 text-left">{k.replace(/_/g, " ")}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {obj.map((row: any, idx: number) => (
                <tr key={idx} className="hover:bg-slate-50/50">
                  {keys.map((k) => (
                    <td key={k} className="px-3 py-2 text-slate-700">
                      {typeof row[k] === "number" ? formatCurrency(row[k]) : String(row[k] ?? "")}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    }

    if (typeof obj === "object" && obj !== null) {
      return (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {Object.entries(obj).map(([key, val]) => (
            <div key={key} className="p-3 bg-slate-50 rounded-lg">
              <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">{key.replace(/_/g, " ")}</span>
              <span className="text-sm font-bold text-slate-800 mt-0.5 block">
                {typeof val === "number" ? formatCurrency(val) : Array.isArray(val) || typeof val === "object" ? "—" : String(val ?? "")}
              </span>
            </div>
          ))}
        </div>
      );
    }

    return <span className="text-slate-600">{String(obj)}</span>;
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-xl font-bold text-slate-900">{title}</h1>
        {!startDate && (
          <div className="ml-auto">
            <DateRangePicker startDate={localStartDate} endDate={localEndDate} onStartChange={setLocalStartDate} onEndChange={setLocalEndDate} />
          </div>
        )}
      </div>
      <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
        {renderData(data)}
      </div>
    </div>
  );
}

export default function ReportsDashboard({ onNavigate: _onNavigate }: ReportsDashboardProps) {
  const [activeReport, setActiveReport] = useState<ReportView | null>(null);

  if (!activeReport) {
    return <DashboardGrid onSelect={setActiveReport} />;
  }

  const handleBack = () => setActiveReport(null);

  switch (activeReport) {
    case "balance_sheet":
      return <BalanceSheetView onBack={handleBack} />;
    case "gstr3b":
      return <GSTR3BView onBack={handleBack} />;
    case "cash_flow":
      return <CashFlowView onBack={handleBack} />;
    case "outstanding_receivables":
      return <OutstandingInvoicesView onBack={handleBack} type="receivables" />;
    case "outstanding_payables":
      return <OutstandingInvoicesView onBack={handleBack} type="payables" />;
    case "aging_receivables":
      return <AgingReportView onBack={handleBack} type="receivables" />;
    case "aging_payables":
      return <AgingReportView onBack={handleBack} type="payables" />;
    case "gstr1":
      return <GenericReportView onBack={handleBack} endpoint="/reports/gst/gstr1" queryKey="report-gstr1" title="GSTR-1" />;
    case "sales_analytics":
      return <GenericReportView onBack={handleBack} endpoint="/reports/analytics/sales" queryKey="report-sales-analytics" title="Sales Analytics" />;
    case "purchase_analytics":
      return <GenericReportView onBack={handleBack} endpoint="/reports/analytics/purchases" queryKey="report-purchase-analytics" title="Purchase Analytics" />;
    default:
      return <DashboardGrid onSelect={setActiveReport} />;
  }
}
