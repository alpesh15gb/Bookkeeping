import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, Receipt, Eye, Edit, ShieldAlert } from "lucide-react";

interface BillListProps {
  onNavigate: (view: "bill_list" | "bill_create" | "bill_edit" | "bill_detail", billId?: string) => void;
}

interface BillListItem {
  id: string;
  bill_number: string;
  issue_date: string;
  due_date: string;
  status: string;
  total: number;
  amount_paid: number;
  contact_name: string;
  created_at: string;
}

export default function BillList({ onNavigate }: BillListProps) {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("ALL");

  // Fetch Vendor Bills using TanStack Query
  const { data: bills = [], isLoading, error } = useQuery<BillListItem[]>({
    queryKey: ["bills"],
    queryFn: async () => {
      const res = await apiClient.get("/bills");
      return res.data;
    },
  });

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
    }).format(amount);
  };

  const getStatusBadge = (status: string) => {
    const s = status.toUpperCase();
    if (s === "DRAFT") return <span className="badge badge-draft">Draft</span>;
    if (s === "UNPAID") return <span className="badge badge-unpaid">Unpaid</span>;
    if (s === "PARTIALLY_PAID") return <span className="badge badge-partially_paid">Partially Paid</span>;
    if (s === "PAID") return <span className="badge badge-paid">Paid</span>;
    if (s === "CANCELLED") return <span className="badge badge-cancelled">Cancelled</span>;
    return <span className="badge badge-draft">{status}</span>;
  };

  // Filter list locally
  const filteredBills = bills.filter((bill) => {
    const matchesSearch =
      bill.bill_number.toLowerCase().includes(search.toLowerCase()) ||
      bill.contact_name.toLowerCase().includes(search.toLowerCase());
    const matchesStatus = statusFilter === "ALL" || bill.status.toUpperCase() === statusFilter;
    return matchesSearch && matchesStatus;
  });

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 pb-4 border-b border-zinc-200/60">
        <div>
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Vendor Bills</h1>
          <p className="text-xs text-zinc-500 mt-1">Record purchases, input tax credits (ITC), and disbursements.</p>
        </div>
        <button
          onClick={() => onNavigate("bill_create")}
          className="btn-primary"
        >
          <Plus className="w-4 h-4" />
          Record Vendor Bill
        </button>
      </div>

      {/* Filter Toolbar */}
      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-lg shadow-sm border border-zinc-200/80">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4.5 w-4.5 text-zinc-400" />
          <input
            type="text"
            placeholder="Search by bill number or vendor name..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="form-input pl-10 pr-4"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="form-select sm:w-48"
        >
          <option value="ALL">All Statuses</option>
          <option value="DRAFT">Draft</option>
          <option value="UNPAID">Unpaid</option>
          <option value="PARTIALLY_PAID">Partially Paid</option>
          <option value="PAID">Paid</option>
        </select>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-zinc-800"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span className="text-xs font-semibold">Error loading vendor bills from API engine.</span>
        </div>
      ) : filteredBills.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-lg border border-zinc-200/80 shadow-sm">
          <Receipt className="w-12 h-12 text-zinc-300 mx-auto mb-3" />
          <h3 className="text-xs font-semibold text-zinc-700 uppercase tracking-wider">No Bills Found</h3>
          <p className="text-xs text-zinc-400 mt-1">Log a vendor bill to manage your purchases and track GST input taxes.</p>
        </div>
      ) : (
        <div className="bg-white rounded-lg shadow-sm border border-zinc-200/80 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="financial-table">
              <thead>
                <tr>
                  <th>Bill Number</th>
                  <th>Vendor</th>
                  <th>Issue Date</th>
                  <th>Due Date</th>
                  <th className="text-right">Total Bill</th>
                  <th className="text-right">Paid</th>
                  <th>Status</th>
                  <th className="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredBills.map((b) => (
                  <tr key={b.id}>
                    <td className="font-mono font-medium text-zinc-900">{b.bill_number}</td>
                    <td className="font-semibold text-zinc-800">{b.contact_name}</td>
                    <td className="text-zinc-500 text-xs">{new Date(b.issue_date).toLocaleDateString("en-IN")}</td>
                    <td className="text-zinc-500 text-xs">{new Date(b.due_date).toLocaleDateString("en-IN")}</td>
                    <td className="numeric-val font-semibold">{formatCurrency(b.total)}</td>
                    <td className="numeric-val text-zinc-500">{formatCurrency(b.amount_paid)}</td>
                    <td>{getStatusBadge(b.status)}</td>
                    <td className="text-right">
                      <div className="inline-flex items-center gap-2 justify-end">
                        <button
                          onClick={() => onNavigate("bill_detail", b.id)}
                          title="View Details"
                          className="p-1 text-zinc-400 hover:text-zinc-800 hover:bg-zinc-100 rounded transition"
                        >
                          <Eye className="w-3.5 h-3.5" />
                        </button>
                        {b.status.toUpperCase() === "DRAFT" && (
                          <button
                            onClick={() => onNavigate("bill_edit", b.id)}
                            title="Edit Draft"
                            className="p-1 text-zinc-400 hover:text-amber-700 hover:bg-amber-50 rounded transition"
                          >
                            <Edit className="w-3.5 h-3.5" />
                          </button>
                        )}
                      </div>
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
