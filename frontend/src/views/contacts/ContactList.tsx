import React, { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { Plus, Search, Users, Eye, Edit, ShieldAlert } from "lucide-react";

interface ContactListProps {
  onNavigate: (view: "list" | "create" | "edit" | "detail", contactId?: string) => void;
}

interface ContactListItem {
  id: string;
  name: string;
  email: string;
  phone: string;
  contact_type: string;
  gstin: string;
  state_code: string;
  is_active: boolean;
  created_at: string;
}

export default function ContactList({ onNavigate }: ContactListProps) {
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("ALL");

  const { data: contacts = [], isLoading, error } = useQuery<ContactListItem[]>({
    queryKey: ["contacts", typeFilter],
    queryFn: async () => {
      const params: any = {};
      if (typeFilter !== "ALL") {
        params.contact_type = typeFilter;
      }
      const res = await apiClient.get("/masters/contacts", { params });
      return res.data;
    },
  });

  const filteredContacts = contacts.filter((c: ContactListItem) => {
    const matchesSearch =
      (c.name || "").toLowerCase().includes(search.toLowerCase()) ||
      (c.phone || "").toLowerCase().includes(search.toLowerCase()) ||
      (c.gstin || "").toLowerCase().includes(search.toLowerCase());
    return matchesSearch;
  });

  return (
    <div className="space-y-6 relative pb-16">
      {/* Desktop Header */}
      <div className="hidden md:flex justify-between items-center pb-2 border-b border-zinc-200">
        <div className="flex items-center gap-6">
          <div>
            <h1 className="text-xl font-bold tracking-tight text-zinc-900">
              Customers & Vendors
            </h1>
            <p className="text-sm text-zinc-500 mt-0.5">Manage contacts and allied parties.</p>
          </div>
          <div className="flex bg-slate-100 p-1 rounded-lg text-xs font-bold text-slate-600">
            <button
              onClick={() => setTypeFilter("CUSTOMER")}
              className={`px-3 py-1.5 rounded-md transition ${
                typeFilter === "CUSTOMER" ? "bg-white text-navy-900 shadow-sm" : "hover:text-navy-900"
              }`}
            >
              Customers
            </button>
            <button
              onClick={() => setTypeFilter("VENDOR")}
              className={`px-3 py-1.5 rounded-md transition ${
                typeFilter === "VENDOR" ? "bg-white text-navy-900 shadow-sm" : "hover:text-navy-900"
              }`}
            >
              Vendors
            </button>
            <button
              onClick={() => setTypeFilter("ALL")}
              className={`px-3 py-1.5 rounded-md transition ${
                typeFilter === "ALL" ? "bg-white text-navy-900 shadow-sm" : "hover:text-navy-900"
              }`}
            >
              All
            </button>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <div className="relative">
            <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
            <input
              type="text"
              placeholder="Search parties by name, phone or GSTIN..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-9 pr-4 py-2 border border-slate-200 rounded-lg text-xs focus:ring-2 focus:ring-[#DCA035] outline-none w-64 bg-white"
            />
          </div>
          <button
            onClick={() => onNavigate("create")}
            className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg text-sm font-semibold shadow-sm transition"
          >
            <Plus className="w-4 h-4" /> Add Party
          </button>
        </div>
      </div>

      {/* Mobile Top Header */}
      <div className="md:hidden bg-[#0B1B3D] text-white p-4 -mx-4 -mt-4 mb-6 border-b border-navy-800 shadow-md">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-bold tracking-tight text-white font-sans">Parties</h1>
          </div>
          <button className="text-zinc-300 hover:text-[#DCA035]">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
            </svg>
          </button>
        </div>

        {/* Tab Controls: Customers, Vendors, All */}
        <div className="flex border-b border-navy-800 -mx-4 px-4 text-center">
          <button
            onClick={() => setTypeFilter("CUSTOMER")}
            className={`flex-1 pb-2.5 text-xs font-bold transition border-b-2 ${
              typeFilter === "CUSTOMER" ? "text-[#DCA035] border-[#DCA035]" : "text-zinc-400 border-transparent"
            }`}
          >
            Customers
          </button>
          <button
            onClick={() => setTypeFilter("VENDOR")}
            className={`flex-1 pb-2.5 text-xs font-bold transition border-b-2 ${
              typeFilter === "VENDOR" ? "text-[#DCA035] border-[#DCA035]" : "text-zinc-400 border-transparent"
            }`}
          >
            Vendors
          </button>
          <button
            onClick={() => setTypeFilter("ALL")}
            className={`flex-1 pb-2.5 text-xs font-bold transition border-b-2 ${
              typeFilter === "ALL" ? "text-[#DCA035] border-[#DCA035]" : "text-zinc-400 border-transparent"
            }`}
          >
            All
          </button>
        </div>

        {/* Search Bar inside Header */}
        <div className="relative mt-4">
          <Search className="absolute left-3 top-2.5 h-4 w-4 text-zinc-400" />
          <input
            type="text"
            placeholder="Search parties by name, phone or GSTIN"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-9 pr-4 py-2 bg-white text-slate-800 rounded-lg text-xs focus:ring-2 focus:ring-brand-500 border-none placeholder-slate-400"
          />
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span>Error loading parties. Please check API server.</span>
        </div>
      ) : filteredContacts.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <Users className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Parties Found</h3>
          <p className="text-xs text-slate-500 mt-1">Try creating a new party to get started.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {filteredContacts.map((c) => {
            return (
              <div 
                key={c.id} 
                className="bg-white p-4 rounded-2xl border border-slate-100 shadow-sm flex items-start gap-4 hover:border-brand-500 transition relative"
              >
                {/* Party Icon */}
                <div className="p-3 bg-slate-50 border border-slate-100 rounded-2xl flex-shrink-0 flex items-center justify-center">
                  <Users className="w-5 h-5 text-[#0B1B3D]" />
                </div>

                {/* Details Panel */}
                <div className="flex-1 min-w-0 space-y-1.5">
                  <h3 className="text-sm font-bold text-slate-800 truncate leading-tight">{c.name}</h3>
                  
                  {/* Phone */}
                  <div className="flex items-center gap-1.5 text-xs text-slate-500">
                    <svg className="w-3.5 h-3.5 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.94.725l.548 2.2a1 1 0 01-.321.988l-1.305.98a10.582 10.582 0 004.872 4.872l.98-1.305a1 1 0 01.988-.321l2.2.548a1 1 0 01.725.94V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                    </svg>
                    <span>{c.phone || "—"}</span>
                  </div>

                  {/* GSTIN */}
                  {c.gstin && (
                    <div className="flex items-center gap-1.5 text-xs text-slate-500 font-mono">
                      <span className="px-1 py-0.5 border border-slate-200 text-slate-400 text-[8px] font-bold rounded">GST</span>
                      <span>{c.gstin}</span>
                    </div>
                  )}

                  {/* Contact Type */}
                  <div className="pt-1">
                    <span className={`px-2 py-0.5 text-[10px] font-bold rounded-full ${
                      c.contact_type === "CUSTOMER" ? "bg-blue-50 text-blue-700 border border-blue-200" :
                      c.contact_type === "VENDOR" ? "bg-purple-50 text-purple-700 border border-purple-200" :
                      "bg-teal-50 text-teal-700 border border-teal-200"
                    }`}>
                      {c.contact_type}
                    </span>
                  </div>
                </div>

                {/* Action Buttons */}
                <div className="flex flex-col items-center gap-2">
                  <button
                    onClick={() => onNavigate("edit", c.id)}
                    aria-label="Edit contact"
                    className="p-1.5 text-slate-400 hover:text-amber-500 hover:bg-slate-50 rounded-lg transition focus:outline-none focus:ring-2 focus:ring-brand-500"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
                    </svg>
                  </button>
                  <button
                    onClick={() => onNavigate("detail", c.id)}
                    aria-label="View contact details"
                    className="p-1.5 text-slate-400 hover:text-blue-500 hover:bg-slate-50 rounded-lg transition focus:outline-none focus:ring-2 focus:ring-brand-500"
                  >
                    <Eye className="w-4 h-4" />
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Floating Action Button (FAB) */}
      <button
        onClick={() => onNavigate("create")}
        className="md:hidden fixed bottom-20 right-6 w-14 h-14 bg-[#DCA035] hover:bg-[#C98F2C] text-white rounded-full flex items-center justify-center shadow-lg transition active:scale-95 z-40 border border-[#DCA035]/20 font-extrabold text-2xl"
      >
        <Plus className="w-6 h-6" />
      </button>
    </div>
  );
}
