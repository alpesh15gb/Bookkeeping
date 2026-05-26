import React, { useState, useEffect } from "react";
import LoginPage from "./views/auth/LoginPage";
import InvoiceList from "./views/invoices/InvoiceList";
import InvoiceForm from "./views/invoices/InvoiceForm";
import InvoiceDetail from "./views/invoices/InvoiceDetail";
import SalesDashboard from "./views/sales/SalesDashboard";
import BillList from "./views/bills/BillList";
import BillForm from "./views/bills/BillForm";
import BillDetail from "./views/bills/BillDetail";
import ContactList from "./views/contacts/ContactList";
import ContactForm from "./views/contacts/ContactForm";
import ContactDetail from "./views/contacts/ContactDetail";
import ProductList from "./views/products/ProductList";
import ProductForm from "./views/products/ProductForm";
import ProductDetail from "./views/products/ProductDetail";
import AccountList from "./views/accounting/AccountList";
import AccountForm from "./views/accounting/AccountForm";
import LedgerView from "./views/accounting/LedgerView";
import TrialBalance from "./views/accounting/TrialBalance";
import ProfitLoss from "./views/accounting/ProfitLoss";
import ReportsDashboard from "./views/reports/ReportsDashboard";
import SettingsPage from "./views/settings/SettingsPage";
import ExpenseList from "./views/expenses/ExpenseList";
import ExpenseForm from "./views/expenses/ExpenseForm";
import ExpenseDetail from "./views/expenses/ExpenseDetail";

// New components
import PaymentsList from "./views/payments/PaymentsList";
import PaymentForm from "./views/payments/PaymentForm";
import PaymentDetail from "./views/payments/PaymentDetail";
import AccountDetail from "./views/accounting/AccountDetail";
import CreditNoteList from "./views/credit-notes/CreditNoteList";
import CreditNoteForm from "./views/credit-notes/CreditNoteForm";
import CreditNoteDetail from "./views/credit-notes/CreditNoteDetail";
import PurchaseOrderList from "./views/purchase-orders/PurchaseOrderList";
import PurchaseOrderForm from "./views/purchase-orders/PurchaseOrderForm";
import PurchaseOrderDetail from "./views/purchase-orders/PurchaseOrderDetail";
import SalesOrderList from "./views/sales-orders/SalesOrderList";
import SalesOrderForm from "./views/sales-orders/SalesOrderForm";
import SalesOrderDetail from "./views/sales-orders/SalesOrderDetail";

import logo from "./logo.png";
import { apiClient, setAccessToken, setTenantId } from "./lib/api";
import {
  LayoutDashboard,
  FileSpreadsheet,
  Receipt,
  Users,
  Package,
  BookOpen,
  PieChart,
  Settings,
  Building2,
  HelpCircle,
  Banknote,
  FileMinus,
  ShoppingCart,
  ShoppingBag,
  LogOut,
  Menu,
  X,
  Bell,
  ChevronDown
} from "lucide-react";

type View =
  | "sales_dashboard" | "list" | "create" | "edit" | "detail"
  | "bill_list" | "bill_create" | "bill_edit" | "bill_detail"
  | "contacts" | "contact_create" | "contact_edit" | "contact_detail"
  | "products" | "product_create" | "product_edit" | "product_detail"
  | "accounts" | "account_create" | "account_edit" | "account_detail"
  | "ledger" | "trial_balance" | "profit_loss"
  | "reports"
  | "settings"
  | "payments" | "payment_receipt" | "payment_disbursement"
  | "credit_notes" | "credit_note_create" | "credit_note_detail"
  | "purchase_orders" | "purchase_order_create" | "purchase_order_detail"
  | "sales_orders" | "sales_order_create" | "sales_order_detail"
  | "expense_list" | "expense_create" | "expense_edit" | "expense_detail";

