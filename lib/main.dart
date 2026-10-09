import 'package:flutter/material.dart';
import 'services/app_log.dart';
import 'screens/app_log_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/home_screen.dart';
import 'package:remini_care_ai_app/screens/history_screen.dart';
import 'package:remini_care_ai_app/screens/life_screen/life_screen.dart';
import 'package:remini_care_ai_app/screens/tts_cache_screen.dart';
import 'package:remini_care_ai_app/theme/remini_care_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.instance.record(LogArea.app, LogEvent.started);
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.instance.record(LogArea.app, LogEvent.frameworkError);
    previousErrorHandler?.call(details);
  };
  runApp(const MyApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();
final GoRouter _router = GoRouter(
  navigatorKey: _navigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/life_screen',
      builder: (context, state) => const LifeScreen(),
    ),
    GoRoute(
      path: '/history_screen',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/tts_cache_screen',
      builder: (context, state) => const TtsCacheScreen(),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      builder: (context, child) => AppLogOverlay(
        navigatorKey: _navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      debugShowCheckedModeBanner: false,
      title: 'ReminiCare AI',
      theme: ReminiCareTheme.light,
    );
  }
}
