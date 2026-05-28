import React from "react";

interface FormCardProps {
  title: string;
  description?: string;
  children: React.ReactNode;
  className?: string;
}

export default function FormCard({ title, description, children, className = "" }: FormCardProps) {
  return (
    <div className={`bg-white rounded-xl shadow-card border border-zinc-200 ${className}`}>
      <div className="px-6 pt-5 pb-4 border-b border-zinc-100">
        <h3 className="text-[15px] font-semibold text-zinc-900">{title}</h3>
        {description && (
          <p className="text-sm text-zinc-500 mt-0.5">{description}</p>
        )}
      </div>
      <div className="p-6">{children}</div>
    </div>
  );
}
