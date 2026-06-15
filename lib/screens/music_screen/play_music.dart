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

  // 用來追蹤是否發生錯誤的狀態變數
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    // 檢查傳進來的 URL 是否為空
    if (widget.embedUrl.isEmpty) {
      _hasError = true;
      return; // 直接中斷，不初始化 WebView
    }

    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isWindows) {
      params = WindowsWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final String autoPlayUrl = "${widget.embedUrl}?autoplay=1";

    try {
      final uri = Uri.parse(autoPlayUrl);

      _controller = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 監聽 WebView 載入過程中的各種錯誤
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (WebResourceError error) {
              print("WebView 載入失敗: ${error.description}");
              // 如果發生錯誤，更新畫面顯示提醒介面
              if (mounted) {
                setState(() {
                  _hasError = true;
                });
              }
            },
          ),
        )
        ..loadRequest(uri);
    } catch (e) {
      // 捕捉 Uri.parse 解析失敗的例外（例如網址含有非法字元）
      print("網址格式錯誤: $e");
      _hasError = true;
    }
  }

  // 專屬的錯誤提醒介面
  Widget _buildErrorUI() {
    return Container(
      height: 352, // 維持原本 WebView 的高度，避免畫面突然縮水
      width: 1000,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[400]!, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.music_off, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text(
            "哎呀，找不到這首歌的播放連結",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              // 點擊後返回上一頁
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text("換一首歌試試看", style: TextStyle(fontSize: 24)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              backgroundColor: const Color(0xFFB95A38),
              foregroundColor: Colors.white,
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音樂播放')),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 根據 _hasError 狀態，決定要顯示 WebView 還是錯誤介面
              _hasError
                  ? _buildErrorUI()
                  : SizedBox(
                height: 600, // 注意：600 可能在小螢幕會有點太高，可視情況調整
                width: 1000,
                child: WebViewWidget(controller: _controller),
              ),

              const SizedBox(height: 15),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(
                    left: BorderSide(
                      color: Color(0xFFB95A38),
                      width: 8.0,
                    ),
                  ),
                ),
                child: const Text(
                  "這首歌你有聽過嗎？",
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5D4037),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}