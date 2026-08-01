/// Generic CRUD framework: BaseCrudController + BaseListScreen + ListState.
/// Every CRUD feature module composes these instead of writing controllers
/// and list screens from scratch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/base_model.dart';
import '../api/base_repository.dart';
import '../network/dio_extensions.dart';
import '../result/result.dart';
import '../services/notification_service.dart';
import '../tables/table_column.dart';
import '../tables/table_controller.dart';
import '../tables/apex_data_table.dart';
import '../widgets/page_header.dart';
import '../theme/responsive.dart';
import '../widgets/states.dart';
import '../dialogs/apex_dialogs.dart';

/// The three visual states a list screen can be in.
sealed class ListState {
  const ListState();
}

final class ListLoading extends ListState {
  const ListLoading();
}

final class ListEmpty extends ListState {
  const ListEmpty({this.title = 'No records', this.subtitle});
  final String title;
  final String? subtitle;
}

final class ListData<T extends BaseModel> extends ListState {
  const ListData(this.paged);
  final Paged<T> paged;
}

final class ListError extends ListState {
  const ListError(this.message);
  final String message;
}

/// Base CRUD controller with list/create/update/delete.
class BaseCrudController<T extends BaseModel> extends StateNotifier<ListState> {
  BaseCrudController(this._repo, this._notif) : super(const ListLoading());

  final BaseRepository<T> _repo;
  final NotificationService _notif;

  BaseRepository<T> get repo => _repo;

  /// Fetch paginated list.
  Future<void> load(ListQuery query) async {
    state = const ListLoading();
    final result = await _repo.list(query);
    switch (result) {
      case Success<PagedResult<T>>(:final value):
        state = value.items.isEmpty ? const ListEmpty() : ListData(value);
      case Failure(:final error):
        state = ListError(error.message);
      case Loading():
        // Loading state already set above; nothing else to do.
        break;
    }
  }

  /// Delete a record with confirmation dialog.
  ///
  /// Returns `true` if the record was deleted. Returns `false` if the user
  /// cancelled, the controller was disposed (e.g. the screen was popped), or
  /// the delete failed. Notifications are only shown while the controller is
  /// still mounted so we never touch a stale [BuildContext].
  Future<bool> delete(T record, BuildContext context) async {
    final confirmed = await ApexDialogs.delete(
      context,
      itemName: record.toString(),
    );
    if (confirmed != true) return false;
    final result = await _repo.delete(record.id);
    if (!mounted || !context.mounted) return result is Success;
    if (result is Success) {
      _notif.success(context, 'Deleted successfully.');
      return true;
    }
    _notif.error(context, 'Failed to delete.');
    return false;
  }
}

/// Generic list screen — compose with columns, provider, controller.
class BaseListScreen<T extends BaseModel> extends ConsumerStatefulWidget {
  const BaseListScreen({
    super.key,
    required this.title,
    required this.columns,
    required this.provider,
    required this.tableCtrl,
    this.onCreate,
    this.onRowTap,
    this.searchHint = 'Search',
    this.emptyTitle = 'No records',
    this.emptySubtitle,
    this.filterChips = const [],
  });

  final String title;
  final List<ApexColumn<T>> columns;
  final StateNotifierProvider<BaseCrudController<T>, ListState> provider;
  final ApexTableController tableCtrl;
  final VoidCallback? onCreate;
  final void Function(T)? onRowTap;
  final String searchHint;
  final String emptyTitle;
  final String? emptySubtitle;
  final List<Widget> filterChips;

  @override
  ConsumerState<BaseListScreen<T>> createState() => _BaseListScreenState<T>();
}

class _BaseListScreenState<T extends BaseModel>
    extends ConsumerState<BaseListScreen<T>> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(widget.provider.notifier)
          .load(widget.tableCtrl.toListQuery()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);

    final rows = switch (state) {
      ListData<T>(:final paged) => paged,
      _ => null,
    };

    final isLoading = state is ListLoading;
    final errMsg = switch (state) {
      ListError(:final message) => message,
      _ => null,
    };

    Widget body;
    if (state is ListEmpty) {
      body = EmptyState(
        icon: Icons.inbox_outlined,
        title: widget.emptyTitle,
        subtitle: widget.emptySubtitle,
        actionLabel: widget.onCreate != null ? 'Add ' : null,
        onAction: widget.onCreate,
      );
    } else {
      body = ApexDataTable<T>(
        controller: widget.tableCtrl,
        columns: widget.columns,
        rows: rows,
        isLoading: isLoading,
        error: errMsg,
        onRetry: () => ref
            .read(widget.provider.notifier)
            .load(widget.tableCtrl.toListQuery()),
        onRowTap: widget.onRowTap,
        searchHint: widget.searchHint,
        filterChips: widget.filterChips,
        emptyTitle: widget.emptyTitle,
        emptySubtitle: widget.emptySubtitle,
        onEmptyAction: widget.onCreate,
        emptyActionLabel: widget.onCreate != null ? 'Add ' : null,
      );
    }

    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: canPop
          ? AppBar(elevation: 0, backgroundColor: Colors.transparent)
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: widget.title,
            subtitle: widget.emptySubtitle,
            actions: [
              if (widget.onCreate != null)
                ResponsiveLayout.isMobile(context)
                    ? FilledButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Add'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        onPressed: widget.onCreate,
                      )
                    : FilledButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add New'),
                        onPressed: widget.onCreate,
                      ),
            ],
          ),
          const Divider(),
          Expanded(child: body),
        ],
      ),
    );
  }
}
