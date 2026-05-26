import React, { useState, useEffect } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, AlertCircle, ShieldCheck } from "lucide-react";
import { useUnsavedChangesWarning } from "../../hooks/useUnsavedChangesWarning";

interface ContactFormProps {
  editId?: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail", contactId?: string) => void;
  onSuccess: () => void;
}

interface Address {
  street: string;
  city: string;
  state: string;
  pincode: string;
}

const STATE_CODES = [
  { code: "01", name: "Jammu & Kashmir (01)" },
  { code: "02", name: "Himachal Pradesh (02)" },
  { code: "03", name: "Punjab (03)" },
  { code: "04", name: "Chandigarh (04)" },
  { code: "05", name: "Uttarakhand (05)" },
  { code: "06", name: "Haryana (06)" },
  { code: "07", name: "Delhi (07)" },
  { code: "08", name: "Rajasthan (08)" },
  { code: "09", name: "Uttar Pradesh (09)" },
  { code: "10", name: "Bihar (10)" },
  { code: "11", name: "Sikkim (11)" },
  { code: "12", name: "Arunachal Pradesh (12)" },
  { code: "13", name: "Nagaland (13)" },
  { code: "14", name: "Manipur (14)" },
  { code: "15", name: "Mizoram (15)" },
  { code: "16", name: "Tripura (16)" },
  { code: "17", name: "Meghalaya (17)" },
  { code: "18", name: "Assam (18)" },
  { code: "19", name: "West Bengal (19)" },
  { code: "20", name: "Jharkhand (20)" },
  { code: "21", name: "Odisha (21)" },
  { code: "22", name: "Chhattisgarh (22)" },
  { code: "23", name: "Madhya Pradesh (23)" },
  { code: "24", name: "Gujarat (24)" },
  { code: "25", name: "Daman & Diu (25)" },
  { code: "26", name: "Dadra & Nagar Haveli (26)" },
  { code: "27", name: "Maharashtra (27)" },
  { code: "28", name: "Andhra Pradesh (Old) (28)" },
  { code: "29", name: "Karnataka (29)" },
  { code: "30", name: "Goa (30)" },
  { code: "31", name: "Lakshadweep (31)" },
  { code: "32", name: "Kerala (32)" },
  { code: "33", name: "Tamil Nadu (33)" },
  { code: "34", name: "Puducherry (34)" },
  { code: "35", name: "Andaman & Nicobar (35)" },
  { code: "36", name: "Telangana (36)" },
  { code: "37", name: "Andhra Pradesh (37)" },
  { code: "38", name: "Ladakh (38)" },
];

const REGISTRATION_TYPES = [
  { value: "REGULAR", label: "Regular" },
  { value: "COMPOSITION", label: "Composition" },
  { value: "SEZ", label: "SEZ" },
  { value: "UNREGISTERED", label: "Unregistered" },
  { value: "CONSUMER", label: "Consumer" },
];

