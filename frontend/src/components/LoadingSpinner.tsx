import React from "react";

interface LoadingSpinnerProps {
  size?: "sm" | "md" | "lg";
  message?: string;
}

const SIZES = {
  sm: "h-5 w-5 border-2",
  md: "h-8 w-8 border-[3px]",
  lg: "h-12 w-12 border-4",
};

export default function LoadingSpinner({ size = "md", message }: LoadingSpinnerProps) {
  return (
    <div className="flex flex-col items-center justify-center py-16 gap-3">
      <div
        className={`animate-spin rounded-full border-brand-gold border-t-transparent ${SIZES[size]}`}
      />
      {message && (
        <p className="text-sm text-zinc-500 font-medium">{message}</p>
      )}
    </div>
  );
}
