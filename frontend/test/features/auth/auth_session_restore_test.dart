import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexbooks/core/network/auth_token_state.dart';
import 'package:apexbooks/core/routing/router.dart';
import 'package:apexbooks/core/storage/session_storage.dart';
import 'package:apexbooks/features/auth/data/auth_repository.dart';
import 'package:apexbooks/features/auth/data/models/auth_models.dart';
import 'package:apexbooks/features/auth/data/models/membership_models.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';

const tenantId = 'tenant-1';
const userId = 'user-1';

UserModel _user() => UserModel(
  id: userId,
  email: 'qa@example.com',
  fullName: 'QA User',
  phoneNumber: '',
  isActive: true,
  emailVerified: true,
  totpEnabled: false,
  createdAt: DateTime.utc(2026, 1, 1),
);

Membership _membership() => const Membership(
  id: 'membership-1',
  tenantId: tenantId,
  role: MemberRole.owner,
  isActive: true,
  legalName: 'QA Company',
);

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({
    Result<UserModel>? meResult,
    Result<List<Membership>>? membershipsResult,
  }) : meResult = meResult ?? Success(_user()),
       membershipsResult = membershipsResult ?? Success([_membership()]),
       super(Dio());

  Result<UserModel> meResult;
  Result<List<Membership>> membershipsResult;
  int meCalls = 0;
  int membershipCalls = 0;

  @override
  Future<Result<UserModel>> me() async {
    meCalls++;
    return meResult;
  }

  @override
  Future<Result<List<Membership>>> memberships() async {
    membershipCalls++;
    return membershipsResult;
  }
}

class MemorySessionStorage extends SessionStorage {
  MemorySessionStorage(
    SharedPreferences prefs, {
    this.session,
    this.cachedContext,
  }) : super(const FlutterSecureStorage(), prefs);

  StoredSession? session;
  CachedAuthContext? cachedContext;
  int clearCalls = 0;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<CachedAuthContext?> readCachedAuthContext() async => cachedContext;

  @override
  Future<void> writeCachedAuthContext(CachedAuthContext context) async {
    cachedContext = context;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    session = null;
    cachedContext = null;
  }
}

StoredSession _stored() => const StoredSession(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  activeTenantId: tenantId,
  activeRole: 'owner',
  userId: userId,
);

ProviderContainer _container(
  FakeAuthRepository repository,
  MemorySessionStorage storage,
) {
  return ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      sessionStorageProvider.overrideWithValue(storage),
    ],
  );
}

void main() {
  test('memberships accepts the production value envelope', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'value': [
                {
                  'id': 'membership-1',
                  'tenant_id': tenantId,
                  'tenant_name': 'QA Company',
                  'role': 'owner',
                  'is_active': true,
                },
              ],
            },
          ),
        ),
      ),
    );

    final result = await AuthRepository(dio).memberships();

    expect(result, isA<Success<List<Membership>>>());
    expect(
      (result as Success<List<Membership>>).value.single.tenantId,
      tenantId,
    );
  });

  test(
    'valid persisted session restores token, tenant, and authenticated state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = MemorySessionStorage(prefs, session: _stored());
      final repository = FakeAuthRepository(
        meResult: Success(_user()),
        membershipsResult: Success([_membership()]),
      );
      final container = _container(repository, storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).restore();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.activeMembership?.tenantId, tenantId);
      expect(container.read(authTokenProvider).accessToken, 'access-token');
      expect(container.read(authTokenProvider).activeTenantId, tenantId);
      expect(repository.meCalls, 1);
      expect(repository.membershipCalls, 1);
    },
  );

  test('expired session is cleared and exits to unauthenticated', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = MemorySessionStorage(prefs, session: _stored());
    final repository = FakeAuthRepository(
      meResult: const Failure(ApiError(message: 'expired', statusCode: 401)),
    );
    final container = _container(repository, storage);
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(storage.clearCalls, 1);
    expect(container.read(authTokenProvider).isAuthenticated, false);
  });

  test('transient network failure restores a recent offline context', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = MemorySessionStorage(
      prefs,
      session: _stored(),
      cachedContext: CachedAuthContext(
        user: _user().toJson(),
        memberships: [_membership().toJson()],
        validatedAt: DateTime.now().toUtc(),
      ),
    );
    final repository = FakeAuthRepository(
      meResult: const Failure(ApiError(message: 'offline')),
      membershipsResult: const Failure(ApiError(message: 'offline')),
    );
    final container = _container(repository, storage);
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();

    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.authenticated);
    expect(state.isOfflineSession, isTrue);
    expect(state.activeMembership?.tenantId, tenantId);
    expect(storage.clearCalls, 0);
  });

  test('expired offline context is not authorized', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = MemorySessionStorage(
      prefs,
      session: _stored(),
      cachedContext: CachedAuthContext(
        user: _user().toJson(),
        memberships: [_membership().toJson()],
        validatedAt: DateTime.now().toUtc().subtract(const Duration(days: 8)),
      ),
    );
    final repository = FakeAuthRepository(
      meResult: const Failure(ApiError(message: 'offline')),
      membershipsResult: const Failure(ApiError(message: 'offline')),
    );
    final container = _container(repository, storage);
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(storage.clearCalls, 0);
  });

  test('malformed session is cleared instead of remaining on splash', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = MemorySessionStorage(prefs, session: null);
    final container = _container(FakeAuthRepository(), storage);
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(storage.clearCalls, 1);
  });

  test('storage exception exits loading and clears the session', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = _ThrowingSessionStorage(prefs);
    final container = _container(FakeAuthRepository(), storage);
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restore();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(storage.clearCalls, 1);
  });

  test('concurrent restore calls execute only one restoration', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = MemorySessionStorage(prefs, session: _stored());
    final repository = FakeAuthRepository(
      meResult: Success(_user()),
      membershipsResult: Success([_membership()]),
    );
    final container = _container(repository, storage);
    addTearDown(container.dispose);

    final first = container.read(authControllerProvider.notifier).restore();
    final second = container.read(authControllerProvider.notifier).restore();
    await Future.wait([first, second]);

    expect(repository.meCalls, 1);
    expect(repository.membershipCalls, 1);
  });

  test('router redirects authenticated tenant from login to the shell', () {
    final state = AuthState(
      status: AuthStatus.authenticated,
      user: _user(),
      memberships: [_membership()],
      activeMembership: _membership(),
    );
    expect(authRedirect(state, '/login'), '/');
    expect(authRedirect(state, '/splash'), '/');
    expect(authRedirect(state, '/'), isNull);
    expect(authRedirect(const AuthState(), '/'), '/splash');
    expect(
      authRedirect(const AuthState(status: AuthStatus.unauthenticated), '/'),
      '/login',
    );
  });
}

class _ThrowingSessionStorage extends MemorySessionStorage {
  _ThrowingSessionStorage(super.prefs);

  @override
  Future<StoredSession?> read() =>
      Future<StoredSession?>.error(StateError('storage unavailable'));
}
