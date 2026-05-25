import React, { useState } from "react";
import { apiClient, setAccessToken, setRefreshToken, setTenantId } from "../../lib/api";
import { BookOpen } from "lucide-react";

interface LoginPageProps {
  onLogin: () => void;
}

export default function LoginPage({ onLogin }: LoginPageProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [registering, setRegistering] = useState(false);
  const [regFields, setRegFields] = useState({
    full_name: "",
    phone_number: "",
    company_legal_name: "",
    company_gstin: "",
    company_pan: "",
  });

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const res = await apiClient.post("/auth/login", { email, password });
      const { access_token, refresh_token } = res.data;
      setAccessToken(access_token);
      setRefreshToken(refresh_token);

      // Fetch memberships to get first tenant ID
      const memRes = await apiClient.get("/auth/memberships");
      const memberships = memRes.data;
      if (memberships.length > 0) {
        setTenantId(memberships[0].tenant_id);
      }

      onLogin();
    } catch (err: any) {
      setError(err.response?.data?.detail || "Login failed");
    } finally {
      setLoading(false);
    }
  };

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await apiClient.post("/auth/register", {
        email,
        password,
        ...regFields,
      });
      setRegistering(false);
      // Auto-login after registration
      await handleLogin(e);
    } catch (err: any) {
      setError(err.response?.data?.detail || "Registration failed");
    } finally {
      setLoading(false);
    }
  };

  if (registering) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50 px-4">
        <div className="w-full max-w-md bg-white rounded-2xl shadow-sm border border-slate-200 p-8">
          <div className="flex items-center gap-3 mb-8">
            <div className="h-10 w-10 bg-brand-600 rounded-xl flex items-center justify-center text-white font-bold text-xl">
              A
            </div>
            <div>
              <h1 className="text-lg font-bold text-slate-900">ApexBooks</h1>
              <p className="text-xs text-slate-500">Indian Accounting + GST</p>
            </div>
          </div>
          <h2 className="text-xl font-bold text-slate-900 mb-6">Create Account</h2>
          <form onSubmit={handleRegister} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Full Name</label>
              <input type="text" required value={regFields.full_name} onChange={e => setRegFields({ ...regFields, full_name: e.target.value })}
                className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Company Name</label>
              <input type="text" required value={regFields.company_legal_name} onChange={e => setRegFields({ ...regFields, company_legal_name: e.target.value })}
                className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Email</label>
              <input type="email" required value={email} onChange={e => setEmail(e.target.value)}
                className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Password</label>
              <input type="password" required minLength={8} value={password} onChange={e => setPassword(e.target.value)}
                className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
              <p className="text-xs text-slate-400 mt-1">Min 8 chars, uppercase, lowercase, digit & special character</p>
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Phone</label>
              <input type="text" value={regFields.phone_number} onChange={e => setRegFields({ ...regFields, phone_number: e.target.value })}
                className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">GSTIN (optional)</label>
              <input type="text" value={regFields.company_gstin} onChange={e => setRegFields({ ...regFields, company_gstin: e.target.value })}
                className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">PAN (optional)</label>
              <input type="text" value={regFields.company_pan} onChange={e => setRegFields({ ...regFields, company_pan: e.target.value })}
                className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
            </div>
            {error && <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>}
            <button type="submit" disabled={loading}
              className="w-full bg-brand-600 text-white py-2.5 rounded-lg font-semibold text-sm hover:bg-brand-700 disabled:opacity-50">
              {loading ? "Please wait..." : "Register"}
            </button>
            <p className="text-xs text-center text-slate-500">
              Already have an account?{" "}
              <button type="button" onClick={() => setRegistering(false)} className="text-brand-600 font-semibold hover:underline">
                Sign in
              </button>
            </p>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-50 px-4">
      <div className="w-full max-w-sm bg-white rounded-2xl shadow-sm border border-slate-200 p-8">
        <div className="flex items-center gap-3 mb-8">
          <div className="h-10 w-10 bg-brand-600 rounded-xl flex items-center justify-center text-white font-bold text-xl">
            A
          </div>
          <div>
            <h1 className="text-lg font-bold text-slate-900">ApexBooks</h1>
            <p className="text-xs text-slate-500">Indian Accounting + GST</p>
          </div>
        </div>
        <h2 className="text-xl font-bold text-slate-900 mb-6">Sign In</h2>
        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Email</label>
            <input type="email" required value={email} onChange={e => setEmail(e.target.value)}
              className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
          </div>
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1">Password</label>
            <input type="password" required value={password} onChange={e => setPassword(e.target.value)}
              className="w-full px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500" />
          </div>
          {error && <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>}
          <button type="submit" disabled={loading}
            className="w-full bg-brand-600 text-white py-2.5 rounded-lg font-semibold text-sm hover:bg-brand-700 disabled:opacity-50">
            {loading ? "Please wait..." : "Sign In"}
          </button>
          <p className="text-xs text-center text-slate-500">
            New to ApexBooks?{" "}
            <button type="button" onClick={() => setRegistering(true)} className="text-brand-600 font-semibold hover:underline">
              Create account
            </button>
          </p>
        </form>
      </div>
    </div>
  );
}
