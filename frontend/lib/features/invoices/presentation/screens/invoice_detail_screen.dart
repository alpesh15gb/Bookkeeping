/// Invoice detail screen — delegates to the sales InvoiceDetailScreen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../sales/presentation/invoice_detail_screen.dart' as sales;

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.localId});
  final String localId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return sales.InvoiceDetailScreen(invoiceId: localId);
  }
}