export default function ContactForm({ editId, onNavigate, onSuccess }: ContactFormProps) {
  const isEdit = !!editId;

  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [contactType, setContactType] = useState("CUSTOMER");
  const [gstin, setGstin] = useState("");
  const [pan, setPan] = useState("");
  const [registrationType, setRegistrationType] = useState("CONSUMER");
  const [stateCode, setStateCode] = useState("27");

  const [billingStreet, setBillingStreet] = useState("");
  const [billingCity, setBillingCity] = useState("");
  const [billingState, setBillingState] = useState("");
  const [billingPincode, setBillingPincode] = useState("");

  const [sameAsBilling, setSameAsBilling] = useState(true);
  const [shippingStreet, setShippingStreet] = useState("");
  const [shippingCity, setShippingCity] = useState("");
  const [shippingState, setShippingState] = useState("");
  const [shippingPincode, setShippingPincode] = useState("");

  const [formError, setFormError] = useState("");
  const [verifyLoading, setVerifyLoading] = useState(false);
  const [captchaImage, setCaptchaImage] = useState("");
  const [captchaSession, setCaptchaSession] = useState("");
  const [captchaInput, setCaptchaInput] = useState("");
  const [showCaptchaModal, setShowCaptchaModal] = useState(false);
  const [verifySuccess, setVerifySuccess] = useState("");

  const hasUnsavedChanges = name !== "" || email !== "" || phone !== "";
  useUnsavedChangesWarning(hasUnsavedChanges);

  const { data: contact } = useQuery({
    queryKey: ["contact", editId],
    queryFn: async () => {
      const res = await apiClient.get(`/masters/contacts/${editId}`);
      return res.data;
    },
    enabled: isEdit,
  });

  useEffect(() => {
    if (contact && isEdit) {
      setName(contact.name);
      setEmail(contact.email || "");
      setPhone(contact.phone || "");
      setContactType(contact.contact_type);
      setGstin(contact.gstin || "");
      setPan(contact.pan || "");
      setRegistrationType(contact.registration_type || "CONSUMER");
      setStateCode(contact.state_code);

      if (contact.billing_address) {
        setBillingStreet(contact.billing_address.street || "");
        setBillingCity(contact.billing_address.city || "");
        setBillingState(contact.billing_address.state || "");
        setBillingPincode(contact.billing_address.pincode || "");
      }

      if (contact.shipping_address) {
        setSameAsBilling(false);
        setShippingStreet(contact.shipping_address.street || "");
        setShippingCity(contact.shipping_address.city || "");
        setShippingState(contact.shipping_address.state || "");
        setShippingPincode(contact.shipping_address.pincode || "");
      }
    }
  }, [contact, isEdit]);

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload: any = {
        name,
        contact_type: contactType,
        registration_type: registrationType,
        state_code: stateCode,
        billing_address: {
          street: billingStreet,
          city: billingCity,
          state: billingState,
          state_code: stateCode,
          pincode: billingPincode,
        },
      };

      if (email) payload.email = email;
      if (phone) payload.phone = phone;
      if (gstin) payload.gstin = gstin;
      if (pan) payload.pan = pan;

      if (!sameAsBilling && (shippingStreet || shippingCity || shippingState || shippingPincode)) {
        payload.shipping_address = {
          street: shippingStreet,
          city: shippingCity,
          state: shippingState,
          pincode: shippingPincode,
        };
      }

      if (isEdit) {
        return apiClient.put(`/masters/contacts/${editId}`, payload);
      } else {
        return apiClient.post("/masters/contacts", payload);
      }
    },
    onSuccess: () => {
      onSuccess();
    },
    onError: (err: any) => {
      const msg = err.response?.data?.detail || "Failed to save contact. Ensure API parameters are valid.";
      setFormError(msg);
    },
  });

  const handleVerifyGSTIN = async () => {
    if (!gstin || gstin.length !== 15) {
      setFormError("Enter a valid 15-character GSTIN to verify.");
      return;
    }
    setVerifyLoading(true);
    setFormError("");
    setVerifySuccess("");
    try {
      const capResp = await apiClient.get("/gst/verify/captcha");
      setCaptchaImage(capResp.data.image);
      setCaptchaSession(capResp.data.session_id);
      setCaptchaInput("");
      setShowCaptchaModal(true);
    } catch (err: any) {
      setFormError(err.response?.data?.detail || "Failed to fetch captcha.");
    } finally {
      setVerifyLoading(false);
    }
  };

  const handleSubmitCaptcha = async () => {
    if (!captchaInput) return;
    setVerifyLoading(true);
    setFormError("");
    try {
      const resp = await apiClient.post("/gst/verify", {
        gstin,
        captcha: captchaInput,
        session_id: captchaSession,
      });
      const data = resp.data;
      if (data.legal_name) setName(data.legal_name);
      if (data.trade_name && !name) setName(data.trade_name);
      if (data.state_code) setStateCode(data.state_code);
      if (data.address) {
        const parts = data.address.split(",").map((s: string) => s.trim());
        setBillingStreet(parts[0] || "");
        setBillingCity(parts[1] || "");
        setBillingState(parts[2] || data.state_code || "");
      }
      setShowCaptchaModal(false);
      setVerifySuccess("GSTIN verified ✓");
    } catch (err: any) {
      setFormError(err.response?.data?.detail || "GSTIN verification failed.");
    } finally {
      setVerifyLoading(false);
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    if (!name.trim()) {
      setFormError("Name is required.");
      return;
    }
    if (!contactType) {
      setFormError("Contact type is required.");
      return;
    }
    if (!stateCode) {
      setFormError("State code is required.");
      return;
    }
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      setFormError("Please enter a valid email address.");
      return;
    }
    if (!billingStreet.trim() || !billingCity.trim() || !billingState.trim() || !billingPincode.trim()) {
      setFormError("Billing address is incomplete. All fields are required.");
      return;
    }

    saveMutation.mutate();
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => onNavigate("list")}
          className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900">
          {isEdit ? "Edit Contact" : "Create Contact"}
        </h1>
      </div>

      {formError && (
        <div className="flex items-start gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-sm">
            <span className="font-semibold">Validation Error:</span> {formError}
          </div>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 bg-white p-6 rounded-xl border border-slate-100 shadow-sm">
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Name</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Contact name"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="email@example.com"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Phone</label>
            <input
              type="text"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+91-9876543210"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Contact Type</label>
            <select
              value={contactType}
              onChange={(e) => setContactType(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            >
              <option value="CUSTOMER">Customer</option>
              <option value="VENDOR">Vendor</option>
              <option value="BOTH">Both</option>
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Registration Type</label>
            <select
              value={registrationType}
              onChange={(e) => setRegistrationType(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              {REGISTRATION_TYPES.map((rt) => (
                <option key={rt.value} value={rt.value}>{rt.label}</option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">State Code</label>
            <select
              value={stateCode}
              onChange={(e) => setStateCode(e.target.value)}
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              required
            >
              {STATE_CODES.map((s) => (
                <option key={s.code} value={s.code}>{s.name}</option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">GSTIN</label>
            <div className="flex gap-2">
              <input
                type="text"
                value={gstin}
                onChange={(e) => setGstin(e.target.value.toUpperCase())}
                placeholder="22AAAAA0000A1Z5"
                className="flex-1 px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono uppercase"
              />
              <button
                type="button"
                onClick={handleVerifyGSTIN}
                disabled={verifyLoading || gstin.length !== 15}
                className="px-3 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-xs font-semibold disabled:opacity-50 transition flex items-center gap-1.5"
              >
                <ShieldCheck className="w-4 h-4" />
                {verifyLoading ? "..." : "Verify"}
              </button>
            </div>
            {verifySuccess && <p className="text-xs text-emerald-600 font-semibold mt-1">{verifySuccess}</p>}
          </div>

          <div className="space-y-2">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">PAN</label>
            <input
              type="text"
              value={pan}
              onChange={(e) => setPan(e.target.value)}
              placeholder="AAAAA0000A"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>
        </div>

        <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-4">
          <h3 className="font-semibold text-sm text-slate-700">Billing Address</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-2">
              <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Street</label>
              <input
                type="text"
                value={billingStreet}
                onChange={(e) => setBillingStreet(e.target.value)}
                placeholder="Street address"
                className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                required
              />
            </div>
            <div className="space-y-2">
              <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">City</label>
              <input
                type="text"
                value={billingCity}
                onChange={(e) => setBillingCity(e.target.value)}
                placeholder="City"
                className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                required
              />
            </div>
            <div className="space-y-2">
              <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">State</label>
              <input
                type="text"
                value={billingState}
                onChange={(e) => setBillingState(e.target.value)}
                placeholder="State"
                className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                required
              />
            </div>
            <div className="space-y-2">
              <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Pincode</label>
              <input
                type="text"
                value={billingPincode}
                onChange={(e) => setBillingPincode(e.target.value)}
                placeholder="Pincode"
                className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                required
              />
            </div>
          </div>
        </div>

        <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-4">
          <div className="flex items-center gap-3">
            <input
              type="checkbox"
              id="sameAsBilling"
              checked={sameAsBilling}
              onChange={(e) => setSameAsBilling(e.target.checked)}
              className="w-4 h-4 rounded border-slate-300 text-brand-600 focus:ring-brand-500"
            />
            <label htmlFor="sameAsBilling" className="text-sm font-semibold text-slate-700">Shipping same as billing</label>
          </div>

          {!sameAsBilling && (
            <div className="space-y-4">
              <h3 className="font-semibold text-sm text-slate-700">Shipping Address</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Street</label>
                  <input
                    type="text"
                    value={shippingStreet}
                    onChange={(e) => setShippingStreet(e.target.value)}
                    placeholder="Street address"
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">City</label>
                  <input
                    type="text"
                    value={shippingCity}
                    onChange={(e) => setShippingCity(e.target.value)}
                    placeholder="City"
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">State</label>
                  <input
                    type="text"
                    value={shippingState}
                    onChange={(e) => setShippingState(e.target.value)}
                    placeholder="State"
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>
                <div className="space-y-2">
                  <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">Pincode</label>
                  <input
                    type="text"
                    value={shippingPincode}
                    onChange={(e) => setShippingPincode(e.target.value)}
                    placeholder="Pincode"
                    className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
                  />
                </div>
              </div>
            </div>
          )}
        </div>

        <div className="flex justify-end gap-3">
          <button
            type="button"
            onClick={() => onNavigate("list")}
            className="px-4 py-2 border border-slate-200 text-slate-700 font-semibold rounded-lg text-sm bg-white hover:bg-slate-50 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={saveMutation.isPending}
            className="px-6 py-2 bg-brand-600 hover:bg-brand-700 text-white font-semibold rounded-lg text-sm shadow-sm transition disabled:opacity-50"
          >
            {saveMutation.isPending ? "Saving..." : isEdit ? "Update Contact" : "Create Contact"}
          </button>
        </div>
      </form>

      {/* Captcha Modal */}
      {showCaptchaModal && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4" onClick={() => setShowCaptchaModal(false)}>
          <div className="bg-white rounded-2xl shadow-xl p-6 max-w-sm w-full" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-sm font-bold text-zinc-900 mb-3">GSTIN Verification</h3>
            <p className="text-xs text-zinc-500 mb-4">Enter the captcha text shown below to verify {gstin}.</p>
            {captchaImage && (
              <img src={captchaImage} alt="Captcha" className="w-full rounded-lg border border-slate-200 mb-4" />
            )}
            <input
              type="text"
              value={captchaInput}
              onChange={(e) => setCaptchaInput(e.target.value)}
              placeholder="Enter captcha text"
              className="w-full px-3 py-2 border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-brand-500 mb-4"
              autoFocus
            />
            <div className="flex justify-end gap-2">
              <button onClick={() => setShowCaptchaModal(false)} className="px-3 py-2 text-xs font-semibold text-zinc-600 hover:bg-zinc-50 rounded-lg transition">Cancel</button>
              <button onClick={handleSubmitCaptcha} disabled={verifyLoading || !captchaInput}
                className="px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-xs font-semibold disabled:opacity-50 transition flex items-center gap-1.5">
                <ShieldCheck className="w-4 h-4" /> {verifyLoading ? "Verifying..." : "Verify"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
