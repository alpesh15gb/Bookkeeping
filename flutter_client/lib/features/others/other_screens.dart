import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';

class EstimatesScreen extends StatelessWidget {
  const EstimatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Estimates', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Estimate', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: 15, isSelected: true),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Draft', count: 3),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Sent', count: 8),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Accepted', count: 4),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Estimate #', width: 130),
              TableColumn(label: 'Customer', width: 180),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Valid Until', width: 110),
              TableColumn(label: 'Amount', width: 120),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [
              AppTableRow(cells: [
                Text('EST-001', style: AppTypography.labelLarge),
                Text('Sharma Enterprises', style: AppTypography.bodyMedium),
                Text('Jun 10', style: AppTypography.bodySmall),
                Text('Jul 10', style: AppTypography.bodySmall),
                Text('₹85,000', style: AppTypography.amountTiny),
                const AppStatusBadge(status: InvoiceStatus.pending),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class CreditNotesScreen extends StatelessWidget {
  const CreditNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Credit Notes', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Credit Note', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Note #', width: 130),
              TableColumn(label: 'Customer', width: 180),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Amount', width: 120),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [
              AppTableRow(cells: [
                Text('CN-001', style: AppTypography.labelLarge),
                Text('Sharma Enterprises', style: AppTypography.bodyMedium),
                Text('Jun 08', style: AppTypography.bodySmall),
                Text('₹5,000', style: AppTypography.amountTiny),
                const AppStatusBadge(status: InvoiceStatus.paid),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class SalesOrdersScreen extends StatelessWidget {
  const SalesOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Sales Orders', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Order', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Order #', width: 130),
              TableColumn(label: 'Customer', width: 180),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Amount', width: 120),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class PurchaseOrdersScreen extends StatelessWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Purchase Orders', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Order', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Order #', width: 130),
              TableColumn(label: 'Vendor', width: 180),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Amount', width: 120),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class DebitNotesScreen extends StatelessWidget {
  const DebitNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Debit Notes', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Debit Note', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Note #', width: 130),
              TableColumn(label: 'Vendor', width: 180),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Amount', width: 120),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class ReturnsScreen extends StatelessWidget {
  const ReturnsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Returns', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Return', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Return #', width: 130),
              TableColumn(label: 'Party', width: 180),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Amount', width: 120),
              TableColumn(label: 'Type', width: 100),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class DeliveryChallansScreen extends StatelessWidget {
  const DeliveryChallansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Delivery Challans', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Challan', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Challan #', width: 130),
              TableColumn(label: 'Customer', width: 180),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Items', width: 80),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class InventoryAdjustmentsScreen extends StatelessWidget {
  const InventoryAdjustmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Inventory Adjustments', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Adjustment', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Adjustment #', width: 140),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Product', width: 180),
              TableColumn(label: 'Quantity Change', width: 130),
              TableColumn(label: 'Reason', width: 150),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}
