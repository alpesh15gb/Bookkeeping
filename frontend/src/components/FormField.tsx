import React from "react";

interface FormFieldProps {
  label: string;
  required?: boolean;
  hint?: string;
  error?: string;
  children: React.ReactNode;
  className?: string;
}

export default function FormField({ label, required, hint, error, children, className = "" }: FormFieldProps) {
  return (
    <div className={`space-y-1.5 ${className}`}>
      <label className="block text-xs font-semibold text-zinc-500 uppercase tracking-wider">
        {label}
        {required && <span className="text-red-500 ml-0.5">*</span>}
      </label>
      {children}
      {hint && !error && (
        <p className="text-xs text-zinc-400 mt-0.5">{hint}</p>
      )}
      {error && (
        <p className="text-xs text-red-500 mt-0.5 font-medium">{error}</p>
      )}
    </div>
  );
}
