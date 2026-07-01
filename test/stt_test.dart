import 'dart:io';
import 'package:flutter/material.dart';
import 'package:remini_care_ai_app/services/api_services.dart';
import 'package:remini_care_ai_app/services/audio_services/voice_assistant_services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

/// 🎙️ STT & VoiceAssistant 效能測試工具
/// 
/// 用法：
/// 1. 直接以 Flutter App 模式啟動此檔案：`flutter run test/stt_test.dart`
/// 2. 支援「實機麥克風錄音」與「上傳音檔」兩種測試模式。
/// 3. 用來評估在嘈雜環境下，不同 STT Provider 與 VAD 參數的表現。
void main() {
  runApp(const MaterialApp(
    home: SttTestScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class SttTestScreen extends StatefulWidget {
  const SttTestScreen({super.key});

  @override
  State<SttTestScreen> createState() => _SttTestScreenState();
}

class _SttTestScreenState extends State<SttTestScreen> {
  final VoiceAssistantManager _manager = VoiceAssistantManager();
  String _status = "等待操作...";
  String _resultText = "";
  bool _isRecording = false;
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    // 設定回調以觀察 VoiceAssistantManager 的行為
    _manager.onBackgroundTextRecognized = (text) {
      _addLog("🔍 背景辨識 (VAD): $text");
      setState(() => _resultText = text);
    };
    
    _manager.onSpeechCompleted = (paths) async {
      if (paths.isNotEmpty) {
        _addLog("✅ 錄音完成，正在進行最後辨識...");
        final transcript = await ApiServices().stt.transcribe(paths.first);
        _addLog("📝 最終結果: ${transcript ?? '(無內容)'}");
        setState(() {
          _resultText = transcript ?? "無內容";
          _status = "辨識完成";
          _isRecording = false;
        });
      } else {
        _addLog("❌ 錄音結束但無有效路徑");
        setState(() {
          _status = "錄音失敗";
          _isRecording = false;
        });
      }
    };
  }

  void _addLog(String msg) {
    debugPrint(msg);
    setState(() {
      _logs.insert(0, "${DateTime.now().toString().split('.').first.split(' ').last} - $msg");
    });
  }

  // --- 測試 A: 使用麥克風 (觸發 VAD 流程) ---
  Future<void> _startMicTest() async {
    setState(() {
      _isRecording = true;
      _status = "正在錄音 (VAD 模式)...";
      _resultText = "";
    });
    _addLog("🎙️ 啟動麥克風測試 (VAD)...");
    await _manager.startChatFlow();
  }

  Future<void> _stopMicTest() async {
    _addLog("⏹️ 手動停止錄音...");
    await _manager.forceEndChat();
  }

  // --- 測試 B: 上傳音檔測試 ---
  Future<void> _pickAndTestFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'm4a', 'mp3'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        _addLog("📁 已選擇檔案: ${result.files.single.name}");
        setState(() {
          _status = "正在分析檔案...";
          _resultText = "";
        });

        final stopwatch = Stopwatch()..start();
        final transcript = await ApiServices().stt.transcribe(path);
        stopwatch.stop();

        _addLog("📝 檔案辨識結果: ${transcript ?? '(空)'}");
        _addLog("⏱️ 辨識耗時: ${stopwatch.elapsedMilliseconds}ms");
        
        setState(() {
          _resultText = transcript ?? "無法辨識內容";
          _status = "分析完成";
        });
      }
    } catch (e) {
      _addLog("❌ 讀取檔案失敗: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("STT 雜音環境測試工具")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text("狀態: $_status", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("辨識文字:", style: TextStyle(color: Colors.grey.shade700)),
                    Text(_resultText, style: const TextStyle(fontSize: 20, color: Colors.blue)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isRecording ? _stopMicTest : _startMicTest,
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                    label: Text(_isRecording ? "停止錄音" : "開始錄製"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red : null,
                      foregroundColor: _isRecording ? Colors.white : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickAndTestFile,
                    icon: const Icon(Icons.file_upload),
                    label: const Text("選擇音檔"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text("測試日誌:", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) => Text(_logs[index], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _manager.forceRecalibrateVad();
                _addLog("🎛️ 已重置 VAD 校正參數");
              },
              child: const Text("重置 VAD 校正 (下次錄音重新取樣)"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }
}
