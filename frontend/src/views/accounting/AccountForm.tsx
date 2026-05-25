import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, AlertCircle } from "lucide-react";

interface AccountFormProps {
  editId?: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail", accountId?: string) => void;
  onSuccess: () => void;
}

interface AccountOption {
  id: string;
  name: string;
  code: string;
  account_type: string;
}

const ACCOUNT_TYPE_OPTIONS = ["ASSET", "LIABILITY", "EQUITY", "REVENUE", "EXPENSE"];

export default function AccountForm({ editId, onNavigate, onSuccess }: AccountFormProps) {
  const isEdit = !!editId;

  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [accountType, setAccountType] = useState("ASSET");
  const [parentId, setParentId] = useState("");
  const [openingBalance, setOpeningBalance] = useState(0);
  const [formError, setFormError] = useState("");

  const { data: accountsList = [] } = useQuery<AccountOption[]>({
    queryKey: ["accounts"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/accounts");
      return res.data;
    },
  });

  const { data: account } = useQuery({
    queryKey: ["account", editId],
    queryFn: async () => {
      const res = await apiClient.get(`/masters/accounts/${editId}`);
      return res.data;
    },
    enabled: isEdit,
  });

  useEffect(() => {
    if (account && isEdit) {
      setName(account.name);
      setCode(account.code);
      setAccountType(account.account_type);
      setParentId(account.parent_id || "");
      setOpeningBalance(account.opening_balance);
    }
  }, [account, isEdit]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        name,
        code,
        account_type: accountType,
        parent_id: parentId || null,
        opening_balance: openingBalance,
      };

      if (isEdit) {
        return apiClient.put(`/masters/accounts/${editId}`, payload);
      } else {
        return apiClient.post("/masters/accounts", payload);
      }
    },
    onSuccess: () => {
      onSuccess();
    },
    onError: (err: any) => {
      const msg = err.response?.data?.detail || "Failed to save account. Ensure API parameters are valid.";
      setFormError(msg);
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    if (!name.trim()) {
      setFormError("Account name is required.");
      return;
    }
    if (!code.trim()) {
      setFormError("Account code is required.");
      return;
    }
    if (!accountType) {
      setFormError("Account type is required.");
      return;
    }

    saveMutation.mutate();
  };

  const parentOptions = accountsList.filter((a) => a.id !== editId);

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => onNavigate("list")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">
          {isEdit ? "Edit Account" : "Create Account"}
        </h1>
      </div>

      {formError && (
        <div className="flex items-start gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-sm">
            <span className="font-semibold">Error:</span> {formError}
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Account Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Cash in Hand"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Account Code</label>
            <input
              type="text"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="e.g. 1010"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Account Type</label>
            <select
              value={accountType}
              onChange={(e) => setAccountType(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            >
              {ACCOUNT_TYPE_OPTIONS.map((t) => (
                <option key={t} value={t}>
                  {t.charAt(0) + t.slice(1).toLowerCase()}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Parent Account</label>
            <select
              value={parentId}
              onChange={(e) => setParentId(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              <option value="">-- None (Top Level) --</option>
              {parentOptions.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} ({a.code}) — {a.account_type}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Opening Balance (₹)</label>
            <input
              type="number"
              step="0.01"
              value={openingBalance}
              onChange={(e) => setOpeningBalance(parseFloat(e.target.value) || 0)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>
        </div>

        <div className="flex justify-end gap-3">
          <button
            type="button"
            onClick={() => onNavigate("list")}
            className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saveMutation.isPending}
            className="px-6 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50"
          >
            {saveMutation.isPending ? "Saving..." : isEdit ? "Update Account" : "Create Account"}
          </button>
        </div>
      </form>
    </div>
  );
}
