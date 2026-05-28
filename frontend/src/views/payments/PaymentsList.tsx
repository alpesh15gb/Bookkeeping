import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Eye, ArrowDownCircle, ArrowUpCircle } from "lucide-react";
import { useState } from "react";
import PageHeader from "../../components/PageHeader";
import Toolbar from "../../components/Toolbar";
import DataTable, { Column } from "../../components/DataTable";
import StatusBadge from "../../components/StatusBadge";
import AmountText from "../../components/AmountText";
import { formatDate } from "../../lib/utils";

interface PaymentsListProps {
  onNavigate: (view: "payments" | "payment_receipt" | "payment_disbursement", id?: string) => void;
}

interface ReceiptItem {
  id: string;
  receipt_number: string;
  payment_date: string;
  contact_name: string;
  payment_mode: string;
  amount: number;
  status: string;
}

interface DisbursementItem {
  id: string;
  payment_number: string;
  payment_date: string;
  contact_name: string;
  payment_mode: string;
  amount: number;
  status: string;
}

export default function PaymentsList({ onNavigate }: PaymentsListProps) {
  const [activeTab, setActiveTab] = useState<"receipts" | "disbursements">("receipts");

  const { data: receipts = [], isLoading: rLoading } = useQuery<ReceiptItem[]>({
    queryKey: ["payments-receipts"],
    queryFn: async () => { const r = await apiClient.get("/payments/receipts"); return Array.isArray(r.data) ? r.data : []; },
  });

  const { data: disbursements = [], isLoading: dLoading } = useQuery<DisbursementItem[]>({
    queryKey: ["payments-disbursements"],
    queryFn: async () => { const r = await apiClient.get("/payments/disbursements"); return Array.isArray(r.data) ? r.data : []; },
  });

  const isReceipts = activeTab === "receipts";
  const data: (ReceiptItem | DisbursementItem)[] = isReceipts ? receipts : disbursements;
  const isLoading = isReceipts ? rLoading : dLoading;

  const columns: Column<ReceiptItem | DisbursementItem>[] = [
    {
      key: "receipt_number",
      header: "Number",
      mono: true,
      width: "140px",
      render: (_val, row) => {
        const num = isReceipts ? (row as ReceiptItem).receipt_number : (row as DisbursementItem).payment_number;
        return <span className="font-mono font-medium text-zinc-800">{num}</span>;
      },
    },
    { key: "payment_date", header: "Date", width: "110px", render: (val) => <span className="text-zinc-500">{formatDate(val)}</span> },
    { key: "contact_name", header: "Party", render: (val) => <span className="font-medium">{val || "—"}</span> },
    {
      key: "payment_mode",
      header: "Mode",
      align: "center",
      width: "100px",
      render: (val) => <StatusBadge status={val} variant="info" className="font-mono" />,
    },
    {
      key: "amount",
      header: "Amount",
      align: "right",
      mono: true,
      render: (val, row) => {
        const prefix = isReceipts ? "+" : "−";
        return <AmountText value={isReceipts ? val : -Math.abs(Number(val))} colored />;
      },
    },
    { key: "status", header: "Status", align: "center", width: "110px", render: (val) => <StatusBadge status={val} /> },
    {
      key: "id", header: "", width: "80px", align: "center",
      render: (_val, row) => (
        <button
          onClick={(e) => { e.stopPropagation(); onNavigate(isReceipts ? "payment_receipt" : "payment_disbursement", row.id); }}
          className="px-2.5 py-1 text-[11px] font-semibold text-blue-600 bg-blue-50 border border-blue-200 rounded-lg hover:bg-blue-100 transition inline-flex items-center gap-1"
        >
          <Eye className="w-3 h-3" /> View
        </button>
      ),
    },
  ];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Payments"
        subtitle="Track customer receipts and vendor disbursements"
        actions={[
          {
            label: isReceipts ? "Receive Payment" : "Make Payment",
            icon: <Plus className="w-4 h-4" />,
            onClick: () => onNavigate(isReceipts ? "payment_receipt" : "payment_disbursement"),
          },
        ]}
      />
      <Toolbar
        filters={[{
          label: "Type",
          selected: activeTab,
          options: [
            { label: "Receipts", value: "receipts" },
            { label: "Disbursements", value: "disbursements" },
          ],
          onChange: (v) => v && setActiveTab(v as "receipts" | "disbursements"),
        }]}
      />
      <DataTable
        columns={columns}
        data={data}
        loading={isLoading}
        emptyTitle={`No ${isReceipts ? "receipts" : "disbursements"} found`}
        emptyDescription={isReceipts ? "Record your first payment receipt." : "Log your first vendor payment."}
        emptyAction={{ label: isReceipts ? "Receive Payment" : "Make Payment", onClick: () => onNavigate(isReceipts ? "payment_receipt" : "payment_disbursement") }}
        onRowClick={(row) => onNavigate(isReceipts ? "payment_receipt" : "payment_disbursement", row.id)}
        rowKey={(row) => row.id}
      />
    </div>
  );
}
