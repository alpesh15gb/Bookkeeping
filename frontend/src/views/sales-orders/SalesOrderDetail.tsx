import React, { useState, useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiClient } from "../../lib/api";
import { ArrowLeft, Printer, Download, AlertTriangle } from "lucide-react";

interface SalesOrderDetailProps {
  soId: string;
  onNavigate: (view: string, soId?: string) => void;
}

export default function SalesOrderDetail({ soId, onNavigate }: SalesOrderDetailProps) {
  const [showPrintModal, setShowPrintModal] = useState(false);

  const { data: so, isLoading, error } = useQuery({
    queryKey: ["sales-order", soId],
    queryFn: async () => {
      const res = await apiClient.get(`/sales-orders/${soId}`);
      return res.data;
    },
  });

  const { data: companyData } = useQuery({
    queryKey: ["company", so?.tenant_id],
    queryFn: async () => {
      const res = await apiClient.get(`/companies/${so.tenant_id}`);
      return res.data;
    },
    enabled: !!so?.tenant_id,
  });

  const { data: settingsData } = useQuery({
    queryKey: ["settings"],
    queryFn: async () => {
      const res = await apiClient.get("/settings");
      return res.data;
    },
  });

  const { data: printData } = useQuery({
    queryKey: ["so-print", soId],
    queryFn: async () => {
      const res = await apiClient.get(`/sales-orders/${soId}/pdf-payload`);
      return res.data;
    },
    enabled: showPrintModal,
  });

  useEffect(() => {
    if (printData && showPrintModal) {
      const formatCurrency = (v: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(v);
      const docNumber = printData.sales_order?.so_number || "";
      const html = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<title>Sales Order ${docNumber}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 40px; color: #1e293b; font-size: 12px; }
  .header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 3px solid #1e40af; padding-bottom: 24px; margin-bottom: 24px; }
  .company { display: flex; align-items: flex-start; gap: 16px; }
  .company-logo { max-height: 64px; max-width: 160px; object-fit: contain; }
  .company h1 { margin: 0; font-size: 22px; color: #1e40af; font-weight: 700; }
  .company p { margin: 2px 0; font-size: 11px; color: #475569; }
  .doc-info { text-align: right; }
  .doc-info h2 { font-size: 26px; margin: 0 0 8px 0; color: #1e293b; letter-spacing: 1px; text-transform: uppercase; }
  .doc-info p { margin: 2px 0; font-size: 12px; color: #475569; }
  .address-section { display: flex; justify-content: space-between; margin: 20px 0; }
  .address-box { width: 48%; }
  .address-box .label { font-size: 9px; font-weight: 700; color: #94a3b8; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px; }
  .address-box .name { font-size: 14px; font-weight: 700; color: #1e293b; margin-bottom: 4px; }
  .address-box p { margin: 1px 0; font-size: 11px; color: #475569; line-height: 1.5; }
  .meta-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin: 20px 0; padding: 16px; background: #f8fafc; border-radius: 4px; }
  .meta-grid .item .label { font-size: 9px; font-weight: 700; color: #94a3b8; text-transform: uppercase; letter-spacing: 1px; }
  .meta-grid .item .value { font-size: 13px; font-weight: 600; color: #1e293b; margin-top: 2px; }
  table { width: 100%; border-collapse: collapse; margin: 20px 0; }
  th { background: #1e40af; color: white; padding: 10px 12px; text-align: left; font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
  td { padding: 10px 12px; border-bottom: 1px solid #e2e8f0; font-size: 11px; }
  tr:nth-child(even) { background: #f8fafc; }
  .text-right { text-align: right; }
  .totals { margin-top: 20px; margin-left: auto; width: 350px; }
  .totals tr td { border: none; padding: 6px 12px; font-size: 12px; }
  .totals .grand-total td { font-size: 16px; font-weight: 700; border-top: 2px solid #1e293b; padding-top: 10px; }
  .totals .label-cell { text-align: right; color: #64748b; }
  .totals .value-cell { text-align: right; font-weight: 600; }
  .footer { margin-top: 40px; padding-top: 16px; border-top: 1px solid #e2e8f0; text-align: center; font-size: 10px; color: #94a3b8; }
  @media print { body { padding: 20px; } }
</style>
</head>
<body>
<div class="header">
  <div class="company">
    ${printData.company?.logo_url ? `<img class="company-logo" src="${printData.company.logo_url}" alt="Logo" onerror="this.style.display='none'" />` : ""}
    <div>
      <h1>${printData.company?.legal_name || ""}</h1>
      ${printData.company?.gstin ? `<p>GSTIN: ${printData.company.gstin}</p>` : ""}
      ${printData.company?.pan ? `<p>PAN: ${printData.company.pan}</p>` : ""}
    </div>
  </div>
  <div class="doc-info">
    <h2>Sales Order</h2>
    <p style="font-size:14px;font-weight:700;color:#1e40af;">${docNumber}</p>
  </div>
</div>

<div class="address-section">
  <div class="address-box">
    <div class="label">Seller</div>
    <div class="name">${printData.company?.legal_name || ""}</div>
    ${printData.company?.gstin ? `<p>GSTIN: ${printData.company.gstin}</p>` : ""}
  </div>
  <div class="address-box" style="text-align:right;">
    <div class="label">Customer</div>
    <div class="name">${printData.customer?.name || ""}</div>
    ${printData.customer?.gstin ? `<p>GSTIN: ${printData.customer.gstin}</p>` : ""}
    ${printData.customer?.billing_address ? `<p>${printData.customer.billing_address.street || ""}, ${printData.customer.billing_address.city || ""}, ${printData.customer.billing_address.state || ""} - ${printData.customer.billing_address.pincode || ""}</p>` : ""}
  </div>
</div>

<div class="meta-grid">
  <div class="item"><div class="label">Order Date</div><div class="value">${printData.sales_order?.order_date ? new Date(printData.sales_order.order_date).toLocaleDateString("en-IN") : ""}</div></div>
  <div class="item"><div class="label">Due Date</div><div class="value">${printData.sales_order?.due_date ? new Date(printData.sales_order.due_date).toLocaleDateString("en-IN") : ""}</div></div>
  <div class="item"><div class="label">Place of Supply</div><div class="value">${printData.sales_order?.pos_state_code || ""}</div></div>
  <div class="item"><div class="label">Status</div><div class="value">${printData.sales_order?.status || ""}</div></div>
</div>

<table>
  <thead><tr>
    <th>#</th><th>Item</th><th>HSN/SAC</th><th class="text-right">Qty</th>
    <th class="text-right">Rate</th><th class="text-right">Discount</th>
    <th class="text-right">Tax</th><th class="text-right">Amount</th>
  </tr></thead>
  <tbody>
    ${(printData.lines || []).map((l: any, i: number) => `
    <tr>
      <td>${i + 1}</td>
      <td>${l.product_name || ""}</td>
      <td>${l.hsn_sac || ""}</td>
      <td class="text-right">${l.quantity}</td>
      <td class="text-right">${formatCurrency(l.rate)}</td>
      <td class="text-right">${l.discount > 0 ? formatCurrency(l.discount) : "—"}</td>
      <td class="text-right">${l.gst_rate}%</td>
      <td class="text-right">${formatCurrency(l.total)}</td>
    </tr>`).join("")}
  </tbody>
</table>

<table class="totals">
  <tr><td class="label-cell">Subtotal</td><td class="value-cell">${formatCurrency(printData.sales_order?.subtotal || 0)}</td></tr>
  ${(printData.sales_order?.discount_total || 0) > 0 ? `<tr><td class="label-cell">Discount</td><td class="value-cell">-${formatCurrency(printData.sales_order.discount_total)}</td></tr>` : ""}
  ${(printData.sales_order?.cgst_amount || 0) > 0 ? `<tr><td class="label-cell">CGST</td><td class="value-cell">${formatCurrency(printData.sales_order.cgst_amount)}</td></tr>` : ""}
  ${(printData.sales_order?.sgst_amount || 0) > 0 ? `<tr><td class="label-cell">SGST</td><td class="value-cell">${formatCurrency(printData.sales_order.sgst_amount)}</td></tr>` : ""}
  ${(printData.sales_order?.igst_amount || 0) > 0 ? `<tr><td class="label-cell">IGST</td><td class="value-cell">${formatCurrency(printData.sales_order.igst_amount)}</td></tr>` : ""}
  <tr class="grand-total"><td class="label-cell">Total</td><td class="value-cell">${formatCurrency(printData.sales_order?.total || 0)}</td></tr>
</table>

<div class="footer">
  <p>This is a computer-generated sales order and does not require a physical signature.</p>
</div>

<script>window.onload = () => { window.print(); }</script>
</body></html>`;
      const win = window.open("", "_blank");
      if (win) {
        win.document.write(html);
        win.document.close();
      }
      setShowPrintModal(false);
    }
  }, [printData, showPrintModal]);

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(val);
  };

  const getStatusColor = (status: string) => {
    switch (status?.toUpperCase()) {
      case "DRAFT": return "bg-slate-100 text-slate-700 border-slate-200";
      case "CONFIRMED": return "bg-indigo-50 text-indigo-700 border-indigo-200";
      case "DELIVERED": return "bg-emerald-50 text-emerald-700 border-emerald-200";
      case "CANCELLED": return "bg-rose-50 text-rose-700 border-rose-200";
      default: return "bg-slate-100 text-slate-700";
    }
  };

  if (isLoading) {
    return (
      <div className="flex justify-center items-center py-20">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600"></div>
      </div>
    );
  }

  if (error || !so) {
    return (
      <div className="flex items-center gap-3 p-4 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg">
        <AlertTriangle className="w-5 h-5" />
        <span>Error retrieving sales order details.</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center no-print">
        <div className="flex items-center gap-3">
          <button
            onClick={() => onNavigate("list")}
            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded transition"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-xl font-bold text-slate-900 font-mono">{so.so_number}</h1>
          <span className={`px-2.5 py-0.5 text-xs font-semibold rounded-full border ${getStatusColor(so.status)}`}>
            {so.status}
          </span>
        </div>
        <button
          onClick={() => setShowPrintModal(true)}
          disabled={showPrintModal}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-semibold border border-slate-200 text-slate-700 bg-white hover:bg-slate-50 rounded-lg transition disabled:opacity-50"
        >
          {showPrintModal ? <Download className="w-4 h-4" /> : <Printer className="w-4 h-4" />}
          {showPrintModal ? "Preparing Print..." : "Print"}
        </button>
      </div>

      <div className="bg-white p-8 rounded-xl border border-slate-100 shadow-sm print-box">
        <div className="flex items-start gap-4 border-b border-slate-100 pb-8">
          {settingsData?.logo_url && (
            <img
              src={settingsData.logo_url}
              alt="Company logo"
              className="h-16 w-auto object-contain rounded border border-slate-100"
            />
          )}
          <div>
            <h2 className="text-lg font-bold text-slate-900">{companyData?.legal_name || "—"}</h2>
            {companyData?.gstin && <p className="text-sm font-semibold text-slate-700 mt-1">GSTIN: {companyData.gstin}</p>}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-8 py-8 border-b border-slate-100">
          <div>
            <span className="text-xs font-bold uppercase tracking-wider text-slate-400">Seller</span>
            <h3 className="text-lg font-bold text-slate-900 mt-1">{companyData?.legal_name || "—"}</h3>
            {companyData?.gstin && <p className="text-sm font-semibold text-slate-700 mt-2">GSTIN: {companyData.gstin}</p>}
          </div>
          <div className="md:text-right">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-400">Customer</span>
            <h3 className="text-lg font-bold text-slate-900 mt-1">{so.contact.name}</h3>
            {so.contact.billing_address && (
              <div className="text-sm text-slate-500 mt-1">
                <p>{so.contact.billing_address.street}</p>
                <p>{so.contact.billing_address.city}, {so.contact.billing_address.state} - {so.contact.billing_address.pincode}</p>
              </div>
            )}
            {so.contact.gstin && <p className="text-sm font-semibold text-slate-700 mt-2">GSTIN: {so.contact.gstin}</p>}
          </div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 py-8 border-b border-slate-100 text-sm">
          <div>
            <span className="text-slate-400 font-semibold block uppercase text-[10px] tracking-wider">Order Date</span>
            <span className="font-semibold text-slate-700 mt-1 block">
              {new Date(so.order_date).toLocaleDateString("en-IN")}
            </span>
          </div>
          <div>
            <span className="text-slate-400 font-semibold block uppercase text-[10px] tracking-wider">Due Date</span>
            <span className="font-semibold text-slate-700 mt-1 block">
              {new Date(so.due_date).toLocaleDateString("en-IN")}
            </span>
          </div>
          <div>
            <span className="text-slate-400 font-semibold block uppercase text-[10px] tracking-wider">Place of Supply</span>
            <span className="font-semibold text-slate-700 mt-1 block font-mono">State Code: {so.pos_state_code}</span>
          </div>
        </div>

        <table className="w-full border-collapse text-left text-sm mt-8">
          <thead>
            <tr className="bg-slate-50 border-b border-slate-100 text-slate-500 font-semibold">
              <th className="px-4 py-2.5">#</th>
              <th className="px-4 py-2.5">Item</th>
              <th className="px-4 py-2.5">HSN/SAC</th>
              <th className="px-4 py-2.5 text-right">Qty</th>
              <th className="px-4 py-2.5 text-right">Rate</th>
              <th className="px-4 py-2.5 text-right">Discount</th>
              <th className="px-4 py-2.5 text-right">GST</th>
              <th className="px-4 py-2.5 text-right">Amount</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {so.lines.map((line: any, idx: number) => (
              <tr key={line.id} className="text-slate-700">
                <td className="px-4 py-3 text-slate-400">{idx + 1}</td>
                <td className="px-4 py-3 font-semibold">{line.product?.name || "Product Item"}</td>
                <td className="px-4 py-3 font-mono">{line.hsn_sac}</td>
                <td className="px-4 py-3 text-right">{parseFloat(line.quantity)}</td>
                <td className="px-4 py-3 text-right">{formatCurrency(parseFloat(line.rate))}</td>
                <td className="px-4 py-3 text-right text-rose-600">
                  {parseFloat(line.discount) > 0 ? `-${formatCurrency(parseFloat(line.discount))}` : "—"}
                </td>
                <td className="px-4 py-3 text-right">{parseFloat(line.gst_rate)}%</td>
                <td className="px-4 py-3 text-right font-semibold">{formatCurrency(parseFloat(line.total))}</td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="space-y-3 md:max-w-md md:ml-auto w-full text-sm mt-8 pt-8 border-t border-slate-100">
          <div className="flex justify-between text-slate-500">
            <span>Subtotal</span>
            <span>{formatCurrency(parseFloat(so.subtotal))}</span>
          </div>
          {parseFloat(so.discount_total) > 0 && (
            <div className="flex justify-between text-slate-500">
              <span>Discount</span>
              <span className="text-rose-600">-{formatCurrency(parseFloat(so.discount_total))}</span>
            </div>
          )}
          {parseFloat(so.cgst_amount) > 0 && (
            <div className="flex justify-between text-slate-400 italic pl-2 text-xs">
              <span>CGST</span>
              <span>{formatCurrency(parseFloat(so.cgst_amount))}</span>
            </div>
          )}
          {parseFloat(so.sgst_amount) > 0 && (
            <div className="flex justify-between text-slate-400 italic pl-2 text-xs">
              <span>SGST</span>
              <span>{formatCurrency(parseFloat(so.sgst_amount))}</span>
            </div>
          )}
          {parseFloat(so.igst_amount) > 0 && (
            <div className="flex justify-between text-slate-400 italic pl-2 text-xs">
              <span>IGST</span>
              <span>{formatCurrency(parseFloat(so.igst_amount))}</span>
            </div>
          )}
          <div className="flex justify-between text-base font-bold text-slate-900 pt-2 border-t border-slate-100">
            <span>Total</span>
            <span>{formatCurrency(parseFloat(so.total))}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
