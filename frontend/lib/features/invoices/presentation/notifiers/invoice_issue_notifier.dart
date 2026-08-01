/// Issue confirmation state management.
///
/// The UI validates allocation capacity and displays a confirmation summary.
/// On confirm, it calls [InvoiceRepository.issue] which owns all business
/// logic: final validation, number consumption, freeze, journal, outbox.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/app_exception.dart';
import '../../domain/commands/invoice_commands.dart';
import '../../domain/entities/invoice_entity.dart';
import '../../domain/repositories/invoice_repository.dart';
import '../providers/invoice_providers.dart';

class InvoiceIssueState {
  const InvoiceIssueState({
    this.status = IssueStatus.checking,
    this.allocation,
    this.error,
  });

  final IssueStatus status;
  final NumberAllocationEntity? allocation;
  final String? error;

  bool get canIssue => status == IssueStatus.ready;
  bool get isChecking => status == IssueStatus.checking;
  bool get isIssuing => status == IssueStatus.issuing;
  bool get isDone => status == IssueStatus.done;
  bool get isBlocked => status == IssueStatus.blocked;

  InvoiceIssueState copyWith({
    IssueStatus? status,
    NumberAllocationEntity? allocation,
    String? error,
    bool clearError = false,
  }) => InvoiceIssueState(
    status: status ?? this.status,
    allocation: allocation ?? this.allocation,
    error: clearError ? null : (error ?? this.error),
  );
}

enum IssueStatus { checking, ready, issuing, done, blocked }

class InvoiceIssueNotifier extends StateNotifier<InvoiceIssueState> {
  InvoiceIssueNotifier(this._repository) : super(const InvoiceIssueState());

  final InvoiceRepository _repository;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _set(InvoiceIssueState s) {
    if (!_disposed) state = s;
  }

  /// Check allocation availability for a draft.
  Future<void> checkAllocation({
    required String companyId,
    required String deviceId,
    required String financialYearId,
    String series = 'SALES',
    String documentType = 'INVOICE',
  }) async {
    _set(const InvoiceIssueState(status: IssueStatus.checking));
    try {
      final alloc = await _repository.ensureAllocation(
        companyId: companyId,
        deviceId: deviceId,
        financialYearId: financialYearId,
        series: series,
        documentType: documentType,
      );
      if (alloc == null) {
        _set(
          const InvoiceIssueState(
            status: IssueStatus.blocked,
            error:
                'No document numbers are available offline. Connect once to reserve a number range.',
          ),
        );
      } else if (alloc.isExhausted) {
        _set(
          InvoiceIssueState(
            status: IssueStatus.blocked,
            error:
                'Number range exhausted ($alloc.used of ${alloc.toNum - alloc.fromNum + 1} used). Sync to request more numbers.',
            allocation: alloc,
          ),
        );
      } else {
        _set(InvoiceIssueState(status: IssueStatus.ready, allocation: alloc));
      }
    } catch (e) {
      _set(
        InvoiceIssueState(
          status: IssueStatus.blocked,
          error: 'Could not check allocation: $e',
        ),
      );
    }
  }

  /// Execute the issue.
  Future<InvoiceEntity?> issue({
    required String localId,
    required String companyId,
    required String deviceId,
    required String financialYearId,
    String series = 'SALES',
  }) async {
    if (!state.canIssue) return null;
    _set(state.copyWith(status: IssueStatus.issuing));

    try {
      final entity = await _repository.issue(
        IssueInvoiceCommand(
          localId: localId,
          companyId: companyId,
          deviceId: deviceId,
          financialYearId: financialYearId,
          series: series,
        ),
      );
      _set(state.copyWith(status: IssueStatus.done));
      return entity;
    } on ValidationException catch (e) {
      _set(state.copyWith(status: IssueStatus.blocked, error: e.message));
      return null;
    } catch (e) {
      _set(
        state.copyWith(status: IssueStatus.blocked, error: 'Issue failed: $e'),
      );
      return null;
    }
  }

  void reset() {
    _set(const InvoiceIssueState());
  }
}

final invoiceIssueProvider =
    StateNotifierProvider.autoDispose<InvoiceIssueNotifier, InvoiceIssueState>((
      ref,
    ) {
      final repo = ref.watch(invoiceRepositoryProvider);
      return InvoiceIssueNotifier(repo);
    });
