import React from "react";
import { ArrowLeft } from "lucide-react";

export interface PageHeaderAction {
  label: string;
  onClick: () => void;
  icon?: React.ReactNode;
  variant?: "primary" | "secondary" | "ghost" | "danger";
  disabled?: boolean;
  loading?: boolean;
}

interface PageHeaderProps {
  title: string;
  subtitle?: string;
  backTo?: () => void;
  actions?: PageHeaderAction[];
}

export default function PageHeader({ title, subtitle, backTo, actions }: PageHeaderProps) {
  return (
    <div className="pb-5 border-b border-zinc-200 mb-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div className="flex items-center gap-3 min-w-0">
          {backTo && (
            <button
              onClick={backTo}
              className="p-1.5 text-zinc-400 hover:text-zinc-600 hover:bg-zinc-100 rounded-lg transition flex-shrink-0"
              aria-label="Back"
            >
              <ArrowLeft className="w-5 h-5" />
            </button>
          )}
          <div className="min-w-0">
            <h1 className="text-[22px] font-bold tracking-tight text-zinc-900 truncate">
              {title}
            </h1>
            {subtitle && (
              <p className="text-sm text-zinc-500 mt-0.5">{subtitle}</p>
            )}
          </div>
        </div>

        {actions && actions.length > 0 && (
          <div className="flex items-center gap-2 flex-shrink-0">
            {actions.map((action, i) => {
              const variant = action.variant || "primary";
              const base =
                "inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-semibold transition duration-150 disabled:opacity-50 disabled:cursor-not-allowed";

              const variants: Record<string, string> = {
                primary:
                  "bg-brand-gold text-white hover:bg-brand-gold-hover shadow-sm",
                secondary:
                  "bg-white text-zinc-700 border border-zinc-200 hover:bg-zinc-50",
                ghost:
                  "bg-transparent text-zinc-500 hover:bg-zinc-100 border border-transparent",
                danger:
                  "bg-red-50 text-red-600 border border-red-200 hover:bg-red-100",
              };

              return (
                <button
                  key={i}
                  onClick={action.onClick}
                  disabled={action.disabled || action.loading}
                  className={`${base} ${variants[variant]}`}
                >
                  {action.loading ? (
                    <span className="w-4 h-4 border-2 border-current border-t-transparent rounded-full animate-spin" />
                  ) : action.icon ? (
                    <span className="w-4 h-4">{action.icon}</span>
                  ) : null}
                  {action.label}
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
