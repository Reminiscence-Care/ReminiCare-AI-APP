import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:remini_care_ai_app/models/song_model.dart';
import 'package:remini_care_ai_app/home_screen.dart';
import 'package:remini_care_ai_app/screens/life_screen/life_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/music_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/music_years_selection_screen.dart';
import 'package:remini_care_ai_app/screens//music_screen/select_songs_screen.dart';
import 'package:remini_care_ai_app/screens//music_screen/play_music_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/add_songs_data_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(SongModelAdapter());
  await Hive.openBox<SongModel>('my_music_box');
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
        path: '/select_songs_screen/:musicLanguage/:yearLabel',
        builder: (context, state) {
          final musicLanguage = state.pathParameters['musicLanguage'] ?? '國語歌';
          final yearLabel = state.pathParameters['yearLabel'] ?? '1950-1960';

          return SelectSongsScreen(
            musicLanguage: musicLanguage,
            yearLabel: yearLabel,
          );
        }
    ),

    GoRoute(
        path: '/play_music_screen',
        builder: (context, state) {
          // 👈 型別精準轉換為 Map<String, String>
          final songData = state.extra as Map<String, String>;
          return PlayMusicScreen(songData: songData);
        }
    ),
    GoRoute(
      path: '/add_songs_data_screen',
      builder: (context, state) =>  AddSongsDataScreen()
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