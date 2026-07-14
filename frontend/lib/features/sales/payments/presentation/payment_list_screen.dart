import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'payment_form_screen.dart';
import 'payment_providers.dart';

class PaymentListScreen extends ConsumerWidget {
  const PaymentListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(paymentListProvider(1));
    final fmt = ref.watch(numberFormatterProvider);
    Future<void> create() async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PaymentFormScreen()),
      );
      ref.invalidate(paymentListProvider);
    }

    return Scaffold(
      body: Column(
        children: [
          PageHeader(
            title: 'Customer Receipts',
            subtitle:
                'Record collections, allocate invoices, and track customer advances.',
            actions: [
              FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.add),
                label: const Text('New Receipt'),
              ),
            ],
          ),
          Expanded(
            child: payments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error.toString()),
                    TextButton(
                      onPressed: () => ref.invalidate(paymentListProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (items) => items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.payments_outlined, size: 48),
                          const SizedBox(height: 12),
                          const Text('No customer receipts yet'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: create,
                            child: const Text('Record first receipt'),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final p = items[index];
                        return ListTile(
                          leading: const Icon(Icons.south_west_rounded),
                          title: Text(
                            p.paymentNumber,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${p.contactName} · ${p.paymentDate} · ${p.paymentMode.value.replaceAll('_', ' ')}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                fmt.currency(p.amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Chip(label: Text(p.status.value)),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
