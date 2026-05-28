import React from "react";

interface AppCardProps {
  children: React.ReactNode;
  className?: string;
  padding?: "default" | "none" | "sm";
  onClick?: () => void;
}

export default function AppCard({ children, className = "", padding = "default", onClick }: AppCardProps) {
  const paddingClasses: Record<string, string> = {
    default: "p-6",
    sm: "p-4",
    none: "",
  };

  return (
    <div
      onClick={onClick}
      className={`bg-white rounded-xl shadow-card border border-zinc-200 ${paddingClasses[padding]} ${onClick ? "cursor-pointer hover:shadow-card-elevated transition-shadow" : ""} ${className}`}
    >
      {children}
    </div>
  );
}
