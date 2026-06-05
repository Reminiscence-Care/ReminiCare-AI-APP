import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MusicScreen extends StatelessWidget {
  const MusicScreen ({super.key});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(title: const Text('音樂')),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                context.push('/music_years_selection_screen/國語歌');
              },
              child: Container(
                width: screenWidth * 0.35,
                margin: const EdgeInsets.all(16.0),
                child: Image.asset(
                  'assets/images/mandarin_songs.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),

            GestureDetector(
              onTap: () {
                context.push('/music_years_selection_screen/台語歌');
              },
              child: Container(
                width: screenWidth * 0.35,
                margin: const EdgeInsets.all(16.0),
                child: Image.asset(
                  'assets/images/taiwanese_songs.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}