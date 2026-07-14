import 'pages/account/login_page.dart';
import 'pages/account/password_page.dart';
import 'pages/index_tab/my_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'pages/index_tab/device_page.dart';
import 'pages/index_tab/device_qr_scan_page.dart';
import 'pages/video/video_list_page.dart';
import 'pages/video/video_player_page.dart';

import 'pages/account/password_type.dart';
import 'pages/index_tab/index_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey =
GlobalKey<NavigatorState>(debugLabel: 'shell');

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/index',
  observers: [FlutterSmartDialog.observer],
  debugLogDiagnostics: kDebugMode,
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
      path: '/password',
      name: ChangePasswordPage.sName,
      builder: (BuildContext context, GoRouterState state) {
        final type = state.extra as ChangePasswordType?;
        if (type == null) {
          throw ArgumentError(
              'ChangePasswordType must be provided when navigating to PasswordPage');
        }
        return ChangePasswordPage(type: type);
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
  const ScaffoldWithNavBar({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.devices),
            label: 'Devices',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'My',
          ),
        ],
        currentIndex: _calculateSelectedIndex(context),
        onTap: (int idx) => _onItemTapped(idx, context),
      ),
    );
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/index')) { // Changed from '/a'
      return 0;
    }
    if (location.startsWith('/device')) { // Changed /b to /device
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
