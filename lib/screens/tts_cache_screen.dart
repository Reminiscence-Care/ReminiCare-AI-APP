import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:remini_care_ai_app/services/api_services.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'package:remini_care_ai_app/services/audio_services/speech_services.dart';

class TtsCacheScreen extends StatefulWidget {
  const TtsCacheScreen({super.key});

  @override
  State<TtsCacheScreen> createState() => _TtsCacheScreenState();
}

class _TtsCacheScreenState extends State<TtsCacheScreen> {
  static String _spKeyTtsCache = ReminiCareConfig.ttsCacheName;

  Map<String, dynamic> _cacheMetadata = {};
  bool _isLoading = true;

  // 💡 音訊播放器與服務
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ITTSService _ttsService = ApiServices().tts;

  // 💡 狀態追蹤
  String? _playingKey; // 記錄目前正在播放的快取 Key
  final Set<String> _regeneratingKeys = {}; // 記錄正在重新生成的 Key

  @override
  void initState() {
    super.initState();
    // 監聽播放完成事件，自動還原播放按鈕狀態
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingKey = null);
    });
    _loadCache();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  /// 讀取 SharedPreferences 裡的快取目錄
  Future<void> _loadCache() async {
    setState(() { _isLoading = true; });
    try {
      final sp = await SharedPreferences.getInstance();
      final String? jsonStr = sp.getString(_spKeyTtsCache);

      if (jsonStr != null) {
        _cacheMetadata = Map<String, dynamic>.from(jsonDecode(jsonStr));

        // 過濾掉實體檔案已經不存在的紀錄 (避免髒資料)
        _cacheMetadata.removeWhere((key, data) {
          final file = File(data['path']);
          return !file.existsSync();
        });
      } else {
        _cacheMetadata = {};
      }
    } catch (e) {
      debugPrint("讀取快取失敗: $e");
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  /// 💡 播放/停止 指定的音檔
  Future<void> _togglePlay(String key, String path) async {
    if (_playingKey == key) {
      // 如果正在播放自己，就停止
      await _audioPlayer.stop();
      setState(() => _playingKey = null);
    } else {
      // 停止上一首，播放新的一首
      await _audioPlayer.stop();

      // 💡 關鍵修復：給予底層音訊引擎一點緩衝時間來清空 Buffer，防止兩首切換時產生爆音或雜訊！
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() => _playingKey = key);
      try {
        await _audioPlayer.play(DeviceFileSource(path));
      } catch (e) {
        debugPrint("播放失敗: $e");
        if (mounted) setState(() => _playingKey = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("播放失敗，檔案可能已損毀")),
        );
      }
    }
  }

  /// 💡 重新生成指定的 TTS 音檔
  Future<void> _regenerateItem(String key) async {
    final parts = key.split('::');
    if (parts.length < 2) return;

    final lang = parts[0];
    final text = parts.sublist(1).join("::");

    setState(() => _regeneratingKeys.add(key));

    try {
      // 確保播放器停止
      if (_playingKey == key) await _togglePlay(key, "");

      // 向 API 重新請求乾淨的音檔
      final audioBytes = await _ttsService.generateSpeech(text, lang);

      if (audioBytes != null && audioBytes.isNotEmpty) {
        // 刪除舊檔案
        final oldData = _cacheMetadata[key];
        if (oldData != null) {
          final oldFile = File(oldData['path']);
          if (oldFile.existsSync()) oldFile.deleteSync();
        }

        // 儲存新檔案
        final safeLang = lang == "台語" ? "tw" : "zh";
        final storageDir = await getApplicationDocumentsDirectory();
        final fileName = 'tts_${safeLang}_${DateTime.now().millisecondsSinceEpoch}.wav';
        final newFile = File('${storageDir.path}/$fileName');
        await newFile.writeAsBytes(audioBytes, flush: true);

        // 更新快取元資料
        _cacheMetadata[key] = {
          "path": newFile.path,
          "lastUsed": DateTime.now().millisecondsSinceEpoch,
          "size": audioBytes.length,
        };

        // 寫入 SharedPreferences
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_spKeyTtsCache, jsonEncode(_cacheMetadata));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ 重新生成成功！"), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception("API 回傳空資料");
      }
    } catch (e) {
      debugPrint("重新生成失敗: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ 重新生成失敗，請檢查網路"), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _regeneratingKeys.remove(key));
    }
  }

  /// 刪除單筆語音快取
  Future<void> _deleteItem(String key) async {
    // 若正在播放這首歌，先停止
    if (_playingKey == key) await _togglePlay(key, "");

    final data = _cacheMetadata[key];
    if (data == null) return;

    try {
      final file = File(data['path']);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      debugPrint("刪除實體檔案失敗: $e");
    }

    setState(() {
      _cacheMetadata.remove(key);
    });

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_spKeyTtsCache, jsonEncode(_cacheMetadata));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🗑️ 已刪除該筆語音快取"), duration: Duration(seconds: 1)),
      );
    }
  }

  /// 一鍵清除所有快取
  Future<void> _clearAll() async {
    if (_cacheMetadata.isEmpty) return;

    bool confirm = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text("全部清除", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text("確定要清除所有已下載的語音檔嗎？\n清除後若需再次播放將重新消耗網路流量。"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("取消", style: TextStyle(color: Colors.grey, fontSize: 16))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("確定清除", style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        )
    ) ?? false;

    if (!confirm) return;

    await _audioPlayer.stop();
    setState(() {
      _isLoading = true;
      _playingKey = null;
    });

    // 刪除所有實體檔案
    for (var data in _cacheMetadata.values) {
      try {
        final file = File(data['path']);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }

    _cacheMetadata.clear();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_spKeyTtsCache);

    if (mounted) {
      setState(() { _isLoading = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🧹 所有語音快取已清除完畢！"), backgroundColor: Colors.green),
      );
    }
  }

  /// 計算總容量
  String _getTotalSize() {
    int totalBytes = 0;
    for (var data in _cacheMetadata.values) {
      totalBytes += (data['size'] as int? ?? 0);
    }
    return _formatSize(totalBytes);
  }

  /// 格式化檔案大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('語音快取管理', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        actions: [
          if (_cacheMetadata.isNotEmpty)
            TextButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              label: const Text("全部清除", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _cacheMetadata.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sd_card_alert_rounded, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text("目前沒有任何語音快取", style: TextStyle(fontSize: 18, color: Colors.grey[500])),
          ],
        ),
      )
          : Column(
        children: [
          // 頂部統計面板
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF9E6),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("共 ${_cacheMetadata.length} 筆語音", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87)),
                Text("總佔用: ${_getTotalSize()}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
          ),

          // 快取列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _cacheMetadata.length,
              itemBuilder: (context, index) {
                final key = _cacheMetadata.keys.elementAt(index);
                final data = _cacheMetadata[key];

                // Key 的格式為 "語言::文本"，拆解出來顯示
                final parts = key.split('::');
                final lang = parts.isNotEmpty ? parts[0] : "未知";
                final text = parts.length > 1 ? parts.sublist(1).join("::") : "無內容";

                final filePath = data['path'] as String;
                final sizeStr = _formatSize(data['size'] ?? 0);

                final lastUsedMs = data['lastUsed'] as int? ?? 0;
                final date = DateTime.fromMillisecondsSinceEpoch(lastUsedMs);
                final dateStr = "${date.year}/${date.month.toString().padLeft(2,'0')}/${date.day.toString().padLeft(2,'0')} ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}";

                final bool isPlaying = _playingKey == key;
                final bool isRegenerating = _regeneratingKeys.contains(key);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    // 正在播放時，給予卡片高亮邊框
                    side: BorderSide(color: isPlaying ? Colors.orange : Colors.transparent, width: 2),
                  ),
                  elevation: isPlaying ? 4 : 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center, // 改為置中對齊
                      children: [
                        // 左側：語言標籤
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: lang == "台語" ? Colors.green[50] : Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: lang == "台語" ? Colors.green[200]! : Colors.blue[200]!),
                          ),
                          child: Text(
                            lang,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: lang == "台語" ? Colors.green[700] : Colors.blue[700]
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // 中間：語音文字內容與詳細資訊
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                text,
                                style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.4),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.sd_storage_rounded, size: 14, color: Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Text(sizeStr, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                  const SizedBox(width: 16),
                                  Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Text(dateStr, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 右側：操作按鈕區 (試聽、重新生成、刪除)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 試聽 / 停止 按鈕
                            IconButton(
                              icon: Icon(
                                  isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                                  color: isPlaying ? Colors.redAccent : Colors.orange,
                                  size: 32
                              ),
                              onPressed: isRegenerating ? null : () => _togglePlay(key, filePath),
                              tooltip: isPlaying ? "停止播放" : "試聽",
                            ),

                            // 重新生成 按鈕 / Loading 圈圈
                            if (isRegenerating)
                              const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.orange)
                                ),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: Colors.blueGrey, size: 28),
                                onPressed: () => _regenerateItem(key),
                                tooltip: "重新生成並覆蓋",
                              ),

                            // 刪除 按鈕
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 28),
                              onPressed: isRegenerating ? null : () => _deleteItem(key),
                              tooltip: "刪除此快取",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}