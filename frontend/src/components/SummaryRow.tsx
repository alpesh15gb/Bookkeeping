import React from "react";
import { formatIndianCurrency } from "../lib/utils";

interface SummaryRowProps {
  label: string;
  value: number;
  bold?: boolean;
  separator?: boolean;
  prefix?: string;
  className?: string;
}

export default function SummaryRow({
  label,
  value,
  bold = false,
  separator = false,
  prefix = "₹",
  className = "",
}: SummaryRowProps) {
  return (
    <div
      className={`flex items-center justify-between py-2 ${bold ? "font-semibold" : ""} ${
        separator ? "border-t border-zinc-200 mt-1 pt-3" : ""
      } ${className}`}
    >
      <span
        className={`text-sm ${bold ? "text-zinc-900 font-semibold" : "text-zinc-500"}`}
      >
        {label}
      </span>
      <span
        className={`text-sm font-mono tabular-nums ${bold ? "text-zinc-900 font-semibold text-base" : "text-zinc-700"}`}
      >
        {prefix}{formatIndianCurrency(value, false, false)}
      </span>
    </div>
  );
}
