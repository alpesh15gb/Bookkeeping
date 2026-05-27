import React from "react";

interface DashboardSkeletonProps {
  cards?: number;
}

export default function DashboardSkeleton({ cards = 4 }: DashboardSkeletonProps) {
  return (
    <div className="space-y-6 animate-pulse">
      <div className="h-8 w-48 bg-slate-200 rounded-lg" />
      <div className="h-4 w-72 bg-slate-100 rounded" />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {Array.from({ length: cards }).map((_, i) => (
          <div key={i} className="bg-white border border-slate-100 rounded-xl p-4 shadow-sm">
            <div className="flex items-start gap-3">
              <div className="p-2 bg-slate-100 rounded-xl w-10 h-10" />
              <div className="flex-1 space-y-2">
                <div className="h-3 w-16 bg-slate-200 rounded" />
                <div className="h-6 w-28 bg-slate-200 rounded" />
                <div className="h-3 w-20 bg-slate-100 rounded" />
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
