import React from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Edit, AlertTriangle, Mail, Phone, MapPin } from "lucide-react";

interface ContactDetailProps {
  contactId: string;
  onNavigate: (view: "list" | "create" | "edit" | "detail", contactId?: string) => void;
}

interface AddressDisplay {
  street: string;
  city: string;
  state: string;
  pincode: string;
}

export default function ContactDetail({ contactId, onNavigate }: ContactDetailProps) {
  const { data: contact, isLoading, error } = useQuery({
    queryKey: ["contact", contactId],
    queryFn: async () => {
      const res = await apiClient.get(`/masters/contacts/${contactId}`);
      return res.data;
    },
  });

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (error || !contact) {
    return (
      <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
        <AlertTriangle className="w-5 h-5 flex-shrink-0" />
        <span>Error retrieving contact details.</span>
      </div>
    );
  }

  const renderAddress = (label: string, addr: AddressDisplay | null) => {
    if (!addr) return <p className="text-sm text-slate-400 italic">Not provided</p>;
    return (
      <div className="text-sm text-slate-600 space-y-0.5">
        <p className="font-medium text-slate-700">{addr.street}</p>
        <p>{addr.city}, {addr.state} - {addr.pincode}</p>
      </div>
    );
  };

  const getTypeBadge = (type: string) => {
    const base = "px-2.5 py-1 text-xs font-semibold rounded-full";
    switch (type) {
      case "CUSTOMER":
        return `${base} bg-blue-50 text-blue-700 border border-blue-200`;
      case "VENDOR":
        return `${base} bg-purple-50 text-purple-700 border border-purple-200`;
      case "BOTH":
        return `${base} bg-teal-50 text-teal-700 border border-teal-200`;
      default:
        return `${base} bg-slate-100 text-slate-700`;
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div className="flex items-center gap-3">
          <button
            onClick={() => onNavigate("list")}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-xl font-bold text-slate-900">{contact.name}</h1>
          <span className={getTypeBadge(contact.contact_type)}>
            {contact.contact_type}
          </span>
          <span className={`px-2.5 py-0.5 text-xs font-semibold rounded-full border ${
            contact.is_active
              ? "bg-emerald-50 text-emerald-700 border-emerald-200"
              : "bg-rose-50 text-rose-700 border-rose-200"
          }`}>
            {contact.is_active ? "Active" : "Inactive"}
          </span>
        </div>

        <button
          onClick={() => onNavigate("edit", contactId)}
          disabled={!contact.is_active}
          className="inline-flex items-center gap-1.5 px-4 py-1.5 text-sm font-semibold bg-brand-600 hover:bg-brand-700 text-white rounded-lg transition shadow-sm disabled:opacity-50"
        >
          <Edit className="w-4 h-4" />
          Edit
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-4">
          <h3 className="font-semibold text-sm text-slate-700 pb-2 border-b border-slate-100">Contact Information</h3>

          <div className="space-y-3">
            <div className="flex items-start gap-3">
              <Mail className="w-4 h-4 text-slate-400 mt-0.5" />
              <div>
                <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">Email</span>
                <span className="text-sm text-slate-700">{contact.email || "—"}</span>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <Phone className="w-4 h-4 text-slate-400 mt-0.5" />
              <div>
                <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">Phone</span>
                <span className="text-sm text-slate-700">{contact.phone || "—"}</span>
              </div>
            </div>

            <div className="flex items-start gap-3">
              <MapPin className="w-4 h-4 text-slate-400 mt-0.5" />
              <div>
                <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">State Code</span>
                <span className="text-sm text-slate-700 font-mono">{contact.state_code || "—"}</span>
              </div>
            </div>
          </div>
        </div>

        <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-4">
          <h3 className="font-semibold text-sm text-slate-700 pb-2 border-b border-slate-100">Tax Information</h3>

          <div className="space-y-3">
            <div>
              <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">GSTIN</span>
              <span className="text-sm text-slate-700 font-mono">{contact.gstin || "—"}</span>
            </div>

            <div>
              <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">PAN</span>
              <span className="text-sm text-slate-700 font-mono">{contact.pan || "—"}</span>
            </div>

            <div>
              <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">Registration Type</span>
              <span className="text-sm text-slate-700">{contact.registration_type || "CONSUMER"}</span>
            </div>
          </div>
        </div>

        <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-4">
          <h3 className="font-semibold text-sm text-slate-700 pb-2 border-b border-slate-100">Billing Address</h3>
          {renderAddress("Billing", contact.billing_address)}
        </div>

        <div className="bg-white p-6 rounded-xl border border-slate-100 shadow-sm space-y-4">
          <h3 className="font-semibold text-sm text-slate-700 pb-2 border-b border-slate-100">Shipping Address</h3>
          {renderAddress("Shipping", contact.shipping_address)}
        </div>
      </div>

      <div className="text-xs text-slate-400 text-right">
        Created on {new Date(contact.created_at).toLocaleDateString("en-IN")}
        {contact.updated_at && ` · Updated on ${new Date(contact.updated_at).toLocaleDateString("en-IN")}`}
      </div>
    </div>
  );
}
