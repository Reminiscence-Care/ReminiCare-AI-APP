import 'package:flutter/material.dart';

class MusicYearsSelectionScreen extends StatelessWidget {
  final String? musicLanguage;
  const MusicYearsSelectionScreen ({
    super.key, this.musicLanguage
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(musicLanguage ?? '國語歌')),
      body: Center(

      ),
    );
  }
}