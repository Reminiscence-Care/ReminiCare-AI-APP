import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class PlayMusicScreen extends StatefulWidget {
  final Map<String, String> songData;

  const PlayMusicScreen({super.key, required this.songData});

  @override
  State<PlayMusicScreen> createState() => _PlayMusicScreenState();
}

class _PlayMusicScreenState extends State<PlayMusicScreen> {
  // 宣告播放器核心
  late AudioPlayer _audioPlayer;

  // 狀態變數
  bool _isPlaying = false;
  Duration _duration = Duration.zero;  // 歌曲總長度
  Duration _position = Duration.zero;  // 目前播放進度

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudioPlayer();
  }

  // 初始化播放器並載入音樂檔案
  Future<void> _initAudioPlayer() async {
    try {
      String? audioPath = widget.songData['audioPath'];
      if (audioPath != null && audioPath.isNotEmpty) {

        File audioFile = File(audioPath);
        if (await audioFile.exists()) {

          // 💡 終極解法：讓 Dart 把 Windows 路徑轉成安全的 URI (會自動處理中文與斜線)
          final audioUri = Uri.file(audioPath);
          print('🔗 轉換後的安全 URI: $audioUri');

          // 捨棄 setFilePath，改用最穩定的 setAudioSource 搭配 URI
          await _audioPlayer.setAudioSource(AudioSource.uri(audioUri));

        } else {
          debugPrint("❌ 找不到檔案：$audioPath");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('找不到這首歌的音檔，可能是舊資料或檔案已遺失！')),
            );
          }
          return;
        }
      }

      // 1. 監聽播放狀態 (播放中 / 暫停中)
      _audioPlayer.playerStateStream.listen((playerState) {
        if(!mounted) return;
        setState(() {
          _isPlaying = playerState.playing;
        });

        // 防呆：如果播完了，自動重設進度到開頭
        if (playerState.processingState == ProcessingState.completed) {
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.pause();
        }
      });

      // 2. 監聽歌曲總時長
      _audioPlayer.durationStream.listen((totalDuration) {
        if(!mounted) return;
        setState(() {
          _duration = totalDuration ?? Duration.zero;
        });
      });

      // 3. 監聽目前播放進度（實時更新時間與進度條）
      _audioPlayer.positionStream.listen((currentPosition) {
        if(!mounted) return;
        setState(() {
          _position = currentPosition;
        });
      });

    } catch (e) {
      debugPrint("音樂載入失敗: $e");
    }
  }

  // 播放 / 暫停 切換按鈕
  void _togglePlayPause() {
    if (_isPlaying) {
      _audioPlayer.pause();
    } else {
      _audioPlayer.play();
    }
  }

  //  輔助函式：將 Duration 轉換為長輩看得懂的 00:00 格式
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  void dispose() {
    //  離開頁面時一定要釋放播放器資源，否則音樂會一直播不停
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 計算目前的進度比例 (0.0 到 1.0 之間)
    double progressValue = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF2EBE1),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('正在播放', style: TextStyle(color: Color(0xFF4E342E))),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF4E342E)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
          child: IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                //  左側卡片：歌手與照片資訊
                Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF9),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFF7A4A35), borderRadius: BorderRadius.circular(20)),
                        child: Text('${widget.songData['year']}年代', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(height: 12),
                      Text(widget.songData['language']!, style: const TextStyle(color: Color(0xFF7A4A35), fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 28),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 6))],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(widget.songData['image']!),
                            width: 180,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                                width: 180,
                                height: 180,
                                color: Colors.grey[300],
                                child: const Icon(Icons.person, size: 60, color: Colors.white)
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(widget.songData['singer']!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4E342E))),
                    ],
                  ),
                ),

                const SizedBox(width: 24),

                //  右側卡片：播放功能與歌詞控制
                Container(
                  width: 440,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF9),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(widget.songData['song']!, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF4E342E))),
                      const SizedBox(height: 16),

                      // 播放控制與進度條
                      Row(
                        children: [
                          Container(
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFAD5C35)),
                            child: IconButton(
                              iconSize: 40,
                              color: Colors.white,
                              //  動態更換圖示：播放中顯示暫停，暫停中顯示播放
                              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                              onPressed: _togglePlayPause, //  綁定點擊事件
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: progressValue, //  動態綁定計算後的真實進度
                                    minHeight: 12,
                                    backgroundColor: const Color(0xFFEADFC8),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFAD5C35)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    //  動態顯示當前播放時間與總時長
                                    Text(_formatDuration(_position), style: const TextStyle(color: Color(0xFF4E342E), fontWeight: FontWeight.bold)),
                                    Text(_formatDuration(_duration), style: const TextStyle(color: Color(0xFF4E342E), fontWeight: FontWeight.bold)),
                                  ],
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 24),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEADFC8), width: 2),
                        ),
                        child: const Text(
                          '點播播放後，這裡會出現目前唱\n到的歌詞',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 22, color: Color(0xFF4E342E), fontWeight: FontWeight.bold, height: 1.6),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCECD9),
                          borderRadius: BorderRadius.circular(12),
                          border: const Border(left: BorderSide(color: Color(0xFFAD5C35), width: 8)),
                        ),
                        child: const Text(
                          '這首歌你有聽過嗎？',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4E342E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}