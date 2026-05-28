import React from "react";
import { LucideIcon, Plus } from "lucide-react";

interface EmptyStateAction {
  label: string;
  onClick: () => void;
  icon?: React.ReactNode;
}

interface EmptyStateProps {
  icon?: LucideIcon;
  title: string;
  description?: string;
  action?: EmptyStateAction;
}

export default function EmptyState({ icon: Icon, title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-4 text-center">
      {Icon && (
        <div className="w-14 h-14 rounded-full bg-zinc-100 flex items-center justify-center mb-4">
          <Icon className="w-7 h-7 text-zinc-400" />
        </div>
      )}
      <h3 className="text-base font-semibold text-zinc-800 mb-1">{title}</h3>
      {description && (
        <p className="text-sm text-zinc-500 max-w-sm mb-5">{description}</p>
      )}
      {action && (
        <button
          onClick={action.onClick}
          className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-gold text-white rounded-lg text-sm font-semibold hover:bg-brand-gold-hover transition shadow-sm"
        >
          {action.icon || <Plus className="w-4 h-4" />}
          {action.label}
        </button>
      )}
    </div>
  );
}
