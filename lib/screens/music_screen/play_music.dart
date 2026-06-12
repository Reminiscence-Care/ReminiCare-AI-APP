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
      body:
        WebViewWidget(controller: _controller),
    );
  }
}