import React from "react";

interface SectionHeaderProps {
  title: string;
  action?: React.ReactNode;
  className?: string;
}

export default function SectionHeader({ title, action, className = "" }: SectionHeaderProps) {
  return (
    <div className={`flex items-center justify-between pb-2 mb-4 border-b border-zinc-100 ${className}`}>
      <h3 className="text-[15px] font-semibold text-zinc-900">{title}</h3>
      {action && <div>{action}</div>}
    </div>
  );
}
