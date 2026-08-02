// InvoiceDetail provider tests.
//
// Verifies the Riverpod `invoiceDetailProvider` used by InvoiceDetailScreen
// resolves through InvoiceService and surfaces failures as ApiError (so the
// screen can distinguish 404 / 401 / 500 / network).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/presentation/design_system/theme/app_theme.dart';
import 'package:apexbooks/features/auth/data/models/membership_models.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import 'package:apexbooks/features/sales/presentation/invoice_detail_screen.dart';
import 'package:apexbooks/features/sales/services/invoice_service.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

AuthState _authState() => const AuthState(
  status: AuthStatus.authenticated,
  activeMembership: Membership(
    id: 'm-1',
    tenantId: 't-1',
    role: MemberRole.owner,
    isActive: true,
    legalName: 'Test Company',
    gstin: '27AAACT1234A1Z1',
  ),
);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object data) => ResponseBody.fromBytes(
  Uint8List.fromList(utf8.encode(jsonEncode(data))),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _detailJson() => {
  'id': 'inv-1',
  'invoice_number': 'INV/1',
  'status': 'DRAFT',
  'issue_date': '2026-08-03',
  'due_date': '2026-08-03',
  'pos_state_code': '27',
  'subtotal': '5000.0000',
  'total': '5900.0000',
  'amount_paid': '0.0000',
  'e_invoice_status': 'PENDING',
  'lines': [
    {
      'id': 'line-1',
      'product_id': 'prod-1',
      'product_name': 'MacBook Pro M3 Max',
      'quantity': '1',
      'rate': '5000.0000',
      'hsn_sac': '84713010',
      'gst_rate': '18.00',
      'subtotal': '5000.0000',
      'cgst_amount': '450.0000',
      'sgst_amount': '450.0000',
      'igst_amount': '0.0000',
      'total': '5900.0000',
    },
  ],
  'contact': {'name': 'Tata Consultancy Services Ltd'},
};

void main() {
  test('invoiceDetailProvider resolves a parsed Invoice', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
      ..httpClientAdapter = _FakeAdapter(
        (options) async => _json(200, _detailJson()),
      );
    final container = ProviderContainer(
      overrides: [
        invoiceServiceProvider.overrideWithValue(InvoiceService(dio)),
      ],
    );
    addTearDown(container.dispose);

    final invoice = await container.read(invoiceDetailProvider('inv-1').future);
    expect(invoice.id, 'inv-1');
    expect(invoice.customerName, 'Tata Consultancy Services Ltd');
    expect(invoice.total, 5900.0);
    expect(invoice.lines.length, 1);
  });

  test('invoiceDetailProvider surfaces a 404 as ApiError not found', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
      ..httpClientAdapter = _FakeAdapter(
        (options) async => _json(404, {
          'detail': 'Invoice not found in this company context.',
        }),
      );
    final container = ProviderContainer(
      overrides: [
        invoiceServiceProvider.overrideWithValue(InvoiceService(dio)),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(invoiceDetailProvider('missing').future),
      throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test(
    'invoiceDetailProvider surfaces a 500 as ApiError server error',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
        ..httpClientAdapter = _FakeAdapter(
          (options) async => _json(500, {'detail': 'boom'}),
        );
      final container = ProviderContainer(
        overrides: [
          invoiceServiceProvider.overrideWithValue(InvoiceService(dio)),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(invoiceDetailProvider('inv-1').future),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.isServer, 'isServer', true),
        ),
      );
    },
  );

  testWidgets('InvoiceDetailScreen renders the loaded detail', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dio = Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
      ..httpClientAdapter = _FakeAdapter(
        (options) async => _json(200, _detailJson()),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoiceServiceProvider.overrideWithValue(InvoiceService(dio)),
          numberFormatterProvider.overrideWithValue(NumberFormatter()),
          authControllerProvider.overrideWith(
            () => _StubAuthController(_authState()),
          ),
        ],
        child: MaterialApp(
          theme: buildApexTheme(Brightness.light),
          home: const InvoiceDetailScreen(invoiceId: 'inv-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('INV/1'), findsOneWidget);
    expect(find.text('Tata Consultancy Services Ltd'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('MacBook Pro M3 Max'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
