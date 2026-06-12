import 'dart:async';
import 'dart:io';
import 'dart:typed_data'; // 💡 新增：用於二進位 WAV 標頭重新計算與位元組操作
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart'; // 💡 核心：全權接管高品質滾動錄音與指令拼接
import 'package:path_provider/path_provider.dart';

// 引入您的純 Dart 服務層
import '../../services/reminicare_ai_services.dart';

// 匯入您自定義的子組件
import 'widgets/language_selector.dart';
import 'widgets/question_area.dart';
import 'widgets/chat_views.dart';
import 'widgets/keywords_view.dart';
import 'widgets/generating_view.dart';
import 'widgets/evaluation_view.dart';

enum ChatStatus {
  prepare, chatting, completed, keywords, generating, evaluation,
  dislikePrepare, dislikeChatting, dislikeCompleted, dislikeKeywords, dislikeGenerating, dislikeEvaluation,
  likePrepare, likeChatting, likeCompleted, likeKeywords, likeGenerating,
}

/// 用於動態解析 WAV 音訊區塊的內部資料結構
class WavInfo {
  final List<int> header;          // 包含 data 區塊大小標記之前的完整標頭
  final List<int> pcm;             // 純淨的 PCM 音訊數據
  final int dataChunkSizeOffset;   // data 區塊長度標記在檔案中的精確位元組偏移量

  WavInfo({
    required this.header,
    required this.pcm,
    required this.dataChunkSizeOffset,
  });
}

