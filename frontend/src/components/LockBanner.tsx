import React from "react";
import { Lock, AlertTriangle } from "lucide-react";

interface LockBannerProps {
  message: string;
  type?: "posted" | "locked" | "void";
  action?: {
    label: string;
    onClick: () => void;
  };
}

const STYLES = {
  posted: {
    bg: "bg-blue-50 border-blue-200",
    text: "text-blue-700",
    icon: Lock,
  },
  locked: {
    bg: "bg-amber-50 border-amber-200",
    text: "text-amber-700",
    icon: Lock,
  },
  void: {
    bg: "bg-red-50 border-red-200",
    text: "text-red-600",
    icon: AlertTriangle,
  },
};

export default function LockBanner({ message, type = "posted", action }: LockBannerProps) {
  const style = STYLES[type];
  const Icon = style.icon;

  return (
    <div className={`flex items-center justify-between px-4 py-3 rounded-lg border ${style.bg} mb-6`}>
      <div className="flex items-center gap-3">
        <Icon className={`w-4 h-4 ${style.text}`} />
        <p className={`text-sm font-medium ${style.text}`}>{message}</p>
      </div>
      {action && (
        <button
          onClick={action.onClick}
          className={`text-sm font-semibold ${style.text} hover:underline`}
        >
          {action.label}
        </button>
      )}
    </div>
  );
}
