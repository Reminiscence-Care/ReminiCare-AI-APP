import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_win_floating/webview.dart';

class PlayMusic extends StatefulWidget {
  final String embedUrl;
  const PlayMusic({super.key, required this.embedUrl});

  @override
  State<StatefulWidget> createState() => _PlayMusicState();
}

class _PlayMusicState extends State<PlayMusic> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isWindows) {
      params = WindowsWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.embedUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('音樂播放')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // 💡 關鍵修正 2：用 SizedBox 給 WebView 明確的高度與寬度！
            SizedBox(
              height: 600, // Spotify Embed 的標準高度通常是 152 或 352
              width: 1000,  // 給予一個合理的寬度
              child: WebViewWidget(controller: _controller),
            ),

            const SizedBox(height: 20), // 加上一點間距
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0), // 淡米黃色背景
                borderRadius: BorderRadius.circular(12), // 整體圓角
                border: const Border(
                  left: BorderSide(
                    color: Color(0xFFB95A38), // 左側深橘色
                    width: 8.0,               // 粗細
                  ),
                ),
              ),
              child: const Text(
                "這首歌你有聽過嗎？",
                style: TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5D4037), // 深棕色文字
                ),
              ),
            )

          ],
        ),
      )

    );
  }
}