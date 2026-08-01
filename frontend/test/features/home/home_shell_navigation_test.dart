import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:apexbooks/core/database/database_provider.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/logging/logger_service.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/theme/app_theme.dart';
import 'package:apexbooks/features/auth/data/models/membership_models.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import 'package:apexbooks/features/home/home_shell.dart';
import 'package:apexbooks/features/masters/accounts/data/repositories/account_repository.dart';
import 'package:apexbooks/features/masters/accounts/presentation/account_controller.dart';

class _AuthenticatedController extends AuthController {
  @override
  AuthState build() => const AuthState(
    status: AuthStatus.authenticated,
    activeMembership: Membership(
      id: 'membership-1',
      tenantId: 'tenant-1',
      role: MemberRole.owner,
      isActive: true,
      legalName: 'Test Company',
      taxMode: 'NON_GST',
    ),
  );
}

class _EmptyApiAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode([]),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

class _NoopAccountController extends AccountController {
  _NoopAccountController()
    : super(
        AccountRepository(Dio(BaseOptions()), CacheService(LoggerService())),
        NotificationService(),
      );

  @override
  Future<void> load(ListQuery query) async {}
}

void main() {
  testWidgets(
    'Reports to Accounting mounts the journal hub and survives rebuild',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dio = Dio(
        BaseOptions(
          connectTimeout: Duration.zero,
          receiveTimeout: Duration.zero,
          sendTimeout: Duration.zero,
        ),
      );
      dio.httpClientAdapter = _EmptyApiAdapter();
      final router = GoRouter(
        initialLocation: '/?section=reports',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                HomeShell(section: state.uri.queryParameters['section']),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_AuthenticatedController.new),
            accountControllerProvider.overrideWith(
              (ref) => _NoopAccountController(),
            ),
            databaseProvider.overrideWithValue(db),
            apiClientProvider.overrideWithValue(dio),
          ],
          child: MaterialApp.router(
            theme: apexLightTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('home-nav-reports')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-nav-accounting')));
      // Avoid waiting on provider/network futures from the mounted screens; the
      // router transition and selected destination are synchronous here.
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        router.routeInformationProvider.value.uri.queryParameters['section'],
        'accounting',
      );
      expect(find.byKey(const ValueKey('accounting-hub')), findsOneWidget);
      expect(find.text('Journals'), findsOneWidget);

      await tester.pump();
      expect(find.byKey(const ValueKey('accounting-hub')), findsOneWidget);
      expect(find.text('Journals'), findsOneWidget);
    },
  );
}
