import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/home_screen.dart';
import 'package:remini_care_ai_app/screens/life_screen/life_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/music_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/music_years_selection_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/local_music_screen.dart';
import 'package:remini_care_ai_app/screens//music_screen/select_songs_screen.dart';
import 'package:remini_care_ai_app/screens//music_screen/play_music_screen.dart';

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
    GoRoute(
    // 接收 language (國語歌) 與 year (1950-1960) 兩個參數
      path: '/select_songs_screen/:language/:year',
      builder: (context, state) {
      final language = state.pathParameters['language'] ?? '國語歌';
      final year = state.pathParameters['year'] ?? '未知年代';
      return SelectSongsScreen(language: language, year: year);
      }
    ),
    GoRoute(
      path: '/play_music_screen',
      builder: (context, state) {
      // 透過 extra 接收一整包歌曲資訊 (Map 格式)
      final songData = state.extra as Map<String, dynamic>;
      return PlayMusicScreen(songData: songData);
      }
    )
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