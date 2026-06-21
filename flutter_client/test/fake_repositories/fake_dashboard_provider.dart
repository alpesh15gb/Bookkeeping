import 'package:flutter_client/providers/dashboard_provider.dart';

class FakeDashboardProvider extends DashboardProvider {
  @override
  bool get isLoading => false;

  @override
  Map<String, dynamic> get metrics => const {
        'overdue_invoices_count': 3,
        'pending_bills_count': 2,
      };

  @override
  double get receivables => 125000;
}
