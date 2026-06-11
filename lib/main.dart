import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:remini_care_ai_app/models/song_model.dart';
import 'package:remini_care_ai_app/home_screen.dart';
import 'package:remini_care_ai_app/screens/life_screen/life_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/music_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/play_music.dart';
import 'package:remini_care_ai_app/screens/music_screen/search_and_recommendation.dart';
import 'package:remini_care_ai_app/screens/music_screen/search_by_texts_or_speech.dart';
import 'package:remini_care_ai_app/screens/music_screen/search_options.dart';
import 'package:remini_care_ai_app/screens/music_screen/search_results.dart';


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
      path: '/search_and_recommendation/:languageLabel',
      builder: (context, state) {
        final languageLabel = state.pathParameters['languageLabel'];
        return SearchAndRecommendation(languageLabel: languageLabel);
      },
    ),
    GoRoute(
      path: '/search_options/:languageLabel',
      builder: (context, state) {
        final languageLabel = state.pathParameters['languageLabel'];
        return SearchOptions(languageLabel: languageLabel);
      },
    ),
    GoRoute(
      path: '/search_by_texts_or_speech/:texts_or_speech/:languageLabel',
      builder: (context, state) {
        final texts_or_speech = state.pathParameters['texts_or_speech'];
        final languageLabel = state.pathParameters['languageLabel'];

        return SearchByTextsOrSpeech(texts_or_speech: texts_or_speech, languageLabel: languageLabel);
      },
    ),
    GoRoute(
      path: '/search_results/:value/:languageLabel',
      builder: (context, state) {
        final value = state.pathParameters['value'];
        final languageLabel = state.pathParameters['languageLabel'];
        return SearchResults(value: value, languageLabel: languageLabel);
      }
    ),
    GoRoute(
      path: '/play_music/:embedUrl',
      builder: (context, state) {
        var embedUrl = state.pathParameters['embedUrl'];
        if(embedUrl == "" || embedUrl == null){
          embedUrl = 'https://open.spotify.com/embed';
        }
        return PlayMusic(embedUrl: embedUrl);
      }
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