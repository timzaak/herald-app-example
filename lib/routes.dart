import 'main.dart';
import 'pages/account/consent_gate_page.dart';
import 'pages/account/login_page.dart';
import 'pages/account/password_page.dart';
import 'pages/account/register_page.dart';
import 'pages/account/reset_password_confirm_page.dart';
import 'pages/account/totp_verify_page.dart';
import 'pages/account/verify_email_pending_page.dart';
import 'pages/index_tab/my_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'pages/index_tab/device_page.dart';
import 'pages/index_tab/device_qr_scan_page.dart';
import 'pages/video/video_list_page.dart';
import 'pages/video/video_player_page.dart';
import 'providers/auth_providers.dart';
import 'services/auth/auth_result.dart';

import 'pages/account/password_type.dart';
import 'pages/index_tab/index_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell',
);

/// Anonymous-route whitelist for the login-state redirect guard (design §4.4.3).
///
/// Routes whose paths appear here are reachable without an authenticated
/// session. FL-D03 pre-included all 7 anonymous paths (the three FL-D04 paths
/// `/register`, `/verify-email-pending`, `/reset-password-confirm` were added
/// ahead of FL-D04's route entries); FL-D04 only adds the corresponding
/// `GoRoute` builders. Do not restructure the guard.
const Set<String> _anonymousPaths = {
  '/login',
  '/register',
  '/verify-email-pending',
  '/totp-verify',
  '/consent',
  '/password',
  '/reset-password-confirm',
};

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/index',
  observers: [FlutterSmartDialog.observer],
  debugLogDiagnostics: kDebugMode,
  // Login-state redirect guard (design §4.4.3). Reads the frozen top-level
  // `heraldContainer` (declared in `main.dart`) synchronously. When the user
  // hits a protected route while unauthenticated, redirect to `/login` with
  // the original location encoded as `?returnTo=`; `LoginPage` consumes the
  // query param on success. When authenticated and sitting on `/login`,
  // redirect to `/index` so a logged-in user never sees the login page.
  redirect: (BuildContext context, GoRouterState state) {
    final authed =
        heraldContainer.read(authStateProvider).status ==
        AuthStatus.authenticated;
    final location = state.matchedLocation;
    if (!authed && !_anonymousPaths.contains(location)) {
      final encoded = Uri.encodeComponent(state.uri.toString());
      return '/login?returnTo=$encoded';
    }
    if (authed && location == '/login') {
      return '/index';
    }
    return null;
  },
  routes: <RouteBase>[
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (BuildContext context, GoRouterState state, Widget child) {
        return ScaffoldWithNavBar(child: child);
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/index', // Changed from '/a'
          builder: (BuildContext context, GoRouterState state) {
            return const IndexPage(); // Use IndexPage
          },
        ),

        GoRoute(
          path: '/device', // Changed path to /device
          name: DevicePage.sName, // Added name for the route
          builder: (BuildContext context, GoRouterState state) {
            return const DevicePage(); // Changed to DevicePage
          },
          routes: <RouteBase>[
            GoRoute(
              path: '/qr_scan',
              name: DeviceQrScanPage.sName,
              builder: (BuildContext context, GoRouterState state) {
                return const DeviceQrScanPage();
              },
            ),
          ],
        ),

        GoRoute(
          path: '/my',
          name: MyPage.sName,
          builder: (BuildContext context, GoRouterState state) {
            return const MyPage();
          },
        ),
      ],
    ),
    GoRoute(
      path: '/login',
      name: LoginPage.sName, // Assuming LoginPage has sName
      builder: (BuildContext context, GoRouterState state) {
        return const LoginPage();
      },
    ),
    GoRoute(
      path: '/totp-verify',
      name: TotpVerifyPage.sName,
      builder: (BuildContext context, GoRouterState state) {
        // `extra` is a plain map (design §4.4.3 extra-map convention):
        //   {'tempToken': String, 'secondFactors': List<String>}
        final extra = state.extra as Map<String, dynamic>?;
        final tempToken = (extra?['tempToken'] as String?) ?? '';
        final secondFactorsRaw = extra?['secondFactors'];
        final secondFactors = secondFactorsRaw is List
            ? secondFactorsRaw.whereType<String>().toList(growable: false)
            : const <String>[];
        return TotpVerifyPage(
          tempToken: tempToken,
          secondFactors: secondFactors,
        );
      },
    ),
    GoRoute(
      path: '/consent',
      name: ConsentGatePage.sName,
      builder: (BuildContext context, GoRouterState state) {
        // `extra` is a plain map (design §4.4.3 extra-map convention):
        //   {'agreements': List<AgreementView>,
        //    'originalFlow': {'kind': 'password'|'email-otp'|'totp', ...}}
        final extra = state.extra as Map<String, dynamic>?;
        final agreementsRaw = extra?['agreements'];
        final agreements = agreementsRaw is List
            ? agreementsRaw.whereType<AgreementView>().toList(growable: false)
            : const <AgreementView>[];
        final originalFlow =
            (extra?['originalFlow'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
        return ConsentGatePage(
          agreements: agreements,
          originalFlow: originalFlow,
        );
      },
    ),
    GoRoute(
      path: '/password',
      name: ChangePasswordPage.sName,
      builder: (BuildContext context, GoRouterState state) {
        final type = state.extra as ChangePasswordType?;
        if (type == null) {
          throw ArgumentError(
            'ChangePasswordType must be provided when navigating to PasswordPage',
          );
        }
        return ChangePasswordPage(type: type);
      },
    ),
    GoRoute(
      path: '/register',
      name: RegisterPage.sName,
      builder: (BuildContext context, GoRouterState state) {
        return const RegisterPage();
      },
    ),
    GoRoute(
      path: '/verify-email-pending',
      name: VerifyEmailPendingPage.sName,
      builder: (BuildContext context, GoRouterState state) {
        // `extra` is a plain map (design §4.4.3 extra-map convention):
        //   {'email': String}
        final extra = state.extra as Map<String, dynamic>?;
        final email = extra?['email'];
        return VerifyEmailPendingPage(email: email is String ? email : '');
      },
    ),
    GoRoute(
      path: '/reset-password-confirm',
      name: ResetPasswordConfirmPage.sName,
      builder: (BuildContext context, GoRouterState state) {
        // `extra` is a plain map (design §4.4.3 extra-map convention):
        //   {'email': String} — email carried from the request step for context.
        final extra = state.extra as Map<String, dynamic>?;
        final email = extra?['email'];
        return ResetPasswordConfirmPage(email: email is String ? email : '');
      },
    ),
    GoRoute(
      path: '/videos',
      builder: (BuildContext context, GoRouterState state) {
        return const VideoListPage();
      },
    ),
    GoRoute(
      path: '/video_player/:videoUrl',
      builder: (BuildContext context, GoRouterState state) {
        final videoUrl = state.pathParameters['videoUrl']!;
        return VideoPlayerPage(videoUrl: Uri.decodeComponent(videoUrl));
      },
    ),
  ],
);

class ScaffoldWithNavBar extends StatelessWidget {
  /// Constructs an [ScaffoldWithNavBar].
  const ScaffoldWithNavBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'Devices'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'My'),
        ],
        currentIndex: _calculateSelectedIndex(context),
        onTap: (int idx) => _onItemTapped(idx, context),
      ),
    );
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/index')) {
      // Changed from '/a'
      return 0;
    }
    if (location.startsWith('/device')) {
      // Changed /b to /device
      return 1;
    }
    if (location.startsWith('/my')) {
      return 2;
    }
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        GoRouter.of(context).go('/index'); // Changed from '/a'
        break;
      case 1:
        GoRouter.of(context).go('/device'); // Changed /b to /device
        break;
      case 2:
        GoRouter.of(context).go('/my');
        break;
    }
  }
}
