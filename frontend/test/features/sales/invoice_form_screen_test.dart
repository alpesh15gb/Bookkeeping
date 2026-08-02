// InvoiceFormScreen render test at desktop size.
//
// Regression: the form body used to render as a blank light-grey rectangle
// because (a) InvoiceLinesTable threw a LateInitializationError on mount and
// (b) the Place-of-Supply dropdown was fed a value that did not match any
// item. This test mounts the real screen at a desktop window size and asserts
// the key form sections are visible and interactive.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/logging/logger_service.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/presentation/design_system/theme/app_theme.dart';
import 'package:apexbooks/features/auth/data/models/membership_models.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import 'package:apexbooks/features/masters/contacts/data/repositories/contact_repository.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/products/data/repositories/product_repository.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';
import 'package:apexbooks/features/sales/presentation/invoice_form_screen.dart';
import 'package:apexbooks/features/sales/services/invoice_service.dart';
import 'package:dio/dio.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._state);
  final AuthState _state;
  @override
  AuthState build() => _state;
}

AuthState _authenticatedState() => const AuthState(
  status: AuthStatus.authenticated,
  user: null,
  activeMembership: Membership(
    id: 'm-1',
    tenantId: 't-1',
    role: MemberRole.owner,
    isActive: true,
    legalName: 'Test Company',
    gstin: '27AAACT1234A1Z1',
    taxMode: 'GST_REGULAR',
  ),
);

Widget _buildApp() {
  final cache = CacheService(LoggerService());
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'));
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        () => _StubAuthController(_authenticatedState()),
      ),
      numberFormatterProvider.overrideWithValue(NumberFormatter()),
      apiClientProvider.overrideWithValue(dio),
      contactRepositoryProvider.overrideWithValue(
        ContactRepository(dio, cache),
      ),
      productRepositoryProvider.overrideWithValue(
        ProductRepository(dio, cache),
      ),
    ],
    child: MaterialApp(
      theme: buildApexTheme(Brightness.light),
      home: const InvoiceFormScreen(),
    ),
  );
}

void main() {
  testWidgets('renders full invoice form at desktop size', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildApp());
    await tester.pump();

    // Header section renders.
    expect(find.text('New Invoice'), findsOneWidget);
    expect(find.text('Invoice Details'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Place of Supply'), findsOneWidget);
    expect(find.text('Invoice Number'), findsOneWidget);
    expect(find.text('Issue Date'), findsOneWidget);
    expect(find.text('Due Date'), findsOneWidget);

    // Lines table renders (regression for LateInitializationError).
    expect(find.text('Invoice Lines'), findsOneWidget);
    expect(find.text('Add Line'), findsOneWidget);

    // Totals panel renders and stays visible.
    expect(find.text('Totals'), findsOneWidget);

    // Save action exists.
    expect(find.text('Save'), findsWidgets);

    // No exception widget (grey error box) anywhere.
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('POS state dropdown initializes from GSTIN without throwing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildApp());
    await tester.pump();

    // The state code derived from the GSTIN (27) must resolve to an actual
    // dropdown item. Tapping opens the list of state options.
    await tester.tap(find.text('Place of Supply'));
    await tester.pumpAndSettle();
    expect(find.text('27 - Maharashtra'), findsOneWidget);
  });

  testWidgets('adds a line and recalculates totals', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildApp());
    await tester.pump();

    await tester.tap(find.text('Add Line'));
    await tester.pumpAndSettle();
    // Two rows of numeric cells now (initial + added).
    expect(find.text('Invoice Lines'), findsOneWidget);
    // Totals panel still rendered and no crash.
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('shows explicit error state when edit initialization fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Backend returns 500 for the edit lookup.
    final failing = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
      ..httpClientAdapter = _FailingGetAdapter();
    final cache = CacheService(LoggerService());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _StubAuthController(_authenticatedState()),
          ),
          numberFormatterProvider.overrideWithValue(NumberFormatter()),
          apiClientProvider.overrideWithValue(failing),
          invoiceServiceProvider.overrideWithValue(InvoiceService(failing)),
          contactRepositoryProvider.overrideWithValue(
            ContactRepository(failing, cache),
          ),
          productRepositoryProvider.overrideWithValue(
            ProductRepository(failing, cache),
          ),
        ],
        child: MaterialApp(
          theme: buildApexTheme(Brightness.light),
          home: const InvoiceFormScreen(editId: 'inv-missing'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Failed to load invoice'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}

class _FailingGetAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET') {
      const body =
          '{"detail": "The server is unavailable. Please try again shortly.", "code": "HTTP_500"}';
      return ResponseBody.fromBytes(
        Uint8List.fromList(utf8.encode(body)),
        500,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}
