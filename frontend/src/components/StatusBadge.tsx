import React from "react";

type BadgeVariant = "success" | "warning" | "danger" | "info" | "gray" | "draft" | "posted" | "paid" | "partial" | "cancelled" | "overdue" | "active" | "inactive" | "issued" | "pending";

interface StatusBadgeProps {
  status: string;
  variant?: BadgeVariant;
  className?: string;
}

const VARIANT_CLASSES: Record<BadgeVariant, string> = {
  success:   "bg-emerald-50 text-emerald-700 border-emerald-200",
  warning:   "bg-amber-50 text-amber-700 border-amber-200",
  danger:    "bg-red-50 text-red-600 border-red-200",
  info:      "bg-blue-50 text-blue-700 border-blue-200",
  gray:      "bg-zinc-50 text-zinc-600 border-zinc-200",
  draft:     "bg-zinc-50 text-zinc-600 border-zinc-200",
  posted:    "bg-blue-50 text-blue-700 border-blue-200",
  paid:      "bg-emerald-50 text-emerald-700 border-emerald-200",
  partial:   "bg-amber-50 text-amber-700 border-amber-200",
  cancelled: "bg-red-50 text-red-600 border-red-200",
  overdue:   "bg-red-50 text-red-600 border-red-200",
  active:    "bg-emerald-50 text-emerald-700 border-emerald-200",
  inactive:  "bg-zinc-50 text-zinc-500 border-zinc-200",
  issued:    "bg-blue-50 text-blue-700 border-blue-200",
  pending:   "bg-amber-50 text-amber-700 border-amber-200",
};

function inferVariant(status: string): BadgeVariant {
  const s = status.toUpperCase().replace(/\s/g, "_");
  if (s === "DRAFT") return "draft";
  if (s === "SENT" || s === "POSTED" || s === "FINALIZED") return "posted";
  if (s === "PAID" || s === "COMPLETED") return "paid";
  if (s === "PARTIALLY_PAID" || s === "PARTIAL") return "partial";
  if (s === "CANCELLED" || s === "CANCELED" || s === "VOID" || s === "REVERSED") return "cancelled";
  if (s === "OVERDUE" || s === "EXPIRED") return "overdue";
  if (s === "PENDING" || s === "UNPAID" || s === "PARTIALLY_PAID" || s === "PROCESSING") return "pending";
  if (s === "ACTIVE" || s === "OPEN") return "active";
  if (s === "INACTIVE" || s === "CLOSED") return "inactive";
  if (s === "ISSUED" || s === "CONFIRMED") return "issued";
  return "gray";
}

export default function StatusBadge({ status, variant, className = "" }: StatusBadgeProps) {
  const resolved = variant || inferVariant(status);
  const display = status.replace(/_/g, " ");

  return (
    <span
      className={`inline-flex items-center px-2.5 py-0.5 text-xs font-semibold rounded-full border ${VARIANT_CLASSES[resolved]} ${className}`}
    >
      {display}
    </span>
  );
}
