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

    // 1：如果作業系統是 Windows，強制註冊 webview_win_floating 作為底層引擎
    if (Platform.isWindows) {
      WindowsWebViewPlatform.registerWith();
    }

    // 2：初始化 WebViewController
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // Spotify 依賴大量 JS，必須全開
      ..setBackgroundColor(Colors.transparent)         // 讓背景透明，融入你的 App UI
      ..loadRequest(Uri.parse(widget.embedUrl));       // 載入網址
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 152,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12), // 幫 Webview 加上漂亮的圓角
        child: WebViewWidget(controller: _controller),
      ),
    );
  }

}