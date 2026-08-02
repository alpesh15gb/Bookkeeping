/// Invoice form screen — delegates to the sales InvoiceFormScreen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../sales/presentation/invoice_form_screen.dart' as sales;

class InvoiceFormScreen extends ConsumerWidget {
  const InvoiceFormScreen({super.key, this.editId});
  final String? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return sales.InvoiceFormScreen(editId: editId);
  }
}
