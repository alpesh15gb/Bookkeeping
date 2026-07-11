/// The app-wide [GoRouter] with auth-aware redirects.
///
/// Redirect logic:
///   * `initial` (still restoring session) → splash.
///   * `unauthenticated` on a protected route → `/login`.
///   * `authenticated` without an active tenant on the home route →
///     `/select-company`.
///   * `authenticated` with an active tenant on an auth route → `/`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/auth_routes.dart' as auth_routes;
import '../../features/auth/presentation/company_selection_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/home/home_shell.dart';
import '../../app/app_splash.dart';

/// Provider that exposes the configured [GoRouter]. It listens to the auth
/// controller so redirects re-evaluate on every auth state change.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.listen<AuthState>(authControllerProvider, (_, next) {
    auth.value = next;
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final status = auth.value.status;
      final location = state.uri.toString();
      final isAuthRoute =
          location == auth_routes.login ||
          location == auth_routes.register ||
          location == auth_routes.forgotPassword ||
          location.startsWith(auth_routes.resetPassword);
      final isCompanyRoute = location == auth_routes.companySelection;

      switch (status) {
        case AuthStatus.initial:
          // While restoring the session, hold on the splash.
          return location == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return isAuthRoute ? null : auth_routes.login;
        case AuthStatus.authenticated:
          final hasTenant = auth.value.hasActiveTenant;
          if (isAuthRoute) {
            // Signed in but sitting on a login page → go home or pick company.
            return hasTenant ? '/' : auth_routes.companySelection;
          }
          if (!hasTenant && !isCompanyRoute) {
            return auth_routes.companySelection;
          }
          if (hasTenant && isCompanyRoute) {
            return '/';
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const AppSplash(),
      ),
      GoRoute(
        path: auth_routes.login,
        name: auth_routes.loginName,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: auth_routes.register,
        name: auth_routes.registerName,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: auth_routes.forgotPassword,
        name: auth_routes.forgotPasswordName,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: auth_routes.resetPassword,
        name: auth_routes.resetPasswordName,
        builder: (context, state) => ResetPasswordScreen(
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: auth_routes.companySelection,
        name: auth_routes.companySelectionName,
        builder: (context, state) => const CompanySelectionScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeShell(),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
});
