/// Invoice list screen — delegates to the redesigned sales InvoiceListScreen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../sales/presentation/invoice_list_screen.dart' as sales;

class InvoiceListScreen extends ConsumerWidget {
  const InvoiceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const sales.InvoiceListScreen();
  }
}
