import React, { Component, ErrorInfo, ReactNode } from "react";
import { AlertTriangle, RefreshCw, Home } from "lucide-react";

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onReset?: () => void;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export default class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null };
  }

  static getDerivedStateFromError(error: Error): Partial<ErrorBoundaryState> {
    // Update state so the next render shows the fallback UI
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    // Log the error to an error reporting service
    console.error("ErrorBoundary caught an error:", error, errorInfo);
    this.setState({ error, errorInfo });
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    if (this.props.onReset) {
      this.props.onReset();
    }
  };

  handleReload = () => {
    window.location.reload();
  };

  handleGoHome = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    window.location.href = "/";
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return <>{this.props.fallback}</>;
      }

      return (
        <div className="min-h-screen flex items-center justify-center bg-zinc-50 p-4">
          <div className="max-w-lg w-full bg-white rounded-2xl shadow-xl border border-zinc-200 overflow-hidden">
            <div className="bg-red-50 p-6 border-b border-red-100">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-red-100 rounded-full">
                  <AlertTriangle className="w-6 h-6 text-red-600" />
                </div>
                <div>
                  <h2 className="text-lg font-bold text-red-900">Something went wrong</h2>
                  <p className="text-sm text-red-700 mt-1">
                    We encountered an unexpected error. Your data is safe.
                  </p>
                </div>
              </div>
            </div>

            <div className="p-6 space-y-4">
              {this.state.error && (
                <div className="bg-zinc-50 border border-zinc-200 rounded-lg p-4">
                  <p className="text-xs font-semibold text-zinc-500 uppercase tracking-wider mb-2">Error Details</p>
                  <code className="block text-xs text-red-800 font-mono bg-red-50 p-2 rounded break-all">
                    {this.state.error.toString()}
                  </code>
                </div>
              )}

              <div className="grid grid-cols-3 gap-3 pt-2">
                <button
                  onClick={this.handleReset}
                  className="flex flex-col items-center gap-1.5 p-3 rounded-lg border border-zinc-200 hover:bg-zinc-50 transition"
                >
                  <RefreshCw className="w-5 h-5 text-zinc-600" />
                  <span className="text-xs font-semibold text-zinc-700">Try Again</span>
                </button>
                <button
                  onClick={this.handleReload}
                  className="flex flex-col items-center gap-1.5 p-3 rounded-lg border border-zinc-200 hover:bg-zinc-50 transition"
                >
                  <RefreshCw className="w-5 h-5 text-zinc-600" />
                  <span className="text-xs font-semibold text-zinc-700">Reload Page</span>
                </button>
                <button
                  onClick={this.handleGoHome}
                  className="flex flex-col items-center gap-1.5 p-3 rounded-lg border border-zinc-200 hover:bg-zinc-50 transition"
                >
                  <Home className="w-5 h-5 text-zinc-600" />
                  <span className="text-xs font-semibold text-zinc-700">Go Home</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
