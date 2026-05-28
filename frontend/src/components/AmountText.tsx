import React from "react";
import { formatIndianCurrency } from "../lib/utils";

interface AmountTextProps {
  value: number;
  size?: "sm" | "md" | "lg";
  colored?: boolean; // red for negative, green for positive
  compact?: boolean;
  showSymbol?: boolean;
  className?: string;
}

const SIZES = {
  sm: "text-xs",
  md: "text-sm",
  lg: "text-base",
};

export default function AmountText({
  value,
  size = "sm",
  colored = false,
  compact = false,
  showSymbol = true,
  className = "",
}: AmountTextProps) {
  const display = formatIndianCurrency(value, compact, showSymbol);
  const colorClass = colored
    ? value < 0
      ? "text-red-600"
      : value > 0
        ? "text-emerald-600"
        : "text-zinc-500"
    : "text-zinc-900";

  return (
    <span className={`font-mono font-semibold tabular-nums ${SIZES[size]} ${colorClass} ${className}`}>
      {display}
    </span>
  );
}