class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key});

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  // 實例化純 Dart AI 客戶端服務
  final NvidiaLlmService _llmService = NvidiaLlmService();
  final SiliconFlowImageService _imageService = SiliconFlowImageService();

  // 💡 關鍵重構：整併為統一的成大語音 ASR + TTS 服務客戶端！
  final NckuSpeechService _nckuSpeechService = NckuSpeechService();

  // 狀態變數與播放器
  String _aiGeneratedText = "";
  String _selectedLanguage = "台語";
  ChatStatus _chatStatus = ChatStatus.prepare;

  bool _isLoading = true;
  bool _isExtractingKeywords = false;

  int _recordSeconds = 0;
  Timer? _recordTimer;

  final int _maxKeywordLength = 5;
  List<String> _originalKeywords = [];
  List<String> _newKeywords = [];

  // 保留對話紀錄以維持上下文
  final List<Map<String, String>> _chatHistory = [];
  String _currentImageUrl = "";

  final AudioPlayer _audioPlayer = AudioPlayer();

  // 智慧 VAD 雲端語音助理與滾動累積變數
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  bool _isRollingWakeWord = false; // 是否正在進行背景喚醒監聽
  bool _isRollingChatRecord = false; // 是否正在對話語音累積錄音中

  // 💡 關鍵變數：永久記錄每一段生成的回憶 WAV 錄音暫存路徑
  final List<String> _recordedChunkPaths = [];

  @override
  void initState() {
    super.initState();
    _initializeConfigurationAndLoad();
  }

  /// 初始化金鑰並獲取初始問題
  Future<void> _initializeConfigurationAndLoad() async {
    await ReminiCareConfig.loadConfig(); // 載入 SharedPreferences 優先的金鑰
    if (!mounted) return;
    _fetchInitialQuestion();
    _startBackgroundWakeWordCycle(); // 啟動：背景自動喚醒監聽
  }

  // ==========================================
  // 計時器管理與狀態重置
  // ==========================================
  void _startTimer() {
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() { _recordSeconds++; });
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  void _resetAllStates() {
    if (!mounted) return;
    setState(() {
      _chatStatus = ChatStatus.prepare;
      _recordSeconds = 0;
      _currentImageUrl = "";
      _originalKeywords.clear();
      _newKeywords.clear();
      _chatHistory.clear();
      _aiGeneratedText = "";
      _isLoading = true;
      _stopTimer();
    });
    _stopActiveAudioOperations();
    _fetchInitialQuestion();
    _startBackgroundWakeWordCycle(); // 重新回到背景監聽
  }

  /// 安全清理所有語音/錄音資源，並徹底移除暫存切片
  void _stopActiveAudioOperations() {
    _isRollingWakeWord = false;
    _isRollingChatRecord = false;
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _audioRecorder.stop();
    _clearTemporaryChunks(); // 清除暫存檔
  }

  /// 清理本輪對話產生的所有臨時語音分段
  void _clearTemporaryChunks() {
    for (var path in _recordedChunkPaths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _recordedChunkPaths.clear();
  }

  /// 💡 判斷當前狀態是否為「需要語音助理/監聽」的活動狀態
  bool _isVoiceActiveStatus(ChatStatus status) {
    return status == ChatStatus.prepare ||
        status == ChatStatus.chatting ||
        status == ChatStatus.completed ||
        status == ChatStatus.dislikePrepare ||
        status == ChatStatus.dislikeChatting ||
        status == ChatStatus.dislikeCompleted ||
        status == ChatStatus.likePrepare ||
        status == ChatStatus.likeChatting ||
        status == ChatStatus.likeCompleted;
  }

  @override
  void dispose() {
    _stopActiveAudioOperations();
    _stopTimer();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ==========================================
  // 🎙️ 核心 A：背景一鍵「喚醒詞」輪詢檢測 (Rolling Wake-word)
  // ==========================================
  Future<void> _startBackgroundWakeWordCycle() async {
    if (!_isVoiceActiveStatus(_chatStatus)) return; // 非語音狀態下，不開啟背景輪詢
    if (_isRollingWakeWord) return;
    _isRollingWakeWord = true;
    _runSingleWakeWordCycle();
  }

  Future<void> _runSingleWakeWordCycle() async {
    // 當狀態移轉到非語音互動頁面時，自動中斷背景監聽循環
    if (!_isRollingWakeWord || !mounted || !_isVoiceActiveStatus(_chatStatus)) {
      _isRollingWakeWord = false;
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final String path = '${directory.path}/reminicare_wake_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );

        // 每隔 3.5 秒錄製一次
        await Future.delayed(const Duration(milliseconds: 3500));
        if (!_isRollingWakeWord || !mounted || !_isVoiceActiveStatus(_chatStatus)) {
          await _audioRecorder.stop();
          return;
        }

        final String? savedPath = await _audioRecorder.stop();
        if (savedPath != null) {
          _transcribeAndCheckWakeWord(savedPath);
        }
      }
    } catch (e) {
      debugPrint("[喚醒器] 輪詢異常: $e");
      if (_isRollingWakeWord && mounted && _isVoiceActiveStatus(_chatStatus)) {
        Future.delayed(const Duration(seconds: 2), _runSingleWakeWordCycle);
      }
    }
  }

  /// 利用成大 ASR 進行高精準喚醒字與流程指令過濾
  Future<void> _transcribeAndCheckWakeWord(String audioPath) async {
    try {
      // 💡 修正：呼叫成大自研 ASR 客戶端進行辨識
      final String? transcript = await _nckuSpeechService.transcribe(audioPath);

      // 隨手刪除暫存檔
      try { File(audioPath).deleteSync(); } catch (_) {}

      if (transcript != null) {
        final String cleanText = transcript.replaceAll(" ", "");
        debugPrint("[喚醒詞檢測] 聽到的原始內容: '$cleanText'，目前狀態為: $_chatStatus");

        // 1. 如果處於準備/修改準備/延伸準備階段，檢測「開始錄音 / 開始聊天」喚醒詞
        if (_chatStatus == ChatStatus.prepare ||
            _chatStatus == ChatStatus.dislikePrepare ||
            _chatStatus == ChatStatus.likePrepare) {
          if (cleanText.contains("開始錄") ||
              cleanText.contains("開始聊") ||
              cleanText.contains("開始") ||
              cleanText.contains("來聊") ||
              cleanText.contains("錄音")) {
            debugPrint("🎉 [喚醒成功] 偵測到開始口令，自動進入對話畫面！");
            _isRollingWakeWord = false;
            _triggerStartChatFlow();
            return;
          }
        }
        // 2. 如果處於完成階段，檢測「重新錄音/重新聊天/結束聊天」等熱詞
        else if (_chatStatus == ChatStatus.completed ||
            _chatStatus == ChatStatus.dislikeCompleted ||
            _chatStatus == ChatStatus.likeCompleted) {
          if (cleanText.contains("重新錄") ||
              cleanText.contains("重新聊") ||
              cleanText.contains("重新") ||
              cleanText.contains("重來") ||
              cleanText.contains("重錄") ||
              cleanText.contains("再來")) {
            debugPrint("🎉 [喚醒成功] 偵測到重新開始對話口令，自動重啟！");
            _isRollingWakeWord = false;
            _triggerStartChatFlow();
            return;
          } else if (cleanText.contains("結束錄") ||
              cleanText.contains("結束聊") ||
              cleanText.contains("結束") ||
              cleanText.contains("完成")) {
            debugPrint("🎉 [喚醒成功] 偵測到結束聊天口令，自動切換至關鍵字與生圖確認畫面！");
            _isRollingWakeWord = false;
            if (mounted) {
              setState(() {
                if (_chatStatus == ChatStatus.dislikeCompleted) {
                  _chatStatus = ChatStatus.dislikeKeywords;
                } else if (_chatStatus == ChatStatus.likeCompleted) {
                  _chatStatus = ChatStatus.likeKeywords;
                } else {
                  _chatStatus = ChatStatus.keywords;
                }
              });
              // 進入非語音關鍵字確認頁，徹底暫停錄製
              _stopActiveAudioOperations();
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("[喚醒器] 翻譯出錯: $e");
    }

    if (_isRollingWakeWord && mounted && _isVoiceActiveStatus(_chatStatus)) {
      _runSingleWakeWordCycle();
    } else {
      _isRollingWakeWord = false;
    }
  }

  // ==========================================
  // 🎙️ 核心 B：滾動對話切片累積錄音循環 & WAV 二進位無損合成器
  // ==========================================

  /// 啟動：滾動錄製對話區段，暫存 WAV 切片路徑，直到聽到「結束錄音」
  Future<void> _runSingleChatRecordCycle() async {
    if (!_isRollingChatRecord || !mounted) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        // 產生獨立檔名的分段音檔
        final String path = '${directory.path}/reminicare_chat_chunk_${DateTime.now().millisecondsSinceEpoch}.wav';

        // 將此段音軌路徑加入我們的待拼接清單中
        _recordedChunkPaths.add(path);

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: path,
        );

        // 每隔 5 秒無痛錄製一個對話切片
        await Future.delayed(const Duration(milliseconds: 5000));
        if (!_isRollingChatRecord || !mounted) {
          await _audioRecorder.stop();
          return;
        }

        final String? savedPath = await _audioRecorder.stop();
        if (savedPath != null) {
          _processChatChunk(savedPath); // 背景默默解析此段對話，判斷是否含有結束錄音指令
        }
      }
    } catch (e) {
      debugPrint("[對話錄音] 滾動循環異常: $e");
      if (_isRollingChatRecord && mounted) {
        Future.delayed(const Duration(seconds: 2), _runSingleChatRecordCycle);
      }
    }
  }

  /// 背景翻譯段落並進行指令過濾，達到「聽到結束錄音才拼接前面音軌」的效果
  Future<void> _processChatChunk(String audioPath) async {
    try {
      // 💡 修正：使用成大 ASR 客戶端解析這段音軌，判斷有沒有講「結束錄音」
      final String? transcript = await _nckuSpeechService.transcribe(audioPath);

      if (transcript != null && transcript.trim().isNotEmpty) {
        final String cleanText = transcript.replaceAll(" ", "");
        debugPrint("[指令監測中] 聽到的段落: '$cleanText'");

        // 關鍵判定：當聽到的段落中「包含結束錄音」時，開啟無損二進位拼接！
        if (_matchesEndCommand(cleanText)) {
          debugPrint("🎉 [結束指令成功] 偵測到結束錄音口令，開始進行 WAV 二進位拼接！");
          _isRollingChatRecord = false; // 終止滾動錄音

          // 1. 關鍵：剔除最後一個包含「結束錄音」指令的雜音分段
          _recordedChunkPaths.remove(audioPath);
          try { File(audioPath).deleteSync(); } catch (_) {}

          // 2. 核心黑科技：將前面所有乾淨的 WAV 檔案進行二進位底層拼接！
          final String? mergedWavPath = await _concatenateWavFiles(_recordedChunkPaths);

          // 3. 一次性送交成大 ASR 進行 100% 完美的長篇逐字稿辨識！
          _submitMergedAudioToAI(mergedWavPath);
          return;
        }
      }
    } catch (e) {
      debugPrint("[對話錄音] 翻譯段落出錯: $e");
    }

    // 若仍在錄音狀態，則繼續下一個 5 秒循環錄製
    if (_isRollingChatRecord && mounted && _isVoiceActiveStatus(_chatStatus)) {
      _runSingleChatRecordCycle();
    } else {
      _isRollingChatRecord = false;
    }
  }

  /// WAV 格式動態二進位探測器 (解決微軟/WASAPI 標頭非 44 bytes 的 PlatformException 與格式損毀)
  WavInfo? _parseWav(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // 1. 驗證 RIFF 與 WAVE 簽名標記
    final String riff = String.fromCharCodes(bytes.sublist(0, 4));
    final String wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != "RIFF" || wave != "WAVE") return null;

    int offset = 12;
    int dataChunkSizeOffset = -1;

    // 2. 滾動解析二進位 Chunk，精確探測 fmt 格式與 data 音訊區塊
    while (offset + 8 <= bytes.length) {
      final String chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final int chunkSize = ByteData.sublistView(bytes, offset + 4, offset + 8).getUint32(0, Endian.little);

      if (chunkId == "data") {
        dataChunkSizeOffset = offset + 4;

        // 標頭包含 data 區塊名稱與長度標記在內的所有前置資訊
        final header = bytes.sublist(0, offset + 8);
        final pcm = bytes.sublist(offset + 8);

        return WavInfo(
          header: header.toList(),
          pcm: pcm.toList(),
          dataChunkSizeOffset: dataChunkSizeOffset,
        );
      }

      // 跳轉至下一個 Chunk (Chunk 標籤與長度佔用 8 bytes)
      offset += 8 + chunkSize;

      // WAV 標準：奇數長度 Chunk 會在尾部補 1 byte 對齊
      if (chunkSize % 2 != 0) {
        offset += 1;
      }
    }
    return null;
  }

  /// WAV 二進位無損拼接演算法 (動態探測，徹底解決損毀問題)
  Future<String?> _concatenateWavFiles(List<String> paths) async {
    if (paths.isEmpty) return null;
    debugPrint("[WAV 拼接器] 正在無損動態解析並拼接 ${paths.length} 個 WAV 音訊段落...");

    try {
      final directory = await getTemporaryDirectory();
      final String outputPath = '${directory.path}/reminicare_merged_final_${DateTime.now().millisecondsSinceEpoch}.wav';
      final File outputFile = File(outputPath);

      List<int> rawPcmBytes = [];
      List<int>? firstWavHeader;
      int dataChunkSizeOffset = -1;

      for (int i = 0; i < paths.length; i++) {
        final file = File(paths[i]);
        if (!file.existsSync()) continue;

        final bytes = await file.readAsBytes();

        // 💡 呼叫格式解析器探測此音軌
        final wavInfo = _parseWav(bytes);
        if (wavInfo == null) {
          debugPrint("⚠️ 檔案 ${paths[i]} 解析為無效的 WAV，跳過。");
          continue;
        }

        if (i == 0 || firstWavHeader == null) {
          // 💡 完整保留第一個音訊檔的客製化 format 標頭結構，絕不強行斬斷！
          firstWavHeader = wavInfo.header;
          dataChunkSizeOffset = wavInfo.dataChunkSizeOffset;
        }

        // 💡 動態提取 PCM 資料並合流
        rawPcmBytes.addAll(wavInfo.pcm);
      }

      if (firstWavHeader == null || dataChunkSizeOffset == -1) {
        debugPrint("❌ 沒有找到任何有效的 WAV 標頭");
        return null;
      }

      // 💡 重新計算總體大小，並動態覆載寫回探測到的偏移位址中
      final int totalDataSize = rawPcmBytes.length;
      final int totalFileSize = (firstWavHeader.length - 8) + totalDataSize;

      final ByteData sizeBuffer = ByteData(4);

      // 1. 更新 RIFF ChunkSize (標頭的 4~7 位元組)
      sizeBuffer.setUint32(0, totalFileSize, Endian.little);
      firstWavHeader[4] = sizeBuffer.getUint8(0);
      firstWavHeader[5] = sizeBuffer.getUint8(1);
      firstWavHeader[6] = sizeBuffer.getUint8(2);
      firstWavHeader[7] = sizeBuffer.getUint8(3);

      // 2. 更新 data Subchunk2Size (在我們動態探測到的 dataChunkSizeOffset)
      sizeBuffer.setUint32(0, totalDataSize, Endian.little);
      firstWavHeader[dataChunkSizeOffset] = sizeBuffer.getUint8(0);
      firstWavHeader[dataChunkSizeOffset + 1] = sizeBuffer.getUint8(1);
      firstWavHeader[dataChunkSizeOffset + 2] = sizeBuffer.getUint8(2);
      firstWavHeader[dataChunkSizeOffset + 3] = sizeBuffer.getUint8(3);

      // 拼接新標頭與拼接後的 PCM 流
      final List<int> consolidatedWavBytes = [...firstWavHeader, ...rawPcmBytes];
      await outputFile.writeAsBytes(consolidatedWavBytes);

      debugPrint("✅ [WAV 拼接成功] 動態合成音檔已儲存於: $outputPath (總PCM位元組: $totalDataSize)");
      return outputPath;

    } catch (e) {
      debugPrint("[WAV 拼接失敗] 發生異常: $e");
      return null;
    }
  }

  /// 💡 彙整整段對話，一次性提交 AI 陪伴與生圖
  void _submitMergedAudioToAI(String? mergedWavPath) {
    _stopTimer();
    _isRollingChatRecord = false;

    final currentStatus = _chatStatus;
    if (!mounted) return;
    setState(() {
      _chatStatus = currentStatus == ChatStatus.dislikeChatting
          ? ChatStatus.dislikeCompleted
          : currentStatus == ChatStatus.likeChatting
          ? ChatStatus.likeCompleted
          : ChatStatus.completed;
    });

    if (mergedWavPath != null) {
      // 💡 一次性送交成大 ASR 高精度解析整段長篇故事，解析完後再傳給 NVIDIA LLM！
      _processAudioAndChat(audioPath: mergedWavPath);
    } else {
      // 防呆：若無音軌，使用預設模擬文字
      _processAudioAndChat();
    }

    // 清理本次對話累積的所有 5 秒切片暫存，避免佔用手機內存
    _clearTemporaryChunks();

    // 重新排程背景喚醒，等待使用者講「重新錄音/聊天」或「結束聊天」
    _startBackgroundWakeWordCycle();
  }

  // ==========================================
  // 🚀 雙模智慧對話流程控制器
  // ==========================================

  /// 一、開始聊天（關閉喚醒輪詢，開啟滾動切片累積錄製）
  void _triggerStartChatFlow() async {
    _stopActiveAudioOperations(); // 徹底釋放錄音資源

    setState(() {
      if (_chatStatus == ChatStatus.dislikePrepare || _chatStatus == ChatStatus.dislikeCompleted) {
        _chatStatus = ChatStatus.dislikeChatting;
      } else if (_chatStatus == ChatStatus.likePrepare || _chatStatus == ChatStatus.likeCompleted) {
        _chatStatus = ChatStatus.likeChatting;
      } else {
        _chatStatus = ChatStatus.chatting;
      }
      _recordSeconds = 0;
      _startTimer();
    });

    _recordedChunkPaths.clear(); // 清空先前累積的音軌暫存清單
    _isRollingChatRecord = true;
    _runSingleChatRecordCycle(); // 啟動：滾動錄製對話循環
  }

  /// 二、手動按鈕結束聊天（關閉 VAD 與滾動，彙整現有全部段落並發送）
  Future<void> _handleEndChat() async {
    _stopTimer();
    _isRollingChatRecord = false; // 終止滾動循環

    final currentStatus = _chatStatus;
    if (!mounted) return;
    setState(() {
      _chatStatus = currentStatus == ChatStatus.dislikeChatting
          ? ChatStatus.dislikeCompleted
          : currentStatus == ChatStatus.likeChatting
          ? ChatStatus.likeCompleted
          : ChatStatus.completed;
    });

    try {
      final String? path = await _audioRecorder.stop();
      if (path != null) {
        // 手動按鈕不需要拋棄最後一個，全部音軌包含最後一小段一起進行拼接！
        final String? mergedWavPath = await _concatenateWavFiles(_recordedChunkPaths);
        _submitMergedAudioToAI(mergedWavPath);
      } else {
        _submitMergedAudioToAI(null);
      }
    } catch (e) {
      debugPrint("[手動結束] 處理最後一段失敗: $e");
      _submitMergedAudioToAI(null);
    }
  }

  // 💡 模糊指令比對
  bool _matchesStartCommand(String text) {
    return text.contains("開始錄") || text.contains("開始聊") || text.contains("開始") || text.contains("來聊");
  }

  bool _matchesEndCommand(String text) {
    return text.contains("結束錄") || text.contains("結束聊") || text.contains("結束錄影") || text.contains("結束錄像") || text.contains("結束") || text.contains("完成");
  }

  // ==========================================
  // 🚀 純 Dart 業務呼叫邏輯 (UI 串接)
  // ==========================================

  Future<void> _playVoice(String text, String language) async {
    if (text.isEmpty) return;
    try {
      if (kIsWeb) return;
      // 💡 修正：調用統一成大自研語音合成 (TTS)
      final Uint8List? audioBytes = await _nckuSpeechService.generateSpeech(text, language);
      if (audioBytes != null) {
        if (!mounted) return;
        await _audioPlayer.play(BytesSource(audioBytes));
      }
    } catch (e) {
      debugPrint("[播放錯誤]: $e");
    }
  }

  void _playCurrentContextVoice(String lang) {
    if (!mounted) return;
    setState(() => _selectedLanguage = lang);
    String textToPlay = _aiGeneratedText;

    if (_chatStatus == ChatStatus.evaluation || _chatStatus == ChatStatus.dislikeEvaluation) {
      textToPlay = "這張圖符合您的回憶嗎？";
    } else if (_chatStatus == ChatStatus.dislikePrepare || _chatStatus == ChatStatus.dislikeChatting || _chatStatus == ChatStatus.dislikeCompleted) {
      textToPlay = "哪裡不對？";
    } else if (_chatStatus == ChatStatus.likePrepare || _chatStatus == ChatStatus.likeChatting || _chatStatus == ChatStatus.likeCompleted) {
      textToPlay = "這張圖片讓您想到什麼？";
    }

    _playVoice(textToPlay, lang);
  }

  Future<void> _fetchInitialQuestion() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });
    try {
      final String question = await _llmService.generateInitialQuestion();
      if (!mounted) return;
      setState(() {
        _aiGeneratedText = question;
      });
    } catch (e) {
      debugPrint("初始問題獲取失敗: $e");
      if (!mounted) return;
      setState(() {
        _aiGeneratedText = "哈囉！小時候家裡最常吃什麼呢？";
      });
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  /// 處理對話回覆與關鍵字擷取 (100% 採用成大 ASR 客戶端進行辨識)
  Future<void> _processAudioAndChat({String? audioPath, String? manualText}) async {
    if (!mounted) return;
    setState(() { _isExtractingKeywords = true; });
    String userMessage = "";

    try {
      if (audioPath != null && !kIsWeb) {
        debugPrint("[高品質語音] 正在送交成大 ASR 服務解析...");
        // 💡 修正：呼叫成大自研 ASR 辨識合併後的長篇語音檔
        String? transcript = await _nckuSpeechService.transcribe(audioPath);

        // 解析完後隨手刪除
        try { File(audioPath).deleteSync(); } catch (_) {}

        if (transcript != null && transcript.trim().isNotEmpty) {
          userMessage = transcript;
          debugPrint("[NCKU ASR] 精準解析文字: $userMessage");
        } else {
          throw Exception("語音辨識無有效回傳");
        }
      } else if (manualText != null && manualText.isNotEmpty) {
        userMessage = manualText;
        debugPrint("[彙整文字直接送出] 最終內容: $userMessage");
      } else {
        if (_chatStatus == ChatStatus.completed) {
          userMessage = "小時候我阿母都在灶腳煮那個蕃薯飯，配滷豆乾啦。";
        } else if (_chatStatus == ChatStatus.dislikeCompleted) {
          userMessage = "這張不像啦，桌上只有一鍋蕃薯粥配醃蘿蔔而已。";
        } else {
          userMessage = "兄弟姊妹都會去山上摸魚。";
        }
      }

      final String reply = await _llmService.generateChatReply(userMessage, _chatHistory);
      final List<String> extracted = await _llmService.extractKeywords(userMessage);

      if (!mounted) return;
      setState(() {
        _aiGeneratedText = reply;
        if (_chatStatus == ChatStatus.completed || _chatStatus == ChatStatus.keywords) {
          _originalKeywords = extracted;
        } else {
          _newKeywords = extracted;
        }
      });

      _chatHistory.add({"role": "user", "content": userMessage});
      _chatHistory.add({"role": "assistant", "content": reply});

    } catch (e) {
      debugPrint("陪伴與智慧分析流發生錯誤: $e");
      if (!mounted) return;
      setState(() {
        _aiGeneratedText = "阿公阿嬤拍謝，我剛才不小心恍神了，可以再跟我說一次嗎？";
      });
    } finally {
      if (mounted) {
        setState(() { _isExtractingKeywords = false; });
      }
    }
  }

  Future<void> _triggerImageGeneration() async {
    if (!mounted) return;
    setState(() { _chatStatus = ChatStatus.generating; });
    try {
      String prompt = _originalKeywords.join("、");
      if (prompt.isEmpty) prompt = "懷舊場景";

      final String? imageUrl = await _imageService.generateNostalgicImage(
        scene: "在傳統灶腳烹飪, 包含關鍵元素: $prompt",
        era: "1980s",
        location: "Taiwan",
      );

      if (!mounted) return;
      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.evaluation;
        });
      } else {
        throw Exception("生圖出錯");
      }
    } catch (e) {
      debugPrint("生圖流程出錯: $e");
      if (!mounted) return;
      setState(() { _chatStatus = ChatStatus.keywords; });
    }
  }

  Future<void> _triggerModifiedImageGeneration() async {
    if (!mounted) return;
    setState(() { _chatStatus = ChatStatus.dislikeGenerating; });
    try {
      String combinedPrompt = _newKeywords.join("、");
      if (combinedPrompt.isEmpty) combinedPrompt = "修改後的食物與場景";

      final String? imageUrl = await _imageService.editImage(
        imagePath: _currentImageUrl,
        editInstruction: "將桌上的食物與細節修改或新增為: $combinedPrompt",
      );

      if (!mounted) return;
      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.dislikeEvaluation;
        });
      } else {
        throw Exception("改圖出錯");
      }
    } catch (e) {
      debugPrint("改圖流程出錯: $e");
      if (!mounted) return;
      setState(() { _chatStatus = ChatStatus.dislikeKeywords; });
    }
  }

  Future<void> _triggerLikeExtendedImageGeneration() async {
    if (!mounted) return;
    setState(() { _chatStatus = ChatStatus.likeGenerating; });
    try {
      String combinedPrompt = [..._originalKeywords, ..._newKeywords].join("、");

      final String? imageUrl = await _imageService.generateNostalgicImage(
        scene: "一個溫馨的台灣家庭回憶場景, 包含關鍵元素: $combinedPrompt",
        era: "1980s",
        location: "Taiwan",
      );

      if (!mounted) return;
      if (imageUrl != null) {
        setState(() {
          _currentImageUrl = imageUrl;
          _chatStatus = ChatStatus.evaluation;
        });
      } else {
        throw Exception("延伸話題生圖出錯");
      }
    } catch (e) {
      debugPrint("延伸生圖流程出錯: $e");
      if (!mounted) return;
      setState(() { _chatStatus = ChatStatus.likeKeywords; });
    }
  }

  // ==========================================
  // 主畫面排版
  // ==========================================
  @override
  Widget build(BuildContext context) {
    String appBarTitle = "";
    switch (_chatStatus) {
      case ChatStatus.prepare: appBarTitle = "準備聊天"; break;
      case ChatStatus.chatting:
      case ChatStatus.completed: appBarTitle = "點開始聊"; break;
      case ChatStatus.keywords: appBarTitle = "抓取關鍵詞"; break;
      case ChatStatus.generating:
      case ChatStatus.dislikeGenerating:
      case ChatStatus.likeGenerating: appBarTitle = "Ai 生圖中"; break;
      case ChatStatus.evaluation:
      case ChatStatus.dislikeEvaluation: appBarTitle = "問像不像"; break;
      case ChatStatus.dislikePrepare:
      case ChatStatus.dislikeChatting:
      case ChatStatus.dislikeCompleted:
      case ChatStatus.dislikeKeywords: appBarTitle = "不像，繼續聊天"; break;
      case ChatStatus.likePrepare:
      case ChatStatus.likeChatting:
      case ChatStatus.likeCompleted:
      case ChatStatus.likeKeywords: appBarTitle = "如果像，就 AI延伸話題"; break;
    }

    final bool showImageOnTop = _chatStatus == ChatStatus.evaluation ||
        _chatStatus == ChatStatus.dislikePrepare || _chatStatus == ChatStatus.dislikeChatting ||
        _chatStatus == ChatStatus.dislikeCompleted || _chatStatus == ChatStatus.dislikeKeywords ||
        _chatStatus == ChatStatus.dislikeEvaluation || _chatStatus == ChatStatus.likePrepare ||
        _chatStatus == ChatStatus.likeChatting || _chatStatus == ChatStatus.likeCompleted ||
        _chatStatus == ChatStatus.likeKeywords;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          appBarTitle,
          style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Spacer(flex: 1),

                          if (showImageOnTop) ...[
                            _buildEvaluationImage(),
                            const Spacer(flex: 1),
                          ],

                          if (_chatStatus != ChatStatus.evaluation && _chatStatus != ChatStatus.dislikePrepare &&
                              _chatStatus != ChatStatus.dislikeChatting && _chatStatus != ChatStatus.likePrepare &&
                              _chatStatus != ChatStatus.likeChatting && _chatStatus != ChatStatus.dislikeEvaluation) ...[
                            LanguageSelector(
                              selectedLanguage: _selectedLanguage,
                              onLanguageSelected: _playCurrentContextVoice,
                            ),
                            const Spacer(flex: 1),
                          ],

                          if (_chatStatus != ChatStatus.evaluation && _chatStatus != ChatStatus.dislikeEvaluation &&
                              _chatStatus != ChatStatus.dislikePrepare && _chatStatus != ChatStatus.dislikeChatting &&
                              _chatStatus != ChatStatus.likePrepare && _chatStatus != ChatStatus.likeChatting) ...[
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _isLoading
                                  ? const QuestionLoadingIndicator()
                                  : QuestionArea(questionText: _aiGeneratedText),
                            ),
                            const Spacer(flex: 1),
                          ],

                          if (_chatStatus == ChatStatus.keywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _originalKeywords,
                              newKeywords: const [],
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ] else if (_chatStatus == ChatStatus.dislikeKeywords || _chatStatus == ChatStatus.likeKeywords) ...[
                            KeywordsView(
                              isLoading: _isExtractingKeywords,
                              originalKeywords: _originalKeywords,
                              newKeywords: _newKeywords,
                              maxLength: _maxKeywordLength,
                            ),
                            const Spacer(flex: 1),
                          ],

                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _buildControlSection(),
                          ),

                          // 💡 僅在語音互動為活動狀態下（_isVoiceActiveStatus == true）才將語音指示器加入 Widget 樹中
                          if (_isVoiceActiveStatus(_chatStatus))
                            _buildVoiceAssistantIndicator(),

                          const Spacer(flex: 2),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
        ),
      ),
    );
  }

  /// 💡 底部智慧型 VAD 狀態提示條 (支援多狀態指令引導)
  Widget _buildVoiceAssistantIndicator() {
    bool isListeningNow = (_chatStatus == ChatStatus.chatting || _chatStatus == ChatStatus.dislikeChatting || _chatStatus == ChatStatus.likeChatting);
    bool isCompletedState = (_chatStatus == ChatStatus.completed || _chatStatus == ChatStatus.dislikeCompleted || _chatStatus == ChatStatus.likeCompleted);

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isListeningNow ? Colors.red[50] : Colors.green[50],
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isListeningNow ? Colors.red[200]! : Colors.green[200]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isListeningNow ? Icons.record_voice_over : Icons.online_prediction_outlined,
              color: isListeningNow ? Colors.red[700] : Colors.green[700],
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              isListeningNow
                  ? "🎙️ 說話聆聽中... (說「結束錄音」或手動結束，完整彙整送出)"
                  : isCompletedState
                  ? "🤖 AI 監聽中... 說「重新錄音」或「結束聊天」"
                  : "🤖 AI 監聽中... 說「開始錄音」",
              style: TextStyle(
                fontSize: 12,
                color: isListeningNow ? Colors.red[800] : Colors.green[800],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvaluationImage() {
    return Container(
      width: 320,
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[200],
      ),
      clipBehavior: Clip.antiAlias,
      child: _currentImageUrl.isNotEmpty
          ? (_currentImageUrl.startsWith('http') || _currentImageUrl.startsWith('https')
          ? Image.network(
        _currentImageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.grey)));
        },
      )
          : (kIsWeb
          ? const Center(
        child: Text(
          'Web 瀏覽器無法讀取電腦硬碟檔案\n\n請改用 Windows 桌面版執行\n(或更新後端提供靜態網址)',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      )
          : Image.file(
        File(_currentImageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey)),
      )))
          : const Center(child: Icon(Icons.image, size: 64, color: Colors.grey)),
    );
  }

  Widget _buildControlSection() {
    switch (_chatStatus) {
      case ChatStatus.prepare:
        return PrepareView(
          onStartChat: _triggerStartChatFlow, // 手動/語音自動分流一體化
        );
      case ChatStatus.chatting:
        return ListeningView(
          recordSeconds: _recordSeconds,
          onEndRecording: _handleEndChat,
        );
      case ChatStatus.completed:
        return CompletedView(
          onRestartChat: _triggerStartChatFlow,
          onEndChat: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.keywords; });
            // 進入非語音關鍵字確認頁，徹底暫停並關閉錄製
            _stopActiveAudioOperations();
          },
        );
      case ChatStatus.keywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerImageGeneration);
      case ChatStatus.generating:
        return const GeneratingView();
      case ChatStatus.evaluation:
        return EvaluationView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onLike: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.likePrepare; });
            // 重新進入對話狀態，重啟背景喚醒監聽！
            _startBackgroundWakeWordCycle();
          },
          onDislike: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.dislikePrepare; });
            // 重新進入對話狀態，重啟背景喚醒監聽！
            _startBackgroundWakeWordCycle();
          },
        );
      case ChatStatus.dislikePrepare:
        return DislikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onStartChat: _triggerStartChatFlow,
        );
      case ChatStatus.dislikeChatting:
        return DislikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          recordSeconds: _recordSeconds,
          onEndRecording: _handleEndChat,
        );
      case ChatStatus.dislikeCompleted:
        return CompletedView(
          onRestartChat: _triggerStartChatFlow,
          onEndChat: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.dislikeKeywords; });
            // 進入非語音關鍵字確認頁，徹底暫停並關閉錄製
            _stopActiveAudioOperations();
          },
        );
      case ChatStatus.dislikeKeywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerModifiedImageGeneration);
      case ChatStatus.dislikeGenerating:
        return const GeneratingView();
      case ChatStatus.dislikeEvaluation:
        return DislikeEvaluationView(
          onContinueModify: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.dislikePrepare; });
            // 重新進入對話狀態，重啟背景喚醒監聽！
            _startBackgroundWakeWordCycle();
          },
          onFinished: _resetAllStates,
        );
      case ChatStatus.likePrepare:
        return LikePrepareView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          onStartChat: _triggerStartChatFlow,
        );
      case ChatStatus.likeChatting:
        return LikeChattingView(
          selectedLanguage: _selectedLanguage,
          onLanguageSelected: _playCurrentContextVoice,
          recordSeconds: _recordSeconds,
          onEndRecording: _handleEndChat,
        );
      case ChatStatus.likeCompleted:
        return CompletedView(
          onRestartChat: _triggerStartChatFlow,
          onEndChat: () {
            if (!mounted) return;
            setState(() { _chatStatus = ChatStatus.likeKeywords; });
            // 進入非語音關鍵字確認頁，徹底暫停並關閉錄製
            _stopActiveAudioOperations();
          },
        );
      case ChatStatus.likeKeywords:
        return KeywordsConfirmButton(isDisabled: _isExtractingKeywords, onConfirm: _triggerLikeExtendedImageGeneration);
      case ChatStatus.likeGenerating:
        return const GeneratingView();
    }
  }
}