import React, { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Plus, Clock, CheckCircle, XCircle } from "lucide-react";

interface SchedulerViewProps {
  onNavigate: (view: any) => void;
}

interface Reminder {
  id: string;
  title: string;
  description?: string;
  due_date: string;
  status: string;
  related_type?: string;
  related_id?: string;
}

export default function SchedulerView({ onNavigate }: SchedulerViewProps) {
  const queryClient = useQueryClient();

  const { data: reminders = [] } = useQuery<Reminder[]>({
    queryKey: ["reminders"],
    queryFn: async () => {
      const res = await apiClient.get("/reminders");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const createMutation = useMutation({
    mutationFn: async (data: { title: string; due_date: string; description?: string }) => {
      await apiClient.post("/reminders", data);
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["reminders"] }),
  });

  const [showForm, setShowForm] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [newDate, setNewDate] = useState(new Date().toISOString().split("T")[0]);
  const [newDesc, setNewDesc] = useState("");

  const today = new Date().toISOString().split("T")[0];
  const upcoming = reminders.filter((r) => r.due_date >= today).sort((a, b) => a.due_date.localeCompare(b.due_date));
  const overdue = reminders.filter((r) => r.due_date < today && r.status !== "COMPLETED");
  const completed = reminders.filter((r) => r.status === "COMPLETED");

  const formatDate = (d: string) => {
    const date = new Date(d);
    return date.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
  };

  const isToday = (d: string) => d === today;
  const isTomorrow = (d: string) => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    return d === tomorrow.toISOString().split("T")[0];
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3 pb-4 border-b border-zinc-200/60">
        <button
          onClick={() => onNavigate("sales_dashboard")}
          className="p-1 text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 rounded-lg transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1">
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Reminders</h1>
          <p className="text-xs text-zinc-500 mt-0.5">Payment reminders, follow-ups, and due dates.</p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition"
        >
          <Plus className="w-4 h-4" />
          Add Reminder
        </button>
      </div>

      {showForm && (
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-5 space-y-4">
          <h3 className="text-sm font-bold text-zinc-800">New Reminder</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <input
              type="text"
              value={newTitle}
              onChange={(e) => setNewTitle(e.target.value)}
              placeholder="Reminder title"
              className="px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
            <input
              type="date"
              value={newDate}
              onChange={(e) => setNewDate(e.target.value)}
              className="px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
            <div className="flex gap-2">
              <input
                type="text"
                value={newDesc}
                onChange={(e) => setNewDesc(e.target.value)}
                placeholder="Optional description"
                className="flex-1 px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              />
              <button
                onClick={() => {
                  if (!newTitle.trim() || !newDate) return;
                  createMutation.mutate({ title: newTitle, due_date: newDate, description: newDesc || undefined });
                  setNewTitle("");
                  setNewDate(new Date().toISOString().split("T")[0]);
                  setNewDesc("");
                  setShowForm(false);
                }}
                className="px-4 py-2 bg-brand-600 text-white rounded-lg text-sm font-semibold hover:bg-brand-700 transition"
              >
                Save
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Upcoming */}
        <div className="lg:col-span-2 space-y-4">
          <h2 className="text-sm font-bold text-zinc-800 flex items-center gap-2">
            <Clock className="w-4 h-4 text-brand-600" />
            Upcoming
          </h2>
          {upcoming.length === 0 ? (
            <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-8 text-center text-sm text-zinc-400">
              No upcoming reminders
            </div>
          ) : (
            <div className="space-y-2">
              {upcoming.map((r) => (
                <div key={r.id} className="bg-white rounded-xl border border-slate-100 shadow-sm p-4 flex items-start gap-3">
                  <div className={`mt-0.5 w-2 h-2 rounded-full shrink-0 ${isToday(r.due_date) ? "bg-red-500" : isTomorrow(r.due_date) ? "bg-amber-500" : "bg-brand-500"}`} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-zinc-800 truncate">{r.title}</p>
                    {r.description && <p className="text-xs text-zinc-400 mt-0.5 truncate">{r.description}</p>}
                  </div>
                  <span className={`text-xs font-medium shrink-0 ${isToday(r.due_date) ? "text-red-600" : isTomorrow(r.due_date) ? "text-amber-600" : "text-zinc-400"}`}>
                    {isToday(r.due_date) ? "Today" : isTomorrow(r.due_date) ? "Tomorrow" : formatDate(r.due_date)}
                  </span>
                </div>
              ))}
            </div>
          )}

          {/* Overdue */}
          {overdue.length > 0 && (
            <>
              <h2 className="text-sm font-bold text-red-600 flex items-center gap-2 pt-2">
                <XCircle className="w-4 h-4" />
                Overdue ({overdue.length})
              </h2>
              <div className="space-y-2">
                {overdue.map((r) => (
                  <div key={r.id} className="bg-white rounded-xl border border-red-100 shadow-sm p-4 flex items-start gap-3">
                    <div className="mt-0.5 w-2 h-2 rounded-full shrink-0 bg-red-500" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-zinc-800 truncate">{r.title}</p>
                      {r.description && <p className="text-xs text-zinc-400 mt-0.5 truncate">{r.description}</p>}
                    </div>
                    <span className="text-xs font-medium text-red-600 shrink-0">{formatDate(r.due_date)}</span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>

        {/* Completed */}
        <div className="space-y-4">
          <h2 className="text-sm font-bold text-zinc-800 flex items-center gap-2">
            <CheckCircle className="w-4 h-4 text-green-600" />
            Completed
          </h2>
          {completed.length === 0 ? (
            <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-8 text-center text-sm text-zinc-400">
              No completed reminders
            </div>
          ) : (
            <div className="space-y-2">
              {completed.map((r) => (
                <div key={r.id} className="bg-white rounded-xl border border-slate-100 shadow-sm p-4 flex items-start gap-3 opacity-60">
                  <div className="mt-0.5 w-2 h-2 rounded-full shrink-0 bg-green-500" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-zinc-800 truncate line-through">{r.title}</p>
                    {r.description && <p className="text-xs text-zinc-400 mt-0.5 truncate">{r.description}</p>}
                  </div>
                  <span className="text-xs font-medium text-zinc-400 shrink-0">{formatDate(r.due_date)}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
