import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {

                    },
                    child: Image.asset('assets/images/music_home.png'),
                  ),
                  Text('以前愛聽的歌')
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {

                    },
                    child: Image.asset('assets/images/life_home.png'),
                  ),
                  Text('以前的生活')
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}