import React from "react";
import { LucideIcon, TrendingUp, TrendingDown } from "lucide-react";
import { formatIndianCurrency, formatMetricAmount } from "../lib/utils";

interface MetricCardProps {
  label: string;
  value: number;
  prefix?: string;
  trend?: number; // positive = up (green), negative = down (red)
  subtext?: string;
  icon?: LucideIcon;
  iconColor?: string;
}

export default function MetricCard({ label, value, prefix = "₹", trend, subtext, icon: Icon, iconColor }: MetricCardProps) {
  const isNegative = value < 0;
  const { value: displayValue, suffix } = formatMetricAmount(value);

  return (
    <div className="bg-white rounded-xl border border-zinc-200 p-5 hover:shadow-card-elevated transition-shadow">
      <div className="flex items-start justify-between mb-3">
        <p className="text-xs font-semibold text-zinc-400 uppercase tracking-wider leading-none">
          {label}
        </p>
        {Icon && (
          <div
            className="w-8 h-8 rounded-lg flex items-center justify-center"
            style={{ backgroundColor: iconColor ? `${iconColor}15` : "rgba(220, 160, 53, 0.1)" }}
          >
            <Icon
              className="w-4 h-4"
              style={{ color: iconColor || "#DCA035" }}
            />
          </div>
        )}
      </div>
      <div className="space-y-1">
        <p className={`text-[28px] font-bold tracking-tight ${isNegative ? "text-red-600" : "text-zinc-900"}`}>
          {isNegative ? "-" : ""}{prefix}{displayValue}
          {suffix && <span className="text-lg font-semibold text-zinc-500 ml-0.5">{suffix}</span>}
        </p>
        {trend !== undefined && (
          <div className="flex items-center gap-1">
            {trend >= 0 ? (
              <TrendingUp className="w-3.5 h-3.5 text-emerald-600" />
            ) : (
              <TrendingDown className="w-3.5 h-3.5 text-red-600" />
            )}
            <span className={`text-xs font-semibold ${trend >= 0 ? "text-emerald-600" : "text-red-600"}`}>
              {Math.abs(trend).toFixed(1)}%
            </span>
            <span className="text-xs text-zinc-400">vs last month</span>
          </div>
        )}
        {subtext && !trend && (
          <p className="text-xs text-zinc-400">{subtext}</p>
        )}
      </div>
    </div>
  );
}
