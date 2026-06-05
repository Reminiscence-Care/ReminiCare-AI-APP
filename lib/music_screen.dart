import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MusicScreen extends StatelessWidget {
  const MusicScreen ({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音樂')),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    context.push('/music_years_selection_screen/國語歌');
                  },
                  child: Image.asset('assets/images/mandarin_songs.png'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    context.push('/music_years_selection_screen/台語歌');
                  },
                  child: Image.asset('assets/images/taiwanese_songs.png'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}