/// Module-specific empty states for every section of ApexBooks.
library;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'premium_empty_state.dart';

/// Empty state for invoices list
class EmptyInvoices extends StatelessWidget {
  const EmptyInvoices({super.key, this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(
      icon: Icons.receipt_long_rounded,
      title: 'No invoices yet',
      subtitle:
          'Create your first invoice to start tracking receivables and getting paid faster.',
      actionLabel: 'Create Invoice',
      onAction: onCreate,
    );
  }
}

/// Empty state for bills/vendor bills
class EmptyBills extends StatelessWidget {
  const EmptyBills({super.key, this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(
      icon: Icons.request_quote_rounded,
      title: 'No bills recorded',
      subtitle: 'Add vendor bills to track what you owe and manage payables.',
      actionLabel: 'Add Bill',
      onAction: onCreate,
    );
  }
}

/// Empty state for contacts
class EmptyContacts extends StatelessWidget {
  const EmptyContacts({super.key, this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(
      icon: Icons.people_alt_rounded,
      title: 'No contacts yet',
      subtitle:
          'Add customers and vendors to start creating invoices and bills.',
      actionLabel: 'Add Contact',
      onAction: onCreate,
    );
  }
}

/// Empty state for products
class EmptyProducts extends StatelessWidget {
  const EmptyProducts({super.key, this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(
      icon: Icons.inventory_2_rounded,
      title: 'No products',
      subtitle:
          'Add products and services to include them in your invoices.',
      actionLabel: 'Add Product',
      onAction: onCreate,
    );
  }
}

/// Empty state for accounts (COA)
class EmptyAccounts extends StatelessWidget {
  const EmptyAccounts({super.key, this.onCreate});
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(
      icon: Icons.account_tree_rounded,
      title: 'No accounts defined',
      subtitle:
          'Your chart of accounts is empty. Add accounts to start tracking financials.',
      actionLabel: 'Add Account',
      onAction: onCreate,
    );
  }
}

/// Empty state for journal entries
class EmptyJournals extends StatelessWidget {
  const EmptyJournals({super.key});

  @override
  Widget build(BuildContext context) {
    return const PremiumEmptyState(
      icon: Icons.book_rounded,
      title: 'No journal entries',
      subtitle:
          'Journal entries are automatically created when you finalize invoices, bills, and payments.',
    );
  }
}

/// Empty state for trial balance
class EmptyTrialBalance extends StatelessWidget {
  const EmptyTrialBalance({super.key});

  @override
  Widget build(BuildContext context) {
    return const PremiumEmptyState(
      icon: Icons.balance_rounded,
      title: 'No data to display',
      subtitle:
          'Post journal entries by finalizing invoices and bills to see your trial balance.',
    );
  }
}

/// Empty state for stock/inventory
class EmptyStock extends StatelessWidget {
  const EmptyStock({super.key});

  @override
  Widget build(BuildContext context) {
    return const PremiumEmptyState(
      icon: Icons.warehouse_rounded,
      title: 'No stock records',
      subtitle:
          'Stock entries are created automatically when you receive goods via purchase orders.',
    );
  }
}

/// Empty search results
class EmptySearchResults extends StatelessWidget {
  const EmptySearchResults({super.key, required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(
      icon: Icons.search_off_rounded,
      title: 'No results for "$query"',
      subtitle: 'Try adjusting your search terms or filters.',
    );
  }
}

/// Empty state for no overdue items (positive)
class EmptyOverdue extends StatelessWidget {
  const EmptyOverdue({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(
      icon: Icons.check_circle_rounded,
      title: 'All caught up!',
      subtitle: 'No overdue invoices. Keep up the great work.',
      iconColor: Theme.of(context).extension<ApexColors>()?.success,
    );
  }
}
