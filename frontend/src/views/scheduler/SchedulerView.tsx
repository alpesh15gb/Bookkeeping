import React, { Suspense, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Plus } from "lucide-react";
import "../../lib/syncfusion";

const ScheduleInternal = React.lazy(() => import("./ScheduleInternal"));

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

  const events = reminders.map((r) => ({
    Id: r.id,
    Subject: r.title,
    Description: r.description || "",
    StartTime: new Date(r.due_date),
    EndTime: new Date(new Date(r.due_date).getTime() + 60 * 60 * 1000),
    IsAllDay: true,
    Status: r.status,
  }));

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
          <h1 className="text-xl font-bold tracking-tight text-zinc-900">Reminders & Schedule</h1>
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

      <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden ej-schedule-custom">
        <Suspense
          fallback={
            <div className="flex justify-center items-center py-20">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" />
            </div>
          }
        >
          <ScheduleInternal events={events} />
        </Suspense>
      </div>
    </div>
  );
}
