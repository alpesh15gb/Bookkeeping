import React, { useState } from "react";
import { apiClient, setAccessToken, setRefreshToken, setTenantId } from "../../lib/api";
import { ShieldCheck, ArrowRight, Smartphone, Mail, Lock, User, Building, Hash } from "lucide-react";

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
    company_legal_name: "",
    company_gstin: "",
    email: "",
    password: "",
    phone_number: "",
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
    if (!regFields.password || regFields.password.length < 8) {
      setError("Password must be at least 8 characters");
      return;
    }
    if (!/[A-Z]/.test(regFields.password)) {
      setError("Password must contain at least one uppercase letter");
      return;
    }
    if (!/[a-z]/.test(regFields.password)) {
      setError("Password must contain at least one lowercase letter");
      return;
    }
    if (!/\d/.test(regFields.password)) {
      setError("Password must contain at least one digit");
      return;
    }
    if (!/[!@#$%^&*(),.?":{}|<>\-_=+\[\]\\/]/.test(regFields.password)) {
      setError("Password must contain at least one special character");
      return;
    }
    setLoading(true);
    try {
      await apiClient.post("/auth/register", {
        email: regFields.email,
        password: regFields.password,
        full_name: regFields.full_name,
        phone_number: regFields.phone_number || undefined,
        company_legal_name: regFields.company_legal_name,
        company_gstin: regFields.company_gstin || undefined,
      });

      setRegistering(false);
      setEmail(regFields.email);
      setPassword("");
      setError("Account created. Please sign in.");
    } catch (err: any) {
      setError(err.response?.data?.detail || "Registration failed");
    } finally {
      setLoading(false);
    }
  };

  if (registering) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-[#0B1B3D] px-4 py-8">
        <div className="w-full max-w-md bg-white rounded-2xl shadow-xl overflow-hidden border border-slate-100 flex flex-col">
          <div className="bg-[#0B1B3D] py-6 px-8 text-center flex flex-col items-center border-b border-navy-800">
            <h2 className="text-lg font-bold text-white mt-1">Set Up Your Business</h2>
            <p className="text-xs text-zinc-300">Let's get started with your business details</p>
          </div>

          <form onSubmit={handleRegister} className="p-6 space-y-4 max-h-[70vh] overflow-y-auto">
            <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider border-b pb-1">Business Information</h3>

            {/* Full Name */}
            <div className="space-y-1">
              <label className="text-[11px] font-bold text-slate-500 uppercase">Your Name</label>
              <div className="relative">
                <User className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
                <input 
                  type="text" 
                  required 
                  placeholder="Enter your full name"
                  value={regFields.full_name} 
                  onChange={e => setRegFields({ ...regFields, full_name: e.target.value })}
                  className="w-full pl-9 pr-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-brand-500" 
                />
              </div>
            </div>

            {/* Business Name */}
            <div className="space-y-1">
              <label className="text-[11px] font-bold text-slate-500 uppercase">Business Name</label>
              <div className="relative">
                <Building className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
                <input 
                  type="text" 
                  required 
                  placeholder="Enter your business name"
                  value={regFields.company_legal_name} 
                  onChange={e => setRegFields({ ...regFields, company_legal_name: e.target.value })}
                  className="w-full pl-9 pr-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-brand-500" 
                />
              </div>
            </div>

            {/* GSTIN */}
            <div className="space-y-1">
              <label className="text-[11px] font-bold text-slate-500 uppercase">GSTIN</label>
              <div className="relative">
                <Hash className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
                <input 
                  type="text" 
                  maxLength={15}
                  placeholder="Enter GSTIN (15 characters)"
                  value={regFields.company_gstin} 
                  onChange={e => setRegFields({ ...regFields, company_gstin: e.target.value.toUpperCase() })}
                  className="w-full pl-9 pr-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 font-mono" 
                />
              </div>
            </div>

            {/* Phone Number */}
            <div className="space-y-1">
              <label className="text-[11px] font-bold text-slate-500 uppercase">Phone Number</label>
              <div className="relative">
                <Smartphone className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
                <input 
                  type="tel" 
                  maxLength={15}
                  placeholder="Enter phone number (optional)"
                  value={regFields.phone_number} 
                  onChange={e => setRegFields({ ...regFields, phone_number: e.target.value })}
                  className="w-full pl-9 pr-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-brand-500" 
                />
              </div>
            </div>

            {/* Email & Password */}
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <label className="text-[11px] font-bold text-slate-500 uppercase">Email</label>
                <input 
                  type="email" 
                  required
                  placeholder="Enter email address"
                  value={regFields.email} 
                  onChange={e => setRegFields({ ...regFields, email: e.target.value })}
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-brand-500" 
                />
              </div>
              <div className="space-y-1">
                <label className="text-[11px] font-bold text-slate-500 uppercase">Password</label>
                <input 
                  type="password" 
                  required
                  minLength={8}
                  placeholder="Min 8 chars, uppercase, lowercase, digit, special"
                  value={regFields.password} 
                  onChange={e => setRegFields({ ...regFields, password: e.target.value })}
                  className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-brand-500" 
                />
              </div>
            </div>

            {error && <p className="text-xs text-red-600 bg-red-50 p-2.5 rounded-lg border border-red-150">{error}</p>}

            <button 
              type="submit" 
              disabled={loading}
              className="w-full bg-[#DCA035] hover:bg-[#C98F2C] text-white py-2.5 rounded-lg font-bold text-sm shadow-md transition flex items-center justify-center gap-1.5 mt-2"
            >
              {loading ? "Creating..." : "Next"} <ArrowRight className="w-4 h-4" />
            </button>

            <p className="text-xs text-center text-slate-500 mt-2">
              Already have an account?{" "}
              <button type="button" onClick={() => setRegistering(false)} className="text-brand-700 font-bold hover:underline">
                Sign In
              </button>
            </p>
          </form>
          
          <div className="bg-slate-50 py-3 text-center border-t text-[10px] text-slate-400 flex items-center justify-center gap-1">
            <ShieldCheck className="w-4 h-4 text-emerald-600" /> Your data is safe and secure with us
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-[#0B1B3D] px-4">

      <div className="w-full max-w-sm flex flex-col items-center">
        {/* Card for login form */}
        <div className="w-full bg-[#0F2247]/80 backdrop-blur-md rounded-2xl border border-navy-800 p-6 shadow-2xl">
          <div className="flex flex-col items-center text-center mb-5">
            <div className="p-2.5 bg-navy-800 rounded-xl mb-2 text-[#DCA035] border border-navy-100/10">
              <Smartphone className="w-5 h-5" />
            </div>
            <h2 className="text-sm font-bold text-white">Sign In</h2>
            <p className="text-[11px] text-zinc-400">Enter your credentials to continue</p>
          </div>

          {error && <p className="text-xs text-red-400 bg-red-950/40 border border-red-900/50 p-2.5 rounded-lg mb-4 text-center">{error}</p>}

          <form onSubmit={handleLogin} className="space-y-4">
            <div className="space-y-1">
              <label className="text-[10px] font-bold text-zinc-400 uppercase">Email</label>
              <div className="relative">
                <Mail className="absolute left-3 top-2.5 h-4 w-4 text-zinc-500" />
                <input
                  type="email"
                  required
                  placeholder="Enter email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full bg-navy-800 border border-navy-800 text-white pl-9 pr-3 py-2 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none"
                />
              </div>
            </div>

            <div className="space-y-1">
              <label className="text-[10px] font-bold text-zinc-400 uppercase">Password</label>
              <div className="relative">
                <Lock className="absolute left-3 top-2.5 h-4 w-4 text-zinc-500" />
                <input
                  type="password"
                  required
                  placeholder="Enter password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="w-full bg-navy-800 border border-navy-800 text-white pl-9 pr-3 py-2 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 outline-none"
                />
              </div>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-[#DCA035] hover:bg-[#C98F2C] text-white py-2.5 rounded-lg text-xs font-bold shadow-md transition"
            >
              {loading ? "Authenticating..." : "SIGN IN"}
            </button>
          </form>

          {/* SignUp Redirect */}
          <div className="w-full text-center mt-6 space-y-4">
            <div className="flex items-center justify-center gap-3">
              <span className="h-px bg-zinc-700 w-12" />
              <span className="text-[10px] text-zinc-500 font-semibold uppercase">New user?</span>
              <span className="h-px bg-zinc-700 w-12" />
            </div>
            <button
              onClick={() => setRegistering(true)}
              className="w-full border border-zinc-600 hover:border-[#DCA035] text-zinc-300 hover:text-white py-2 rounded-lg text-xs font-semibold tracking-wider transition uppercase"
            >
              SIGN UP <ArrowRight className="w-3.5 h-3.5 inline-block ml-0.5" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

