import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:remini_care_ai_app/models/song_model.dart';
import 'package:remini_care_ai_app/home_screen.dart';
import 'package:remini_care_ai_app/screens/life_screen/life_screen.dart';
import 'package:remini_care_ai_app/screens/music_screen/music_screen.dart';

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