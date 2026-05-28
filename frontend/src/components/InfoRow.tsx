import React from "react";
import { Copy, Check } from "lucide-react";
import { useState } from "react";

interface InfoRowProps {
  label: string;
  value: React.ReactNode;
  mono?: boolean;
  copyable?: boolean;
  className?: string;
}

export default function InfoRow({ label, value, mono = false, copyable = false, className = "" }: InfoRowProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    const text = typeof value === "string" ? value : String(value);
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  return (
    <div className={`flex items-center justify-between py-2.5 px-1 ${className}`}>
      <span className="text-xs font-semibold text-zinc-400 uppercase tracking-wider flex-shrink-0">
        {label}
      </span>
      <div className="flex items-center gap-2 max-w-[60%]">
        <span
          className={`text-sm text-right break-all ${mono ? "font-mono font-medium text-zinc-800" : "text-zinc-700"}`}
        >
          {value || "—"}
        </span>
        {copyable && value && (
          <button
            onClick={handleCopy}
            className="p-0.5 text-zinc-400 hover:text-brand-gold transition flex-shrink-0"
            title="Copy"
          >
            {copied ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
          </button>
        )}
      </div>
    </div>
  );
}
