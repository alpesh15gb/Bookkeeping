import React from "react";
import { Search, Plus, Filter } from "lucide-react";

interface FilterOption {
  label: string;
  value: string;
  count?: number;
}

interface FilterConfig {
  label: string;
  options: FilterOption[];
  selected: string | null;
  onChange: (value: string | null) => void;
}

interface ActionConfig {
  label: string;
  icon?: React.ReactNode;
  onClick: () => void;
  variant?: "primary" | "secondary" | "ghost";
}

interface ToolbarProps {
  search?: {
    placeholder?: string;
    value: string;
    onChange: (value: string) => void;
  };
  filters?: FilterConfig[];
  primaryAction?: ActionConfig;
  secondaryActions?: ActionConfig[];
}

const CHIP_COLORS = [
  "border-zinc-200 text-zinc-600 hover:bg-zinc-100",
  "border-blue-200 text-blue-600 hover:bg-blue-50",
  "border-emerald-200 text-emerald-600 hover:bg-emerald-50",
  "border-amber-200 text-amber-600 hover:bg-amber-50",
  "border-red-200 text-red-600 hover:bg-red-50",
  "border-purple-200 text-purple-600 hover:bg-purple-50",
];

export default function Toolbar({ search, filters, primaryAction, secondaryActions }: ToolbarProps) {
  const hasLeft = !!(search || (filters && filters.length > 0));
  const hasRight = !!(primaryAction || (secondaryActions && secondaryActions.length > 0));

  if (!hasLeft && !hasRight) return null;

  return (
    <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 mb-6">
      {/* Left: Search + Filters */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3 w-full sm:w-auto">
        {search && (
          <div className="relative w-full sm:w-72">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-zinc-400" />
            <input
              type="search"
              placeholder={search.placeholder || "Search..."}
              value={search.value}
              onChange={(e) => search.onChange(e.target.value)}
              className="w-full pl-10 pr-4 py-2 text-sm bg-white border border-zinc-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-gold/20 focus:border-brand-gold transition"
            />
          </div>
        )}

        {filters && filters.length > 0 && (
          <div className="flex flex-wrap items-center gap-2">
            {filters.map((filter, fi) => (
              <React.Fragment key={filter.label}>
                {filter.options.map((opt, oi) => {
                  const isActive = filter.selected === opt.value;
                  const colorIdx = (fi * filter.options.length + oi) % CHIP_COLORS.length;
                  return (
                    <button
                      key={opt.value}
                      onClick={() => filter.onChange(isActive ? null : opt.value)}
                      className={`inline-flex items-center gap-1 px-3 py-1.5 text-xs font-semibold rounded-full border transition ${
                        isActive
                          ? "bg-brand-gold-light text-brand-gold border-brand-gold/30"
                          : CHIP_COLORS[colorIdx]
                      }`}
                    >
                      {opt.label}
                      {opt.count !== undefined && (
                        <span className={`ml-0.5 px-1 py-px rounded text-[10px] font-bold ${isActive ? "bg-brand-gold/20" : "bg-zinc-100"}`}>
                          {opt.count}
                        </span>
                      )}
                    </button>
                  );
                })}
              </React.Fragment>
            ))}
          </div>
        )}
      </div>

      {/* Right: Actions */}
      <div className="flex items-center gap-2 flex-shrink-0">
        {secondaryActions?.map((action, i) => (
          <button
            key={i}
            onClick={action.onClick}
            className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-semibold text-zinc-600 bg-white border border-zinc-200 rounded-lg hover:bg-zinc-50 transition"
          >
            {action.icon}
            {action.label}
          </button>
        ))}
        {primaryAction && (
          <button
            onClick={primaryAction.onClick}
            className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-semibold text-white bg-brand-gold hover:bg-brand-gold-hover rounded-lg shadow-sm transition"
          >
            {primaryAction.icon || <Plus className="w-4 h-4" />}
            {primaryAction.label}
          </button>
        )}
      </div>
    </div>
  );
}
