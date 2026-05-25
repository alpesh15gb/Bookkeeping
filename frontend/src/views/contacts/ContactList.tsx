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
    queryKey: ["contacts"],
    queryFn: async () => {
      const params: any = {};
      if (typeFilter !== "ALL") {
        params.contact_type = typeFilter;
      }
      const res = await apiClient.get("/masters/contacts", { params });
      return res.data;
    },
  });

  const filteredContacts = contacts.filter((c) => {
    const matchesSearch =
      c.name.toLowerCase().includes(search.toLowerCase()) ||
      c.email.toLowerCase().includes(search.toLowerCase()) ||
      c.phone.toLowerCase().includes(search.toLowerCase());
    return matchesSearch;
  });

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Contacts</h1>
          <p className="text-sm text-slate-500">Manage customers, vendors, and allied contacts for GST compliance.</p>
        </div>
        <button
          onClick={() => onNavigate("create")}
          className="flex items-center gap-2 px-4 py-2 bg-brand-600 hover:bg-brand-700 text-white rounded-lg shadow-sm font-semibold transition"
        >
          <Plus className="w-4 h-4" />
          Create Contact
        </button>
      </div>

      <div className="flex flex-col sm:flex-row gap-3 bg-white p-4 rounded-xl shadow-sm border border-slate-100">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-2.5 h-4.5 w-4.5 text-slate-400" />
          <input
            type="text"
            placeholder="Search by name, email or phone..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500 text-sm"
          />
        </div>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="px-3 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
        >
          <option value="ALL">All Types</option>
          <option value="CUSTOMER">Customer</option>
          <option value="VENDOR">Vendor</option>
          <option value="BOTH">Both</option>
        </select>
      </div>

      {isLoading ? (
        <div className="flex justify-center items-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
        </div>
      ) : error ? (
        <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span>Error loading contacts. Please check API server.</span>
        </div>
      ) : filteredContacts.length === 0 ? (
        <div className="text-center py-16 bg-white rounded-xl border border-slate-100 shadow-sm">
          <Users className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-sm font-semibold text-slate-700">No Contacts Found</h3>
          <p className="text-xs text-slate-500 mt-1">Try resetting filters or create a new contact to get started.</p>
        </div>
      ) : (
        <div className="bg-white rounded-xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-sm">
              <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
                <tr>
                  <th className="px-6 py-3.5">Name</th>
                  <th className="px-6 py-3.5">Email</th>
                  <th className="px-6 py-3.5">Phone</th>
                  <th className="px-6 py-3.5">Type</th>
                  <th className="px-6 py-3.5">GSTIN</th>
                  <th className="px-6 py-3.5">State</th>
                  <th className="px-6 py-3.5">Status</th>
                  <th className="px-6 py-3.5">Created</th>
                  <th className="px-6 py-3.5 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {filteredContacts.map((c) => (
                  <tr key={c.id} className="hover:bg-slate-50/50 transition">
                    <td className="px-6 py-4 font-semibold text-slate-800">{c.name}</td>
                    <td className="px-6 py-4 text-slate-500">{c.email || "—"}</td>
                    <td className="px-6 py-4 text-slate-500">{c.phone || "—"}</td>
                    <td className="px-6 py-4">
                      <span className={`px-2.5 py-1 text-xs font-semibold rounded-full inline-flex items-center gap-1 ${
                        c.contact_type === "CUSTOMER"
                          ? "bg-blue-50 text-blue-700 border border-blue-200"
                          : c.contact_type === "VENDOR"
                          ? "bg-purple-50 text-purple-700 border border-purple-200"
                          : "bg-teal-50 text-teal-700 border border-teal-200"
                      }`}>
                        {c.contact_type}
                      </span>
                    </td>
                    <td className="px-6 py-4 font-mono text-slate-500">{c.gstin || "—"}</td>
                    <td className="px-6 py-4 text-slate-500">{c.state_code || "—"}</td>
                    <td className="px-6 py-4">
                      <span className={`px-2.5 py-1 text-xs font-semibold rounded-full ${
                        c.is_active
                          ? "bg-emerald-50 text-emerald-700 border border-emerald-200"
                          : "bg-rose-50 text-rose-700 border border-rose-200"
                      }`}>
                        {c.is_active ? "Active" : "Inactive"}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-slate-500">{new Date(c.created_at).toLocaleDateString("en-IN")}</td>
                    <td className="px-6 py-4 text-right">
                      <div className="inline-flex items-center gap-2">
                        <button
                          onClick={() => onNavigate("detail", c.id)}
                          title="View Details"
                          className="p-1 text-slate-400 hover:text-brand-600 hover:bg-slate-100 rounded transition"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        {c.is_active && (
                          <button
                            onClick={() => onNavigate("edit", c.id)}
                            title="Edit Contact"
                            className="p-1 text-slate-400 hover:text-amber-600 hover:bg-slate-100 rounded transition"
                          >
                            <Edit className="w-4 h-4" />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
