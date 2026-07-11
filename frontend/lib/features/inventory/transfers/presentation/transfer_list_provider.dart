/// Transfer list provider — paginated list of stock transfers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../services/transfer_service.dart';

final transferListProvider = FutureProvider.autoDispose<List<Transfer>>((
  ref,
) async {
  final res = await ref.watch(transferServiceProvider).list();
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});