export default function App() {
  const [authenticated, setAuthenticated] = useState(false);
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [currentView, setCurrentView] = useState<View>("sales_dashboard");
  const [activeInvoiceId, setActiveInvoiceId] = useState<string | undefined>(undefined);
  const [activeBillId, setActiveBillId] = useState<string | undefined>(undefined);
  const [activeContactId, setActiveContactId] = useState<string | undefined>(undefined);
  const [activeProductId, setActiveProductId] = useState<string | undefined>(undefined);
  const [activeAccountId, setActiveAccountId] = useState<string | undefined>(undefined);
  const [activePaymentId, setActivePaymentId] = useState<string | undefined>(undefined);
  const [activeCreditNoteId, setActiveCreditNoteId] = useState<string | undefined>(undefined);
  const [activePOId, setActivePOId] = useState<string | undefined>(undefined);
  const [activeSOId, setActiveSOId] = useState<string | undefined>(undefined);
  const [activeExpenseId, setActiveExpenseId] = useState<string | undefined>(undefined);
  const [user, setUser] = useState<{ full_name: string; email: string } | null>(null);

  // Restore session on mount
  useEffect(() => {
    const at = sessionStorage.getItem("_at");
    const tenantId = localStorage.getItem("active_tenant_id");
    if (at && tenantId) {
      setAccessToken(at);
      setTenantId(tenantId);
      apiClient
        .get("/auth/me")
        .then((res) => {
          setUser(res.data);
          setAuthenticated(true);
        })
        .catch(() => {
          setAccessToken(null);
          setTenantId(null);
          sessionStorage.removeItem("_at");
        });
    }
  }, []);

  // Fetch/Clear user info on auth status changes
  useEffect(() => {
    if (authenticated) {
      apiClient
        .get("/auth/me")
        .then((res) => {
          setUser(res.data);
        })
        .catch(() => {
          handleLogout();
        });
    } else {
      setUser(null);
    }
  }, [authenticated]);

  // Close sidebar on Escape key
  useEffect(() => {
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isSidebarOpen) {
        setIsSidebarOpen(false);
      }
    };
    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [isSidebarOpen]);

  const handleLogin = () => {
    setAuthenticated(true);
  };

  const handleLogout = () => {
    apiClient.post("/auth/logout", {}).catch(() => {});
    setAccessToken(null);
    setTenantId(null);
    sessionStorage.removeItem("_at");
    setAuthenticated(false);
  };

  const handleNavigateInvoices = (view: "sales_dashboard" | "list" | "create" | "edit" | "detail", invoiceId?: string) => {
    setActiveInvoiceId(invoiceId);
    if (view === "detail") {
      setCurrentView("detail");
    } else if (view === "create") {
      setCurrentView("create");
    } else if (view === "edit") {
      setCurrentView("edit");
    } else if (view === "sales_dashboard") {
      setCurrentView("sales_dashboard");
    } else {
      setCurrentView("list");
    }
  };

  const handleNavigateBills = (view: "bill_list" | "bill_create" | "bill_edit" | "bill_detail", billId?: string) => {
    setActiveBillId(billId);
    setCurrentView(view);
  };

  const handleNavigateContacts = (view: "list" | "create" | "edit" | "detail", contactId?: string) => {
    setActiveContactId(contactId);
    if (view === "create") { setCurrentView("contact_create"); }
    else if (view === "edit") { setCurrentView("contact_edit"); }
    else if (view === "detail") { setCurrentView("contact_detail"); }
    else { setCurrentView("contacts"); }
  };

  const handleNavigateProducts = (view: "list" | "create" | "edit" | "detail", productId?: string) => {
    setActiveProductId(productId);
    if (view === "create") { setCurrentView("product_create"); }
    else if (view === "edit") { setCurrentView("product_edit"); }
    else if (view === "detail") { setCurrentView("product_detail"); }
    else { setCurrentView("products"); }
  };

  const handleNavigateAccounts = (view: any, accountId?: string) => {
    setActiveAccountId(accountId);
    if (view === "create") { setCurrentView("account_create"); }
    else if (view === "edit") { setCurrentView("account_edit"); }
    else if (view === "detail") { setCurrentView("account_detail"); }
    else if (view === "ledger") { setCurrentView("ledger"); }
    else if (view === "trial_balance") { setCurrentView("trial_balance"); }
    else if (view === "profit_loss") { setCurrentView("profit_loss"); }
    else { setCurrentView("accounts"); }
  };

  const handleNavigatePayments = (view: "payments" | "payment_receipt" | "payment_disbursement", id?: string) => {
    setActivePaymentId(id);
    setCurrentView(view);
  };

  const handleNavigateCreditNotes = (view: "credit_notes" | "credit_note_create" | "credit_note_detail", id?: string) => {
    setActiveCreditNoteId(id);
    setCurrentView(view);
  };

  const handleNavigatePurchaseOrders = (view: "purchase_orders" | "purchase_order_create" | "purchase_order_detail", id?: string) => {
    setActivePOId(id);
    setCurrentView(view);
  };

  const handleNavigateSalesOrders = (view: "sales_orders" | "sales_order_create" | "sales_order_detail", id?: string) => {
    setActiveSOId(id);
    setCurrentView(view);
  };

  const handleNavigateExpenses = (view: "expense_list" | "expense_create" | "expense_edit" | "expense_detail", expenseId?: string) => {
    setActiveExpenseId(expenseId);
    setCurrentView(view);
  };

  const handleFormSuccess = () => {
    setCurrentView("list");
    setActiveInvoiceId(undefined);
  };

  const handleBillSuccess = () => {
    setCurrentView("bill_list");
    setActiveBillId(undefined);
  };

  const handleContactSuccess = () => {
    setCurrentView("contacts");
    setActiveContactId(undefined);
  };

  const handleProductSuccess = () => {
    setCurrentView("products");
    setActiveProductId(undefined);
  };

  const handleExpenseSuccess = () => {
    setCurrentView("expense_list");
    setActiveExpenseId(undefined);
  };

  const handleAccountSuccess = () => {
    setCurrentView("accounts");
    setActiveAccountId(undefined);
  };

  if (!authenticated) {
    return <LoginPage onLogin={handleLogin} />;
  }

  const menuItems = [
    { name: "Dashboard", icon: LayoutDashboard, view: "sales_dashboard" as const },
    { name: "Invoices (Sales)", icon: FileSpreadsheet, view: "list" as const },
    { name: "Vendor Bills", icon: Receipt, view: "bill_list" as const },
    { name: "Expenses", icon: Receipt, view: "expense_list" as const },
    { name: "Payments", icon: Banknote, view: "payments" as const },
    { name: "Credit Notes", icon: FileMinus, view: "credit_notes" as const },
    { name: "Purchase Orders", icon: ShoppingCart, view: "purchase_orders" as const },
    { name: "Sales Orders", icon: ShoppingBag, view: "sales_orders" as const },
    { name: "Customers & Vendors", icon: Users, view: "contacts" as const },
    { name: "Products & Inventory", icon: Package, view: "products" as const },
    { name: "Accounting & Ledgers", icon: BookOpen, view: "accounts" as const },
    { name: "Reports & GST", icon: PieChart, view: "reports" as const },
    { name: "Settings", icon: Settings, view: "settings" as const },
  ];

  return (
    <div className="min-h-screen flex flex-col md:flex-row bg-[#fcfcfd]">
      {/* Mobile Sticky Brand Header */}
      <header className="md:hidden h-14 bg-[#0B1B3D] border-b border-zinc-800 px-4 flex items-center justify-between sticky top-0 z-30 no-print">
        <div className="flex items-center gap-2">
          <button
            onClick={() => setIsSidebarOpen(true)}
            className="p-1.5 text-zinc-300 hover:bg-zinc-800 rounded-md transition"
            aria-label="Open navigation menu"
          >
            <Menu className="w-5 h-5" />
          </button>
          <div className="bg-white rounded px-2 py-0.5 shadow-sm h-8 flex items-center justify-center">
            <img src={logo} alt="Apex Books Logo" className="h-6 object-contain" />
          </div>
        </div>
        <span className="text-[10px] font-semibold px-2 py-0.5 bg-zinc-800 text-zinc-400 rounded-full border border-zinc-700 font-mono">
          {new Date().getMonth() < 3 ? `${new Date().getFullYear() - 1}-${String(new Date().getFullYear()).slice(2)}` : `${new Date().getFullYear()}-${String(new Date().getFullYear() + 1).slice(2)}`}
        </span>
      </header>

      {/* Backdrop overlay for mobile drawer */}
      {isSidebarOpen && (
        <div
          onClick={() => setIsSidebarOpen(false)}
          className="fixed inset-0 bg-zinc-950/20 backdrop-blur-sm z-40 md:hidden transition-opacity duration-200"
        />
      )}

      {/* Sidebar - Drawer on Mobile, Static Sidebar on Desktop */}
      <aside
        className={`fixed md:static inset-y-0 left-0 w-64 bg-[#0B1B3D] text-zinc-300 flex flex-col no-print z-50 transform md:transform-none transition-transform duration-200 ease-in-out ${
          isSidebarOpen ? "translate-x-0" : "-translate-x-full md:translate-x-0"
        }`}
      >
        <div className="p-5 border-b border-zinc-850 flex items-center justify-between md:justify-start gap-3 bg-[#0B1B3D]">
          <div className="bg-white rounded-lg p-2 shadow-sm w-full flex items-center justify-center">
            <img src={logo} alt="Apex Books Logo" className="h-10 object-contain" />
          </div>
          <button
            onClick={() => setIsSidebarOpen(false)}
            className="md:hidden p-1.5 text-zinc-400 hover:text-white rounded-md hover:bg-white/5"
            aria-label="Close navigation menu"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <nav className="flex-1 px-3 py-4 space-y-0.5 overflow-y-auto">
          {menuItems.map((item) => {
            const Icon = item.icon;
            const isCurrent =
              (item.view === "sales_dashboard" && currentView === "sales_dashboard") ||
              (item.view === "list" && ["list", "create", "edit", "detail"].includes(currentView)) ||
              (item.view === "bill_list" && ["bill_list", "bill_create", "bill_edit", "bill_detail"].includes(currentView)) ||
              (item.view === "expense_list" && ["expense_list", "expense_create", "expense_edit", "expense_detail"].includes(currentView)) ||
              (item.view === "payments" && ["payments", "payment_receipt", "payment_disbursement"].includes(currentView)) ||
              (item.view === "credit_notes" && ["credit_notes", "credit_note_create", "credit_note_detail"].includes(currentView)) ||
              (item.view === "purchase_orders" && ["purchase_orders", "purchase_order_create", "purchase_order_detail"].includes(currentView)) ||
              (item.view === "sales_orders" && ["sales_orders", "sales_order_create", "sales_order_detail"].includes(currentView)) ||
              (item.view === "contacts" && ["contacts", "contact_create", "contact_edit", "contact_detail"].includes(currentView)) ||
              (item.view === "products" && ["products", "product_create", "product_edit", "product_detail"].includes(currentView)) ||
              (item.view === "accounts" && ["accounts", "account_create", "account_edit", "account_detail", "ledger", "trial_balance", "profit_loss"].includes(currentView)) ||
              (item.view === "reports" && currentView === "reports") ||
              (item.view === "settings" && currentView === "settings");

            return (
              <button
                key={item.name}
                onClick={() => {
                  if (item.view === "list") {
                    handleNavigateInvoices("list");
                  } else if (item.view === "bill_list") {
                    handleNavigateBills("bill_list");
                  } else if (item.view === "expense_list") {
                    handleNavigateExpenses("expense_list");
                  } else if (item.view === "payments") {
                    setCurrentView("payments");
                  } else if (item.view === "credit_notes") {
                    setCurrentView("credit_notes");
                  } else if (item.view === "purchase_orders") {
                    setCurrentView("purchase_orders");
                  } else if (item.view === "sales_orders") {
                    setCurrentView("sales_orders");
                  } else if (item.view === "contacts") {
                    setCurrentView("contacts");
                  } else if (item.view === "products") {
                    setCurrentView("products");
                  } else if (item.view === "accounts") {
                    setCurrentView("accounts");
                  } else if (item.view === "reports") {
                    setCurrentView("reports");
                  } else if (item.view) {
                    setCurrentView(item.view);
                  }
                  setIsSidebarOpen(false);
                }}
                className={`w-full flex items-center gap-3 px-3 py-2 text-xs font-semibold rounded-md transition duration-150 ${
                  isCurrent
                    ? "bg-gold-500 text-zinc-950 shadow-sm"
                    : "text-zinc-300 hover:bg-white/5 hover:text-white"
                }`}
              >
                <Icon className={`w-4 h-4 ${isCurrent ? "text-zinc-950" : "text-zinc-400"}`} />
                {item.name}
              </button>
            );
          })}
        </nav>

        <div className="p-4 border-t border-zinc-800 text-[11px] text-zinc-300 flex flex-col gap-2 bg-[#08152e]">
          <div className="flex items-center gap-2">
            <Building2 className="w-3.5 h-3.5 text-zinc-500" />
            <span>Accounting App</span>
          </div>
          <button
            onClick={() => {
              handleLogout();
              setIsSidebarOpen(false);
            }}
            className="flex items-center gap-2 mt-2 text-zinc-400 hover:text-red-400 transition text-[11px] border-t border-zinc-800 pt-2 w-full text-left font-semibold"
          >
            <LogOut className="w-3.5 h-3.5 text-zinc-500 hover:text-red-400" />
            <span>Sign Out</span>
          </button>
        </div>
      </aside>

      <main className="flex-1 flex flex-col min-w-0 overflow-y-auto">
        {/* Desktop Top Header */}
        <header className="hidden md:flex h-14 bg-white border-b border-zinc-200 px-8 items-center justify-between no-print sticky top-0 z-30">
          <div className="flex items-center gap-4">
            <span className="text-[11px] font-semibold px-2.5 py-1 bg-zinc-50 text-zinc-700 rounded-full border border-zinc-200/50 font-mono">
              {new Date().getMonth() < 3 ? `FY ${new Date().getFullYear() - 1}-${String(new Date().getFullYear()).slice(2)}` : `FY ${new Date().getFullYear()}-${String(new Date().getFullYear() + 1).slice(2)}`}
            </span>
          </div>
          <div className="flex items-center gap-3.5">
            {/* User Profile Info */}
            <div className="flex items-center gap-2.5 cursor-pointer">
              <div className="h-8 w-8 rounded-full bg-zinc-200 flex items-center justify-center text-xs font-bold text-zinc-600">
                {user?.full_name?.charAt(0)?.toUpperCase() || "U"}
              </div>
              <div className="text-xs">
                <p className="font-semibold text-zinc-850 leading-none mb-0.5">{user?.full_name || "User"}</p>
                <p className="text-zinc-400 text-[9px] font-medium leading-none">{user?.email || ""}</p>
              </div>
              <ChevronDown className="w-3 h-3 text-zinc-400 ml-0.5" />
            </div>
          </div>
        </header>

        <div className="p-4 md:p-8 max-w-7xl w-full mx-auto flex-1">
          {currentView === "sales_dashboard" && <SalesDashboard onNavigate={(view) => {
            const viewMap: Record<string, View> = {
              invoices: "list",
              bills: "bill_list",
              expenses: "expense_list",
              contacts: "contacts",
              products: "products",
              reports: "reports",
              settings: "settings",
            };
            const target = viewMap[view] || "sales_dashboard";
            setCurrentView(target);
            setIsSidebarOpen(false);
          }} />}
          {currentView === "list" && <InvoiceList onNavigate={handleNavigateInvoices} />}
          {(currentView === "create" || currentView === "edit") && (
            <InvoiceForm editId={activeInvoiceId} onNavigate={handleNavigateInvoices} onSuccess={handleFormSuccess} />
          )}
          {currentView === "detail" && activeInvoiceId && (
            <InvoiceDetail invoiceId={activeInvoiceId} onNavigate={handleNavigateInvoices} />
          )}
          {currentView === "bill_list" && <BillList onNavigate={handleNavigateBills} />}
          {(currentView === "bill_create" || currentView === "bill_edit") && (
            <BillForm editId={activeBillId} onNavigate={handleNavigateBills} onSuccess={handleBillSuccess} />
          )}
          {currentView === "bill_detail" && activeBillId && (
            <BillDetail billId={activeBillId} onNavigate={handleNavigateBills} />
          )}
          {currentView === "contacts" && <ContactList onNavigate={handleNavigateContacts} />}
          {(currentView === "contact_create" || currentView === "contact_edit") && (
            <ContactForm editId={activeContactId} onNavigate={handleNavigateContacts} onSuccess={handleContactSuccess} />
          )}
          {currentView === "contact_detail" && activeContactId && (
            <ContactDetail contactId={activeContactId} onNavigate={handleNavigateContacts} />
          )}
          {currentView === "products" && <ProductList onNavigate={handleNavigateProducts} />}
          {(currentView === "product_create" || currentView === "product_edit") && (
            <ProductForm editId={activeProductId} onNavigate={handleNavigateProducts} onSuccess={handleProductSuccess} />
          )}
          {currentView === "product_detail" && activeProductId && (
            <ProductDetail productId={activeProductId} onNavigate={handleNavigateProducts} />
          )}
          {currentView === "expense_list" && <ExpenseList onNavigate={handleNavigateExpenses} />}
          {(currentView === "expense_create" || currentView === "expense_edit") && (
            <ExpenseForm editId={activeExpenseId} onNavigate={handleNavigateExpenses} onSuccess={handleExpenseSuccess} />
          )}
          {currentView === "expense_detail" && activeExpenseId && (
            <ExpenseDetail expenseId={activeExpenseId} onNavigate={handleNavigateExpenses} />
          )}
          {currentView === "accounts" && <AccountList onNavigate={handleNavigateAccounts} />}
          {(currentView === "account_create" || currentView === "account_edit") && (
            <AccountForm editId={activeAccountId} onNavigate={handleNavigateAccounts} onSuccess={handleAccountSuccess} />
          )}
          {currentView === "account_detail" && activeAccountId && (
            <AccountDetail accountId={activeAccountId} onNavigate={handleNavigateAccounts} />
          )}
          {currentView === "ledger" && activeAccountId && (
            <LedgerView accountId={activeAccountId} onNavigate={handleNavigateAccounts} />
          )}
          {currentView === "trial_balance" && (
            <TrialBalance onNavigate={handleNavigateAccounts} />
          )}
          {currentView === "profit_loss" && (
            <ProfitLoss onNavigate={handleNavigateAccounts} />
          )}
          {currentView === "reports" && <ReportsDashboard onNavigate={() => {}} />}
          {currentView === "settings" && <SettingsPage onNavigate={() => {}} />}

          {/* New Views */}
          {currentView === "payments" && (
            <PaymentsList onNavigate={handleNavigatePayments} />
          )}
          {currentView === "payment_receipt" && (
            activePaymentId ? (
              <PaymentDetail paymentId={activePaymentId} mode="receipt" onNavigate={(view) => {
                setActivePaymentId(undefined);
                setCurrentView(view);
              }} />
            ) : (
              <PaymentForm mode="receipt" onSuccess={() => {
                setActivePaymentId(undefined);
                setCurrentView("payments");
              }} onNavigate={(view) => {
                setActivePaymentId(undefined);
                setCurrentView(view);
              }} />
            )
          )}
          {currentView === "payment_disbursement" && (
            activePaymentId ? (
              <PaymentDetail paymentId={activePaymentId} mode="disbursement" onNavigate={(view) => {
                setActivePaymentId(undefined);
                setCurrentView(view);
              }} />
            ) : (
              <PaymentForm mode="disbursement" onSuccess={() => {
                setActivePaymentId(undefined);
                setCurrentView("payments");
              }} onNavigate={(view) => {
                setActivePaymentId(undefined);
                setCurrentView(view);
              }} />
            )
          )}

          {currentView === "credit_notes" && (
            <CreditNoteList onNavigate={handleNavigateCreditNotes} />
          )}
          {currentView === "credit_note_create" && (
            <CreditNoteForm onSuccess={() => {
              setActiveCreditNoteId(undefined);
              setCurrentView("credit_notes");
            }} onNavigate={handleNavigateCreditNotes} />
          )}
          {currentView === "credit_note_detail" && activeCreditNoteId && (
            <CreditNoteDetail creditNoteId={activeCreditNoteId} onNavigate={handleNavigateCreditNotes} />
          )}

          {currentView === "purchase_orders" && (
            <PurchaseOrderList onNavigate={handleNavigatePurchaseOrders} />
          )}
          {currentView === "purchase_order_create" && (
            <PurchaseOrderForm editId={activePOId} onSuccess={() => {
              setActivePOId(undefined);
              setCurrentView("purchase_orders");
            }} onNavigate={handleNavigatePurchaseOrders} />
          )}
          {currentView === "purchase_order_detail" && activePOId && (
            <PurchaseOrderDetail poId={activePOId} onNavigate={handleNavigatePurchaseOrders} />
          )}
          {currentView === "sales_orders" && (
            <SalesOrderList onNavigate={handleNavigateSalesOrders} />
          )}
          {currentView === "sales_order_create" && (
            <SalesOrderForm editId={activeSOId} onSuccess={() => {
              setActiveSOId(undefined);
              setCurrentView("sales_orders");
            }} onNavigate={handleNavigateSalesOrders} />
          )}
          {currentView === "sales_order_detail" && activeSOId && (
            <SalesOrderDetail soId={activeSOId} onNavigate={handleNavigateSalesOrders} />
          )}
        </div>
      </main>

      {/* Mobile Sticky Bottom Tab Navigation Bar */}
      <div className="md:hidden h-16 bg-[#0B1B3D] border-t border-navy-800 fixed bottom-0 left-0 right-0 z-40 flex items-center justify-around px-2 no-print">
        <button
          onClick={() => {
            setCurrentView("sales_dashboard");
            setIsSidebarOpen(false);
          }}
          className={`flex flex-col items-center gap-1 text-[10px] font-bold transition ${
            currentView === "sales_dashboard" ? "text-[#DCA035]" : "text-zinc-400 hover:text-white"
          }`}
        >
          <LayoutDashboard className="w-5 h-5" />
          <span>Dashboard</span>
        </button>

        <button
          onClick={() => {
            handleNavigateInvoices("list");
            setIsSidebarOpen(false);
          }}
          className={`flex flex-col items-center gap-1 text-[10px] font-bold transition ${
            ["list", "create", "edit", "detail"].includes(currentView) ? "text-[#DCA035]" : "text-zinc-400 hover:text-white"
          }`}
        >
          <FileSpreadsheet className="w-5 h-5" />
          <span>Invoices</span>
        </button>

        <button
          onClick={() => {
            setCurrentView("products");
            setIsSidebarOpen(false);
          }}
          className={`flex flex-col items-center gap-1 text-[10px] font-bold transition ${
            ["products", "product_create", "product_edit", "product_detail"].includes(currentView) ? "text-[#DCA035]" : "text-zinc-400 hover:text-white"
          }`}
        >
          <Package className="w-5 h-5" />
          <span>Inventory</span>
        </button>

        <button
          onClick={() => {
            setCurrentView("contacts");
            setIsSidebarOpen(false);
          }}
          className={`flex flex-col items-center gap-1 text-[10px] font-bold transition ${
            ["contacts", "contact_create", "contact_edit", "contact_detail"].includes(currentView) ? "text-[#DCA035]" : "text-zinc-400 hover:text-white"
          }`}
        >
          <Users className="w-5 h-5" />
          <span>Parties</span>
        </button>

        <button
          onClick={() => {
            setCurrentView("settings");
            setIsSidebarOpen(false);
          }}
          className={`flex flex-col items-center gap-1 text-[10px] font-bold transition ${
            currentView === "settings" ? "text-[#DCA035]" : "text-zinc-400 hover:text-white"
          }`}
        >
          <Settings className="w-5 h-5" />
          <span>Settings</span>
        </button>
      </div>

      {/* Adjust main content padding on mobile so bottom bar does not overlap elements */}
      <style>{`
        @media (max-width: 767px) {
          main {
            padding-bottom: 4rem !important;
          }
        }
      `}</style>
    </div>
  );
}
