import React, { useEffect, useState, useRef } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Save, Plus, Trash2 } from "lucide-react";

interface JournalEntryViewProps {
  onNavigate: (view: any) => void;
}

interface JournalLine {
  id: string;
  account_id: string;
  account_name: string;
  debit: number;
  credit: number;
  narration: string;
}

const emptyLine = (): JournalLine => ({
  id: crypto.randomUUID(),
  account_id: "",
  account_name: "",
  debit: 0,
  credit: 0,
  narration: "",
});

export default function JournalEntryView({ onNavigate }: JournalEntryViewProps) {
  const [entryDate, setEntryDate] = useState(new Date().toISOString().split("T")[0]);
  const [referenceNumber, setReferenceNumber] = useState("");
  const [description, setDescription] = useState("");
  const [lines, setLines] = useState<JournalLine[]>([emptyLine(), emptyLine()]);
  const [error, setError] = useState("");
  const queryClient = useQueryClient();

  const { data: accounts = [] } = useQuery<{ id: string; name: string; account_type: string }[]>({
    queryKey: ["masters-accounts"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/accounts");
      return res.data;
    },
  });

  const totalDebit = lines.reduce((s, l) => s + (l.debit || 0), 0);
  const totalCredit = lines.reduce((s, l) => s + (l.credit || 0), 0);
  const isBalanced = Math.abs(totalDebit - totalCredit) < 0.01;

  const addLine = () => setLines([...lines, emptyLine()]);
  const removeLine = (id: string) => {
    if (lines.length <= 2) return;
    setLines(lines.filter((l) => l.id !== id));
  };

  const updateLine = (id: string, field: keyof JournalLine, value: any) => {
    setLines(lines.map((l) => (l.id === id ? { ...l, [field]: value } : l)));
  };

  const saveMutation = useMutation({
    mutationFn: async () => {
      if (!isBalanced) throw new Error("Debit and credit totals must be equal.");
      if (lines.some((l) => !l.account_id)) throw new Error("All lines must have an account selected.");
      const payload = {
        entry_date: entryDate,
        reference_number: referenceNumber || undefined,
        description: description || "Manual Journal Entry",
        lines: lines.map((l) => ({
          account_id: l.account_id,
          amount: l.debit || l.credit,
          direction: l.debit > 0 ? "DEBIT" : "CREDIT",
          narration: l.narration || undefined,
        })),
      };
      await apiClient.post("/accounting/journal-entries", payload);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["accounting"] });
      onNavigate("accounts");
    },
    onError: (err: any) => setError(err.response?.data?.detail || err.message),
  });

  return (
    <div className="max-w-5xl mx-auto space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button
          onClick={() => onNavigate("accounts")}
          className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1">
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Journal Entry</h1>
          <p className="text-xs text-zinc-500 mt-0.5">Record a double-entry manual journal voucher.</p>
        </div>
        <button
          onClick={() => saveMutation.mutate()}
          disabled={saveMutation.isPending}
          className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition disabled:opacity-50"
        >
          <Save className="w-4 h-4" />
          {saveMutation.isPending ? "Posting..." : "Post Entry"}
        </button>
      </div>

      {error && (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg text-sm">
          {error}
        </div>
      )}

      {/* Entry Header */}
      <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-5 space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="space-y-1.5">
            <label className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">Entry Date</label>
            <input
              type="date"
              value={entryDate}
              onChange={(e) => setEntryDate(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>
          <div className="space-y-1.5">
            <label className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">Reference #</label>
            <input
              type="text"
              value={referenceNumber}
              onChange={(e) => setReferenceNumber(e.target.value)}
              placeholder="Optional"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>
          <div className="space-y-1.5">
            <label className="text-[10px] font-bold text-slate-500 uppercase tracking-wider">Description</label>
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Journal description"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>
        </div>
      </div>

      {/* Journal Lines */}
      <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-left text-sm">
            <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
              <tr>
                <th className="px-4 py-3 text-[10px] uppercase tracking-wider">#</th>
                <th className="px-4 py-3 text-[10px] uppercase tracking-wider">Account</th>
                <th className="px-4 py-3 text-[10px] uppercase tracking-wider">Debit</th>
                <th className="px-4 py-3 text-[10px] uppercase tracking-wider">Credit</th>
                <th className="px-4 py-3 text-[10px] uppercase tracking-wider">Narration</th>
                <th className="px-4 py-3 text-[10px] uppercase tracking-wider w-10"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {lines.map((line, index) => (
                <tr key={line.id} className="hover:bg-slate-50/50 transition">
                  <td className="px-4 py-2 text-slate-400 text-xs font-mono">{index + 1}</td>
                  <td className="px-4 py-2">
                    <select
                      value={line.account_id}
                      onChange={(e) => {
                        const selected = accounts.find((a) => a.id === e.target.value);
                        updateLine(line.id, "account_id", e.target.value);
                        updateLine(line.id, "account_name", selected ? `${selected.name} (${selected.account_type})` : "");
                      }}
                      className="w-full px-2 py-1.5 border border-slate-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-brand-500"
                    >
                      <option value="">-- Select Account --</option>
                      {accounts.map((acct) => (
                        <option key={acct.id} value={acct.id}>
                          {acct.name} ({acct.account_type})
                        </option>
                      ))}
                    </select>
                  </td>
                  <td className="px-4 py-2">
                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      value={line.debit || ""}
                      onChange={(e) => {
                        updateLine(line.id, "debit", parseFloat(e.target.value) || 0);
                        if (parseFloat(e.target.value) > 0) updateLine(line.id, "credit", 0);
                      }}
                      placeholder="0.00"
                      className="w-full px-2 py-1.5 border border-slate-200 rounded text-xs font-mono text-right focus:outline-none focus:ring-1 focus:ring-brand-500"
                    />
                  </td>
                  <td className="px-4 py-2">
                    <input
                      type="number"
                      min="0"
                      step="0.01"
                      value={line.credit || ""}
                      onChange={(e) => {
                        updateLine(line.id, "credit", parseFloat(e.target.value) || 0);
                        if (parseFloat(e.target.value) > 0) updateLine(line.id, "debit", 0);
                      }}
                      placeholder="0.00"
                      className="w-full px-2 py-1.5 border border-slate-200 rounded text-xs font-mono text-right focus:outline-none focus:ring-1 focus:ring-brand-500"
                    />
                  </td>
                  <td className="px-4 py-2">
                    <input
                      type="text"
                      value={line.narration}
                      onChange={(e) => updateLine(line.id, "narration", e.target.value)}
                      placeholder="Optional"
                      className="w-full px-2 py-1.5 border border-slate-200 rounded text-xs focus:outline-none focus:ring-1 focus:ring-brand-500"
                    />
                  </td>
                  <td className="px-4 py-2">
                    <button
                      onClick={() => removeLine(line.id)}
                      disabled={lines.length <= 2}
                      className="p-1 text-slate-300 hover:text-red-500 disabled:opacity-30 transition"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot className="bg-slate-50 border-t-2 border-slate-200">
              <tr>
                <td colSpan={2} className="px-4 py-3 text-xs font-bold text-slate-600">Totals</td>
                <td className={`px-4 py-3 text-right font-mono font-bold text-xs ${totalDebit > 0 ? "text-zinc-800" : "text-slate-400"}`}>
                  {totalDebit.toFixed(2)}
                </td>
                <td className={`px-4 py-3 text-right font-mono font-bold text-xs ${totalCredit > 0 ? "text-zinc-800" : "text-slate-400"}`}>
                  {totalCredit.toFixed(2)}
                </td>
                <td colSpan={2} className="px-4 py-3">
                  {!isBalanced && totalDebit + totalCredit > 0 && (
                    <span className="text-[10px] font-bold text-rose-600">Difference: {(totalDebit - totalCredit).toFixed(2)}</span>
                  )}
                  {isBalanced && totalDebit > 0 && (
                    <span className="text-[10px] font-bold text-emerald-600">Balanced ✓</span>
                  )}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>
        <div className="px-4 py-3 border-t border-slate-100 flex items-center gap-2">
          <button
            onClick={addLine}
            className="inline-flex items-center gap-1 px-3 py-1.5 border border-slate-200 bg-white text-slate-700 rounded-lg text-xs font-semibold hover:bg-slate-50 transition"
          >
            <Plus className="w-3.5 h-3.5" /> Add Line
          </button>
        </div>
      </div>
    </div>
  );
}
