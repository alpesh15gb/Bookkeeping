import React from "react";
import LoadingSpinner from "./LoadingSpinner";
import EmptyState from "./EmptyState";
import { FileText } from "lucide-react";

export interface Column<T = any> {
  key: string;
  header: string;
  render?: (value: any, row: T) => React.ReactNode;
  align?: "left" | "right" | "center";
  width?: string;
  mono?: boolean;
}

interface DataTableProps<T = any> {
  columns: Column<T>[];
  data: T[];
  loading?: boolean;
  emptyTitle?: string;
  emptyDescription?: string;
  emptyAction?: { label: string; onClick: () => void };
  onRowClick?: (row: T) => void;
  rowKey?: (row: T) => string;
  className?: string;
}

export default function DataTable<T = any>({
  columns,
  data,
  loading = false,
  emptyTitle = "No data found",
  emptyDescription,
  emptyAction,
  onRowClick,
  rowKey,
  className = "",
}: DataTableProps<T>) {
  if (loading) {
    return (
      <div className="bg-white rounded-xl border border-zinc-200">
        <LoadingSpinner message="Loading data..." />
      </div>
    );
  }

  if (!data || data.length === 0) {
    return (
      <div className="bg-white rounded-xl border border-zinc-200">
        <EmptyState
          icon={FileText}
          title={emptyTitle}
          description={emptyDescription}
          action={emptyAction}
        />
      </div>
    );
  }

  const alignClass = (align?: string) => {
    if (align === "right") return "text-right";
    if (align === "center") return "text-center";
    return "text-left";
  };

  return (
    <div className={`bg-white rounded-xl border border-zinc-200 overflow-hidden ${className}`}>
      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-left text-sm">
          <thead>
            <tr className="bg-zinc-50 border-b border-zinc-200">
              {columns.map((col, i) => (
                <th
                  key={col.key}
                  className={`px-6 py-3 text-[11px] font-semibold uppercase tracking-wider text-zinc-500 ${alignClass(col.align)}`}
                  style={col.width ? { width: col.width } : undefined}
                >
                  {col.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-zinc-100">
            {data.map((row, rowIdx) => {
              const key = rowKey ? rowKey(row) : String(rowIdx);
              return (
                <tr
                  key={key}
                  onClick={() => onRowClick?.(row)}
                  className={`transition-colors duration-100 ${
                    onRowClick ? "cursor-pointer hover:bg-surface-hover" : "hover:bg-zinc-50/50"
                  }`}
                >
                  {columns.map((col) => {
                    const value = (row as any)[col.key];
                    const cellContent = col.render ? col.render(value, row) : value ?? "—";
                    const monoClass = col.mono ? "font-mono font-medium" : "";
                    return (
                      <td
                        key={col.key}
                        className={`px-6 py-4 text-sm ${alignClass(col.align)} ${monoClass} text-zinc-800`}
                      >
                        {cellContent}
                      </td>
                    );
                  })}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
