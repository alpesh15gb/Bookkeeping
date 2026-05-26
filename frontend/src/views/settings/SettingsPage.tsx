import React, { useState, useRef } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiClient, getActiveTenantId } from "../../lib/api";
import {
  Building2,
  User,
  Receipt,
  FileText,
  Wallet,
  Shield,
  ClipboardList,
  Save,
  Plus,
  Trash2,
  Edit,
  ShieldAlert,
  Eye,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";

interface SettingsPageProps {
  onNavigate: (view: "settings") => void;
}

interface CompanyData {
  id: string;
  legal_name: string;
  trade_name: string;
  gstin: string;
  pan: string;
  financial_year_start: string;
}

interface TenantSettings {
  id: string;
  tenant_id: string;
  logo_url: string;
  currency: string;
  gst_enabled: boolean;
  e_invoicing_enabled: boolean;
  e_invoice_username: string;
  e_way_bill_username: string;
  extra_settings: Record<string, any>;
  origin_state_code: string;
}

interface UserProfile {
  id: string;
  email: string;
  full_name: string;
  phone_number: string;
  is_active: boolean;
}

interface SeriesItem {
  id: string;
  tenant_id: string;
  document_type: string;
  prefix: string;
  next_number: number;
  suffix: string;
  padding_digits: number;
  is_active: boolean;
}

interface BankingProfile {
  id: string;
  bank_name: string;
  account_number: string;
  ifsc_code: string;
  branch_name: string;
  account_holder_name: string;
  upi_id: string;
  is_primary: boolean;
  is_active: boolean;
}

interface AuditLogItem {
  id: string;
  actor_email: string;
  action: string;
  resource: string;
  ip_address: string;
  user_agent: string;
  created_at: string;
}

const STATE_CODES = [
  { code: "01", name: "Jammu & Kashmir" },
  { code: "02", name: "Himachal Pradesh" },
  { code: "03", name: "Punjab" },
  { code: "04", name: "Chandigarh" },
  { code: "05", name: "Uttarakhand" },
  { code: "06", name: "Haryana" },
  { code: "07", name: "Delhi" },
  { code: "08", name: "Rajasthan" },
  { code: "09", name: "Uttar Pradesh" },
  { code: "10", name: "Bihar" },
  { code: "11", name: "Sikkim" },
  { code: "12", name: "Arunachal Pradesh" },
  { code: "13", name: "Nagaland" },
  { code: "14", name: "Manipur" },
  { code: "15", name: "Mizoram" },
  { code: "16", name: "Tripura" },
  { code: "17", name: "Meghalaya" },
  { code: "18", name: "Assam" },
  { code: "19", name: "West Bengal" },
  { code: "20", name: "Jharkhand" },
  { code: "21", name: "Odisha" },
  { code: "22", name: "Chhattisgarh" },
  { code: "23", name: "Madhya Pradesh" },
  { code: "24", name: "Gujarat" },
  { code: "25", name: "Daman & Diu" },
  { code: "26", name: "Dadra & Nagar Haveli" },
  { code: "27", name: "Maharashtra" },
  { code: "28", name: "Andhra Pradesh (Old)" },
  { code: "29", name: "Karnataka" },
  { code: "30", name: "Goa" },
  { code: "31", name: "Lakshadweep" },
  { code: "32", name: "Kerala" },
  { code: "33", name: "Tamil Nadu" },
  { code: "34", name: "Puducherry" },
  { code: "35", name: "Andaman & Nicobar" },
  { code: "36", name: "Telangana" },
  { code: "37", name: "Andhra Pradesh" },
  { code: "38", name: "Ladakh" },
];

const DOC_TYPES = ["INVOICE", "BILL", "PAYMENT", "JOURNAL"];

type TabId = "company" | "profile" | "gst" | "invoice" | "bank" | "security" | "audit";

const TABS: { id: TabId; label: string; icon: React.ReactNode }[] = [
  { id: "company", label: "Company", icon: <Building2 className="w-4 h-4" /> },
  { id: "profile", label: "Profile", icon: <User className="w-4 h-4" /> },
  { id: "gst", label: "GST & Tax", icon: <Receipt className="w-4 h-4" /> },
  { id: "invoice", label: "Invoice", icon: <FileText className="w-4 h-4" /> },
  { id: "bank", label: "Bank & Payments", icon: <Wallet className="w-4 h-4" /> },
  { id: "security", label: "Security", icon: <Shield className="w-4 h-4" /> },
  { id: "audit", label: "Audit Logs", icon: <ClipboardList className="w-4 h-4" /> },
];

function LogoUploader({ currentLogo, onUpload, onRemove }: { currentLogo: string; onUpload: (url: string) => void; onRemove: () => void }) {
  const [uploading, setUploading] = useState(false);
  const [dragOver, setDragOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const queryClient = useQueryClient();

  const uploadMutation = useMutation({
    mutationFn: async (file: File) => {
      const fd = new FormData();
      fd.append("file", file);
      const res = await apiClient.post("/settings/logo", fd, {
        headers: { "Content-Type": "multipart/form-data" },
      });
      return res.data.logo_url;
    },
    onSuccess: (url) => {
      onUpload(url);
      queryClient.invalidateQueries({ queryKey: ["settings"] });
    },
  });

  const handleFile = (file: File) => {
    if (!file.type.startsWith("image/")) return;
    setUploading(true);
    uploadMutation.mutate(file, {
      onSettled: () => setUploading(false),
    });
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleFile(file);
  };

  return (
    <div className="space-y-3">
      <div
        onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
        onDragLeave={() => setDragOver(false)}
        onDrop={handleDrop}
        onClick={() => inputRef.current?.click()}
        className={`relative flex flex-col items-center justify-center border-2 border-dashed rounded-xl p-6 cursor-pointer transition ${
          dragOver ? "border-brand-500 bg-brand-50" : "border-slate-200 hover:border-brand-300 bg-slate-50/50"
        }`}
      >
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          onChange={handleChange}
          className="hidden"
        />

        {currentLogo ? (
          <div className="flex flex-col items-center gap-3">
            <img
              src={currentLogo}
              alt="Company logo"
              className="max-h-24 max-w-48 object-contain rounded-lg border border-slate-100"
            />
            <div className="flex gap-2">
              {uploading ? (
                <span className="text-xs text-slate-500">Uploading...</span>
              ) : (
                <>
                  <span className="text-xs text-slate-400">Click or drag to replace</span>
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); onRemove(); }}
                    className="text-xs text-rose-600 hover:text-rose-700 font-semibold"
                  >
                    Remove
                  </button>
                </>
              )}
            </div>
          </div>
        ) : (
          <div className="flex flex-col items-center gap-2 text-slate-400">
            {uploading ? (
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" />
            ) : (
              <>
                <svg className="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
                <span className="text-sm">Drop logo here or click to browse</span>
                <span className="text-xs">PNG, JPG, GIF, WebP up to 5MB</span>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}


export default function SettingsPage({ onNavigate }: SettingsPageProps) {
  const [activeTab, setActiveTab] = useState<TabId>("company");
  const queryClient = useQueryClient();

  const { data: companyData, isLoading: companyLoading } = useQuery<CompanyData>({
    queryKey: ["company"],
    queryFn: async () => {
      const tenantId = getActiveTenantId();
      const res = await apiClient.get(`/companies/${tenantId}`);
      return res.data;
    },
  });

  const { data: settings, isLoading: settingsLoading } = useQuery<TenantSettings>({
    queryKey: ["settings"],
    queryFn: async () => {
      const res = await apiClient.get("/settings");
      return res.data;
    },
  });

  const { data: userProfile, isLoading: profileLoading } = useQuery<UserProfile>({
    queryKey: ["auth-me"],
    queryFn: async () => {
      const res = await apiClient.get("/auth/me");
      return res.data;
    },
  });

  const { data: seriesList = [], isLoading: seriesLoading } = useQuery<SeriesItem[]>({
    queryKey: ["series"],
    queryFn: async () => {
      const res = await apiClient.get("/settings/series");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const { data: bankingProfiles = [], isLoading: bankingLoading } = useQuery<BankingProfile[]>({
    queryKey: ["banking-profiles"],
    queryFn: async () => {
      const res = await apiClient.get("/masters/banking-profiles");
      return Array.isArray(res.data) ? res.data : [];
    },
  });

  const [auditPage, setAuditPage] = useState(1);
  const [auditPageSize] = useState(20);
  const { data: auditData, isLoading: auditLoading } = useQuery<{ data: AuditLogItem[]; total: number }>({
    queryKey: ["audit-logs", auditPage, auditPageSize],
    queryFn: async () => {
      const res = await apiClient.get("/audit-logs", {
        params: { page: auditPage, page_size: auditPageSize },
      });
      const logs = Array.isArray(res.data) ? res.data : [];
      return {
        data: logs,
        total: res.headers["x-total-count"] ? parseInt(res.headers["x-total-count"]) : logs.length
      };
    },
  });

  const [companyForm, setCompanyForm] = useState({
    legal_name: "",
    trade_name: "",
    gstin: "",
    pan: "",
    financial_year_start: "",
    cin: "",
  });

  const [settingsForm, setSettingsForm] = useState({
    logo_url: "",
    gst_enabled: false,
    e_invoicing_enabled: false,
    e_invoice_username: "",
    e_way_bill_username: "",
    origin_state_code: "",
  });

  const [seriesEditId, setSeriesEditId] = useState<string | null>(null);
  const [seriesEdit, setSeriesEdit] = useState<Partial<SeriesItem>>({});

  const [bankForm, setBankForm] = useState<Partial<BankingProfile>>({
    bank_name: "",
    account_number: "",
    ifsc_code: "",
    branch_name: "",
    account_holder_name: "",
    upi_id: "",
    is_primary: false,
    is_active: true,
  });
  const [bankEditId, setBankEditId] = useState<string | null>(null);

  const [passwordForm, setPasswordForm] = useState({
    current_password: "",
    new_password: "",
    confirm_password: "",
  });
  const [passwordError, setPasswordError] = useState("");
  const [passwordSuccess, setPasswordSuccess] = useState("");
  const [passwordSaving, setPasswordSaving] = useState(false);

  React.useEffect(() => {
    if (companyData) {
      setCompanyForm({
        legal_name: companyData.legal_name || "",
        trade_name: companyData.trade_name || "",
        gstin: companyData.gstin || "",
        pan: companyData.pan || "",
        financial_year_start: companyData.financial_year_start
          ? new Date(companyData.financial_year_start).toISOString().split("T")[0]
          : "",
        cin: (companyData as any).cin || "",
      });
    }
  }, [companyData]);

  React.useEffect(() => {
    if (settings) {
      setSettingsForm({
        logo_url: settings.logo_url || "",
        gst_enabled: settings.gst_enabled || false,
        e_invoicing_enabled: settings.e_invoicing_enabled || false,
        e_invoice_username: settings.e_invoice_username || "",
        e_way_bill_username: settings.e_way_bill_username || "",
        origin_state_code: settings.origin_state_code || "",
      });
    }
  }, [settings]);

  const companyMutation = useMutation({
    mutationFn: async (data: typeof companyForm) => {
      return apiClient.put(`/companies/${getActiveTenantId()}`, data);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["company"] });
      console.log("Company settings saved successfully");
    },
  });

  const settingsMutation = useMutation({
    mutationFn: async (data: typeof settingsForm) => {
      return apiClient.put("/settings", data);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings"] });
      console.log("Settings saved successfully");
    },
  });

  const seriesMutation = useMutation({
    mutationFn: async (data: Partial<SeriesItem>) => {
      if (data.id) {
        return apiClient.put(`/settings/series/${data.id}`, data);
      } else {
        return apiClient.post("/settings/series", data);
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["series"] });
      setSeriesEditId(null);
      setSeriesEdit({});
      console.log("Series saved successfully");
    },
  });

  const bankMutation = useMutation({
    mutationFn: async (data: Partial<BankingProfile>) => {
      if (bankEditId) {
        return apiClient.put(`/masters/banking-profiles/${bankEditId}`, data);
      } else {
        return apiClient.post("/masters/banking-profiles", data);
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["banking-profiles"] });
      setBankEditId(null);
      setBankForm({
        bank_name: "",
        account_number: "",
        ifsc_code: "",
        branch_name: "",
        account_holder_name: "",
        upi_id: "",
        is_primary: false,
        is_active: true,
      });
      console.log("Banking profile saved successfully");
    },
  });

  const bankDeleteMutation = useMutation({
    mutationFn: async (id: string) => {
      return apiClient.delete(`/masters/banking-profiles/${id}`);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["banking-profiles"] });
      console.log("Banking profile deleted successfully");
    },
  });

  const handleCompanySave = () => {
    companyMutation.mutate(companyForm);
  };

  const handleSettingsSave = () => {
    settingsMutation.mutate(settingsForm);
  };

  const handleSeriesEdit = (item: SeriesItem) => {
    setSeriesEditId(item.id);
    setSeriesEdit({ ...item });
  };

  const handleSeriesSave = () => {
    if (seriesEditId) {
      seriesMutation.mutate(seriesEdit as SeriesItem);
    }
  };

  const handleSeriesCancel = () => {
    setSeriesEditId(null);
    setSeriesEdit({});
  };

  const handleSeriesChange = (field: keyof SeriesItem, value: any) => {
    setSeriesEdit((prev) => ({ ...prev, [field]: value }));
  };

  const handleBankEdit = (profile: BankingProfile) => {
    setBankEditId(profile.id);
    setBankForm({ ...profile });
  };

  const handleBankSave = () => {
    bankMutation.mutate(bankForm);
  };

  const handleBankDelete = (id: string) => {
    if (confirm("Are you sure you want to delete this banking profile?")) {
      bankDeleteMutation.mutate(id);
    }
  };

  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    setPasswordError("");
    setPasswordSuccess("");
    if (passwordForm.new_password !== passwordForm.confirm_password) {
      setPasswordError("New passwords do not match");
      return;
    }
    if (passwordForm.new_password.length < 8) {
      setPasswordError("Password must be at least 8 characters");
      return;
    }
    setPasswordSaving(true);
    try {
      await apiClient.post("/auth/change-password", {
        current_password: passwordForm.current_password,
        new_password: passwordForm.new_password,
      });
      setPasswordForm({ current_password: "", new_password: "", confirm_password: "" });
      setPasswordSuccess("Password changed successfully.");
    } catch (err: any) {
      setPasswordError(err.response?.data?.detail || "Failed to change password.");
    } finally {
      setPasswordSaving(false);
    }
  };

  const isLoading =
    companyLoading ||
    settingsLoading ||
    profileLoading ||
    seriesLoading ||
    bankingLoading ||
    auditLoading;

  const renderTabContent = () => {
    switch (activeTab) {
      case "company":
        return (
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-slate-900">Company Details</h2>
                <p className="text-sm text-slate-500 mt-1">Manage your company information and registration details</p>
              </div>
              <button
                onClick={handleCompanySave}
                disabled={companyMutation.isPending}
                className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold text-sm transition disabled:opacity-50"
              >
                <Save className="w-4 h-4" />
                {companyMutation.isPending ? "Saving..." : "Save Changes"}
              </button>
            </div>

            <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Legal Name</label>
                  <input
                    type="text"
                    value={companyForm.legal_name}
                    onChange={(e) => setCompanyForm((p) => ({ ...p, legal_name: e.target.value }))}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Trade Name</label>
                  <input
                    type="text"
                    value={companyForm.trade_name}
                    onChange={(e) => setCompanyForm((p) => ({ ...p, trade_name: e.target.value }))}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">GSTIN</label>
                  <input
                    type="text"
                    value={companyForm.gstin}
                    onChange={(e) => setCompanyForm((p) => ({ ...p, gstin: e.target.value.toUpperCase() }))}
                    placeholder="27AABCU9603R1ZM"
                    maxLength={15}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">PAN</label>
                  <input
                    type="text"
                    value={companyForm.pan}
                    onChange={(e) => setCompanyForm((p) => ({ ...p, pan: e.target.value.toUpperCase() }))}
                    placeholder="AABCU9603R"
                    maxLength={10}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">CIN</label>
                  <input
                    type="text"
                    value={companyForm.cin}
                    onChange={(e) => setCompanyForm((p) => ({ ...p, cin: e.target.value.toUpperCase() }))}
                    placeholder="U74999MH2021PTC123456"
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Financial Year Start</label>
                  <input
                    type="date"
                    value={companyForm.financial_year_start}
                    onChange={(e) => setCompanyForm((p) => ({ ...p, financial_year_start: e.target.value }))}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>
              </div>
            </div>
          </div>
        );

      case "profile":
        return (
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-slate-900">User Profile</h2>
                <p className="text-sm text-slate-500 mt-1">View your account information</p>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-6">
              <div className="space-y-6">
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Full Name</label>
                  <input
                    type="text"
                    value={userProfile?.full_name || ""}
                    readOnly
                    className="w-full px-3 py-2 border border-slate-100 bg-slate-50 rounded-lg text-sm text-slate-700"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Email Address</label>
                  <input
                    type="email"
                    value={userProfile?.email || ""}
                    readOnly
                    className="w-full px-3 py-2 border border-slate-100 bg-slate-50 rounded-lg text-sm text-slate-700"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Phone Number</label>
                  <input
                    type="text"
                    value={userProfile?.phone_number || ""}
                    readOnly
                    className="w-full px-3 py-2 border border-slate-100 bg-slate-50 rounded-lg text-sm text-slate-700"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Account Status</label>
                  <div>
                    <span
                      className={`inline-flex items-center px-2.5 py-1 text-xs font-semibold rounded-full ${
                        userProfile?.is_active
                          ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                          : "bg-rose-50 text-rose-700 border border-rose-200"
                      }`}
                    >
                      {userProfile?.is_active ? "Active" : "Inactive"}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        );

      case "gst":
        return (
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-slate-900">GST & Tax Settings</h2>
                <p className="text-sm text-slate-500 mt-1">Configure GST and e-invoicing preferences</p>
              </div>
              <button
                onClick={handleSettingsSave}
                disabled={settingsMutation.isPending}
                className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold text-sm transition disabled:opacity-50"
              >
                <Save className="w-4 h-4" />
                {settingsMutation.isPending ? "Saving..." : "Save Changes"}
              </button>
            </div>

            <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-6">
              <div className="space-y-6">
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Company Logo</label>
                  <LogoUploader
                    currentLogo={settingsForm.logo_url}
                    onUpload={(url) => setSettingsForm((p) => ({ ...p, logo_url: url }))}
                    onRemove={() => setSettingsForm((p) => ({ ...p, logo_url: "" }))}
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Origin State Code</label>
                  <select
                    value={settingsForm.origin_state_code}
                    onChange={(e) => setSettingsForm((p) => ({ ...p, origin_state_code: e.target.value }))}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
                  >
                    <option value="">-- Select State --</option>
                    {STATE_CODES.map((s) => (
                      <option key={s.code} value={s.code}>
                        {s.name} ({s.code})
                      </option>
                    ))}
                  </select>
                </div>

                <div className="flex items-center justify-between py-3 border-t border-slate-100">
                  <div>
                    <span className="font-semibold text-sm text-slate-700">GST Enabled</span>
                    <p className="text-xs text-slate-500 mt-0.5">Enable GST calculations and reporting</p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setSettingsForm((p) => ({ ...p, gst_enabled: !p.gst_enabled }))}
                    className={`relative w-11 h-6 rounded-full transition-colors ${
                      settingsForm.gst_enabled ? "bg-brand-600" : "bg-slate-200"
                    }`}
                  >
                    <span
                      className={`absolute top-1 left-1 w-4 h-4 bg-white rounded-full shadow transition-transform ${
                        settingsForm.gst_enabled ? "translate-x-5" : ""
                      }`}
                    />
                  </button>
                </div>

                <div className="flex items-center justify-between py-3 border-t border-slate-100">
                  <div>
                    <span className="font-semibold text-sm text-slate-700">E-Invoicing Enabled</span>
                    <p className="text-xs text-slate-500 mt-0.5">Enable GST e-invoice generation via IRP</p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setSettingsForm((p) => ({ ...p, e_invoicing_enabled: !p.e_invoicing_enabled }))}
                    className={`relative w-11 h-6 rounded-full transition-colors ${
                      settingsForm.e_invoicing_enabled ? "bg-brand-600" : "bg-slate-200"
                    }`}
                  >
                    <span
                      className={`absolute top-1 left-1 w-4 h-4 bg-white rounded-full shadow transition-transform ${
                        settingsForm.e_invoicing_enabled ? "translate-x-5" : ""
                      }`}
                    />
                  </button>
                </div>

                {settingsForm.e_invoicing_enabled && (
                  <>
                    <div className="space-y-2">
                      <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">E-Invoice Username</label>
                      <input
                        type="text"
                        value={settingsForm.e_invoice_username}
                        onChange={(e) => setSettingsForm((p) => ({ ...p, e_invoice_username: e.target.value }))}
                        className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                      />
                    </div>

                    <div className="space-y-2">
                      <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">E-Way Bill Username</label>
                      <input
                        type="text"
                        value={settingsForm.e_way_bill_username}
                        onChange={(e) => setSettingsForm((p) => ({ ...p, e_way_bill_username: e.target.value }))}
                        className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                      />
                    </div>
                  </>
                )}
              </div>
            </div>
          </div>
        );

      case "invoice":
        return (
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-slate-900">Invoice Numbering Series</h2>
                <p className="text-sm text-slate-500 mt-1">Configure document numbering patterns</p>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
              <table className="w-full border-collapse text-left text-sm">
                <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                  <tr>
                    <th className="px-6 py-3.5">Document Type</th>
                    <th className="px-6 py-3.5">Prefix</th>
                    <th className="px-6 py-3.5">Next Number</th>
                    <th className="px-6 py-3.5">Suffix</th>
                    <th className="px-6 py-3.5">Padding</th>
                    <th className="px-6 py-3.5">Status</th>
                    <th className="px-6 py-3.5">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {DOC_TYPES.map((docType) => {
                    const item = seriesList.find((s) => s.document_type === docType);
                    const isEditing = seriesEditId === item?.id;
                    return (
                      <tr key={docType} className="hover:bg-slate-50/50 transition">
                        <td className="px-6 py-4 font-semibold text-slate-700">{docType}</td>
                        {isEditing ? (
                          <>
                            <td className="px-6 py-4">
                              <input
                                type="text"
                                value={seriesEdit.prefix || ""}
                                onChange={(e) => handleSeriesChange("prefix", e.target.value)}
                                className="w-24 px-2 py-1 border border-slate-200 rounded text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                              />
                            </td>
                            <td className="px-6 py-4">
                              <input
                                type="number"
                                value={seriesEdit.next_number || 1}
                                onChange={(e) => handleSeriesChange("next_number", parseInt(e.target.value) || 1)}
                                className="w-20 px-2 py-1 border border-slate-200 rounded text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                              />
                            </td>
                            <td className="px-6 py-4">
                              <input
                                type="text"
                                value={seriesEdit.suffix || ""}
                                onChange={(e) => handleSeriesChange("suffix", e.target.value)}
                                className="w-20 px-2 py-1 border border-slate-200 rounded text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                              />
                            </td>
                            <td className="px-6 py-4">
                              <input
                                type="number"
                                min={1}
                                max={10}
                                value={seriesEdit.padding_digits || 4}
                                onChange={(e) => handleSeriesChange("padding_digits", parseInt(e.target.value) || 4)}
                                className="w-16 px-2 py-1 border border-slate-200 rounded text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                              />
                            </td>
                            <td className="px-6 py-4">
                              <button
                                onClick={handleSeriesSave}
                                className="text-brand-600 hover:text-brand-700 text-xs font-semibold mr-2"
                              >
                                Save
                              </button>
                              <button
                                onClick={handleSeriesCancel}
                                className="text-slate-500 hover:text-slate-700 text-xs font-semibold"
                              >
                                Cancel
                              </button>
                            </td>
                          </>
                        ) : (
                          <>
                            <td className="px-6 py-4 font-mono text-slate-600">{item?.prefix || "-"}</td>
                            <td className="px-6 py-4 font-mono text-slate-600">{item?.next_number || "-"}</td>
                            <td className="px-6 py-4 font-mono text-slate-600">{item?.suffix || "-"}</td>
                            <td className="px-6 py-4 font-mono text-slate-600">{item?.padding_digits || "-"}</td>
                            <td className="px-6 py-4">
                              <span
                                className={`px-2 py-1 text-xs font-semibold rounded-full ${
                                  item?.is_active
                                    ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                                    : "bg-slate-100 text-slate-600 border border-slate-200"
                                }`}
                              >
                                {item?.is_active ? "Active" : "Inactive"}
                              </span>
                            </td>
                            <td className="px-6 py-4">
                              <button
                                onClick={() => item && handleSeriesEdit(item)}
                                className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition"
                              >
                                <Edit className="w-4 h-4" />
                              </button>
                            </td>
                          </>
                        )}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
              {seriesList.length === 0 && !seriesLoading && (
                <div className="text-center py-12 text-sm text-slate-500">
                  No series configured. Series will be auto-created on first document generation.
                </div>
              )}
            </div>
          </div>
        );

      case "bank":
        return (
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-slate-900">Banking & Payment Profiles</h2>
                <p className="text-sm text-slate-500 mt-1">Manage bank accounts and UPI for collections</p>
              </div>
              <button
                onClick={() => {
                  setBankEditId(null);
                  setBankForm({
                    bank_name: "",
                    account_number: "",
                    ifsc_code: "",
                    branch_name: "",
                    account_holder_name: "",
                    upi_id: "",
                    is_primary: false,
                    is_active: true,
                  });
                }}
                className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold text-sm transition"
              >
                <Plus className="w-4 h-4" />
                Add Profile
              </button>
            </div>

            <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
              <table className="w-full border-collapse text-left text-sm">
                <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                  <tr>
                    <th className="px-6 py-3.5">Bank Name</th>
                    <th className="px-6 py-3.5">Account Number</th>
                    <th className="px-6 py-3.5">IFSC Code</th>
                    <th className="px-6 py-3.5">UPI ID</th>
                    <th className="px-6 py-3.5">Type</th>
                    <th className="px-6 py-3.5">Status</th>
                    <th className="px-6 py-3.5">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {bankingProfiles?.map((profile) => (
                    <tr key={profile.id} className="hover:bg-slate-50/50 transition">
                      <td className="px-6 py-4 font-semibold text-slate-700">{profile.bank_name}</td>
                      <td className="px-6 py-4 font-mono text-slate-600">{profile.account_number}</td>
                      <td className="px-6 py-4 font-mono text-slate-600">{profile.ifsc_code}</td>
                      <td className="px-6 py-4 font-mono text-slate-600">{profile.upi_id || "-"}</td>
                      <td className="px-6 py-4">
                        {profile.is_primary && (
                          <span className="px-2 py-1 text-xs font-semibold rounded-full bg-brand-50 text-brand-700 border border-brand-200">
                            Primary
                          </span>
                        )}
                      </td>
                      <td className="px-6 py-4">
                        <span
                          className={`px-2 py-1 text-xs font-semibold rounded-full ${
                            profile.is_active
                              ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                              : "bg-slate-100 text-slate-600 border border-slate-200"
                          }`}
                        >
                          {profile.is_active ? "Active" : "Inactive"}
                        </span>
                      </td>
                      <td className="px-6 py-4">
                        <div className="inline-flex items-center gap-2">
                          <button
                            onClick={() => handleBankEdit(profile)}
                            className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition"
                          >
                            <Edit className="w-4 h-4" />
                          </button>
                          <button
                            onClick={() => handleBankDelete(profile.id)}
                            className="p-1 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded transition"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {bankingProfiles.length === 0 && !bankingLoading && (
                <div className="text-center py-12 text-sm text-slate-500">
                  No banking profiles added yet.
                </div>
              )}
            </div>

            {bankEditId && (
              <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-6">
                <h3 className="font-semibold text-slate-700 mb-4">
                  {bankEditId ? "Edit Banking Profile" : "Add Banking Profile"}
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Bank Name</label>
                    <input
                      type="text"
                      value={bankForm.bank_name}
                      onChange={(e) => setBankForm((p) => ({ ...p, bank_name: e.target.value }))}
                      className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Account Number</label>
                    <input
                      type="text"
                      value={bankForm.account_number}
                      onChange={(e) => setBankForm((p) => ({ ...p, account_number: e.target.value }))}
                      className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">IFSC Code</label>
                    <input
                      type="text"
                      value={bankForm.ifsc_code}
                      onChange={(e) => setBankForm((p) => ({ ...p, ifsc_code: e.target.value.toUpperCase() }))}
                      className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Branch Name</label>
                    <input
                      type="text"
                      value={bankForm.branch_name}
                      onChange={(e) => setBankForm((p) => ({ ...p, branch_name: e.target.value }))}
                      className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Account Holder Name</label>
                    <input
                      type="text"
                      value={bankForm.account_holder_name}
                      onChange={(e) => setBankForm((p) => ({ ...p, account_holder_name: e.target.value }))}
                      className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                    />
                  </div>
                  <div className="space-y-2">
                    <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">UPI ID</label>
                    <input
                      type="text"
                      value={bankForm.upi_id}
                      onChange={(e) => setBankForm((p) => ({ ...p, upi_id: e.target.value }))}
                      placeholder="yourname@upi"
                      className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                    />
                  </div>
                  <div className="flex items-center gap-3">
                    <input
                      type="checkbox"
                      id="is_primary"
                      checked={bankForm.is_primary}
                      onChange={(e) => setBankForm((p) => ({ ...p, is_primary: e.target.checked }))}
                      className="w-4 h-4 text-brand-600 border-slate-300 rounded focus:ring-brand-500"
                    />
                    <label htmlFor="is_primary" className="text-sm text-slate-700">
                      Set as Primary Account
                    </label>
                  </div>
                </div>
                <div className="flex justify-end gap-3 mt-6">
                  <button
                    onClick={() => {
                      setBankEditId(null);
                      setBankForm({
                        bank_name: "",
                        account_number: "",
                        ifsc_code: "",
                        branch_name: "",
                        account_holder_name: "",
                        upi_id: "",
                        is_primary: false,
                        is_active: true,
                      });
                    }}
                    className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleBankSave}
                    disabled={bankMutation.isPending}
                    className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50"
                  >
                    {bankMutation.isPending ? "Saving..." : "Save Profile"}
                  </button>
                </div>
              </div>
            )}
          </div>
        );

      case "security":
        return (
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-slate-900">Security Settings</h2>
                <p className="text-sm text-slate-500 mt-1">Manage your account security</p>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-6">
              <h3 className="font-semibold text-slate-700 mb-4">Last Login Information</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Last Login</label>
                  <p className="px-3 py-2 bg-slate-50 border border-slate-100 rounded-lg text-sm text-slate-700">
                    {userProfile?.is_active ? new Date().toLocaleString("en-IN") : "N/A"}
                  </p>
                </div>
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Session Status</label>
                  <p className="px-3 py-2 bg-emerald-50 border border-emerald-100 rounded-lg text-sm text-emerald-700 font-semibold">
                    Active
                  </p>
                </div>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-6">
              <h3 className="font-semibold text-slate-700 mb-4">Change Password</h3>

              <form onSubmit={handlePasswordChange} className="space-y-4">
                {passwordSuccess && (
                  <div className="flex items-center gap-3 p-4 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-lg">
                    <span className="text-sm">{passwordSuccess}</span>
                  </div>
                )}
                {passwordError && (
                  <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
                    <ShieldAlert className="w-5 h-5 flex-shrink-0" />
                    <span className="text-sm">{passwordError}</span>
                  </div>
                )}

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Current Password</label>
                  <input
                    type="password"
                    value={passwordForm.current_password}
                    onChange={(e) => setPasswordForm((p) => ({ ...p, current_password: e.target.value }))}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">New Password</label>
                  <input
                    type="password"
                    value={passwordForm.new_password}
                    onChange={(e) => setPasswordForm((p) => ({ ...p, new_password: e.target.value }))}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Confirm New Password</label>
                  <input
                    type="password"
                    value={passwordForm.confirm_password}
                    onChange={(e) => setPasswordForm((p) => ({ ...p, confirm_password: e.target.value }))}
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>

                <button
                  type="submit"
                  disabled={passwordSaving}
                  className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50"
                >
                  {passwordSaving ? "Saving..." : "Update Password"}
                </button>
              </form>
            </div>
          </div>
        );

      case "audit":
        const totalAuditPages = auditData?.total ? Math.ceil(auditData.total / auditPageSize) : 1;
        return (
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-xl font-bold text-slate-900">Audit Logs</h2>
                <p className="text-sm text-slate-500 mt-1">Track user activities and system changes</p>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-slate-100 shadow-sm overflow-hidden">
              <table className="w-full border-collapse text-left text-sm">
                <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                  <tr>
                    <th className="px-6 py-3.5">Timestamp</th>
                    <th className="px-6 py-3.5">User</th>
                    <th className="px-6 py-3.5">Action</th>
                    <th className="px-6 py-3.5">Resource</th>
                    <th className="px-6 py-3.5">IP Address</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {auditData?.data?.map((log) => (
                    <tr key={log.id} className="hover:bg-slate-50/50 transition">
                      <td className="px-6 py-4 text-slate-500">
                        {new Date(log.created_at).toLocaleString("en-IN")}
                      </td>
                      <td className="px-6 py-4 font-medium text-slate-700">{log.actor_email}</td>
                      <td className="px-6 py-4">
                        <span className="px-2 py-1 text-xs font-semibold rounded-full bg-slate-100 text-slate-600 border border-slate-200">
                          {log.action}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-slate-600">{log.resource}</td>
                      <td className="px-6 py-4 font-mono text-slate-500">{log.ip_address}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {(!auditData?.data || auditData.data.length === 0) && !auditLoading && (
                <div className="text-center py-12 text-sm text-slate-500">
                  No audit logs found.
                </div>
              )}
            </div>

            {totalAuditPages > 1 && (
              <div className="flex items-center justify-between">
                <span className="text-sm text-slate-500">
                  Page {auditPage} of {totalAuditPages}
                </span>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setAuditPage((p) => Math.max(1, p - 1))}
                    disabled={auditPage === 1}
                    className="p-2 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition disabled:opacity-30 disabled:hover:bg-transparent"
                  >
                    <ChevronLeft className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => setAuditPage((p) => Math.min(totalAuditPages, p + 1))}
                    disabled={auditPage === totalAuditPages}
                    className="p-2 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition disabled:opacity-30 disabled:hover:bg-transparent"
                  >
                    <ChevronRight className="w-4 h-4" />
                  </button>
                </div>
              </div>
            )}
          </div>
        );

      default:
        return null;
    }
  };

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  return (
    <div className="flex gap-6 h-full">
      <div className="w-56 flex-shrink-0">
        <div className="bg-white rounded-xl border border-slate-100 shadow-sm p-2 sticky top-6">
          <nav className="space-y-1">
            {TABS.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition ${
                  activeTab === tab.id
                    ? "bg-brand-50 text-brand-700"
                    : "text-slate-600 hover:bg-slate-50 hover:text-slate-900"
                }`}
              >
                {tab.icon}
                {tab.label}
              </button>
            ))}
          </nav>
        </div>
      </div>

      <div className="flex-1 min-w-0">
        <div className="bg-slate-50 rounded-xl p-6 min-h-[calc(100vh-12rem)]">{renderTabContent()}</div>
      </div>
    </div>
  );
}