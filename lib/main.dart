import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/home_screen.dart';
import 'package:remini_care_ai_app/life_screen.dart';
import 'package:remini_care_ai_app/music_screen.dart';
import 'package:remini_care_ai_app/music_years_selection_screen.dart';
import 'package:remini_care_ai_app/local_music_screen.dart';

void main() {
  runApp(const MyApp());
}
final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/life_screen',
      builder: (context, state) => const LifeScreen(),
    ),
    GoRoute(
      path: '/music_screen',
      builder: (context, state) => const MusicScreen(),
    ),
    GoRoute(
      path: '/music_years_selection_screen/:musicLanguage',
      builder: (context, state) {
        final musicLanguage = state.pathParameters['musicLanguage'];
        return MusicYearsSelectionScreen(musicLanguage: musicLanguage);
      }
    ),
    GoRoute(
      path: '/local_music_screen',
      builder: (context, state) => const LocalMusicScreen(),
    ),
  ]
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
    );
  }
}