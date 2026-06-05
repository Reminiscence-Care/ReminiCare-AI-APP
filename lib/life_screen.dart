import 'dart:async';
import 'package:flutter/material.dart';

/// 聊天流程的四個狀態：準備中、進行/聆聽中、完成、關鍵詞擷取
enum ChatStatus {
  prepare,
  chatting,
  completed,
  keywords,
}

class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key});

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> {
  // AI 生成的文字，預設放上圖片中的問題以便預覽。未來您可以直接清空它以顯示預留的 Placeholder。
  String _aiGeneratedText = "小時候家裡最常吃什麼呢？";
  String _selectedLanguage = "台語"; // 預設語言選取
  bool _isLoading = false; // LLM API 請求時的載入狀態
  bool _isExtractingKeywords = false; // LLM 擷取關鍵字時的載入狀態
  bool _isGeneratingImage = false; // 點擊確認生圖時的載入狀態

  // 管理當前聊天狀態，預設為準備中
  ChatStatus _chatStatus = ChatStatus.prepare;

  // 錄音計時器變數 (205 秒即為 03:25，完美貼合 image_8d3cfe.png)
  int _recordSeconds = 205;
  Timer? _recordTimer;

  // 關鍵字設定變數
  final int _maxKeywordLength = 5; // 最大關鍵字數量限制
  // 預設擷取出的關鍵字（未來可直接在 _fetchKeywordsFromLLM 內更換為 LLM 回傳結果）
  List<String> _extractedKeywords = ["蕃薯飯", "炒青菜", "包子", "豆乾", "醃蘿蔔"];

  /// 啟動錄音計時器
  void _startTimer() {
    _recordTimer?.cancel(); // 啟動前先清除舊的，防重複
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordSeconds++;
      });
    });
  }

  /// 停止錄音計時器
  void _stopTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  /// 格式化秒數為 MM:SS 格式
  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  /// 未來直接在此串接 LLM API (例如呼叫 Gemini API 產生問題)
  Future<void> _fetchQuestionFromLLM() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // ==========================================
      // TODO: 在這裡寫入您的 LLM API 呼叫程式碼
      // ==========================================
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _aiGeneratedText = "您覺得人生中最難忘的一餐是什麼？";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 模擬呼叫 LLM 從錄音文字擷取關鍵字
  Future<void> _fetchKeywordsFromLLM() async {
    setState(() {
      _isExtractingKeywords = true;
    });

    try {
      // ==========================================
      // TODO: 在這裡串接 LLM API，傳入錄音文字，並回傳關鍵字清單
      // ==========================================
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        // 模擬取得新的關鍵字（此處保持與 image_8cc49f.png 一致的關鍵字）
        _extractedKeywords = ["蕃薯飯", "炒青菜", "包子", "豆乾", "排骨酥"];
        _isExtractingKeywords = false;
      });
    } catch (e) {
      setState(() {
        _isExtractingKeywords = false;
      });
    }
  }

  /// 模擬生成圖片的動作流程
  Future<void> _triggerImageGeneration() async {
    setState(() {
      _isGeneratingImage = true;
    });

    // 模擬 AI 生圖時間
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isGeneratingImage = false;
    });

    // 生圖完成後回到首頁，重置狀態
    _resetAllStates();
  }

  /// 重置整個生命週期
  void _resetAllStates() {
    setState(() {
      _chatStatus = ChatStatus.prepare;
      _recordSeconds = 205;
      _stopTimer();
    });
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 重新生成按鈕
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: '重新生成問題',
            onPressed: (_isLoading || _chatStatus != ChatStatus.prepare)
                ? null
                : _fetchQuestionFromLLM,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // 語言選擇列 (台語 / 中文)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLanguageOption("台語"),
                      const SizedBox(width: 48),
                      _buildLanguageOption("中文"),
                    ],
                  ),

                  const Spacer(flex: 2),

                  // 中央主要的問題文字顯示區
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isLoading
                        ? _buildLoadingIndicator()
                        : _buildQuestionArea(),
                  ),

                  const Spacer(flex: 2),

                  // 動態關鍵詞展示區域 (僅在 keywords 狀態下顯示)
                  _buildDynamicKeywordsArea(),

                  const Spacer(flex: 2),

                  // 底部狀態控制器
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildControlSection(),
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),

            // 生圖中的全螢幕覆蓋載入特效
            if (_isGeneratingImage) _buildGeneratingOverlay(),
          ],
        ),
      ),
    );
  }

  /// 建立語言選擇按鈕 (台語 / 中文)
  Widget _buildLanguageOption(String language) {
    final bool isSelected = _selectedLanguage == language;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLanguage = language;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.grey[400] : Colors.grey[300],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              language,
              style: TextStyle(
                fontSize: 20,
                color: isSelected ? Colors.black : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顯示主要問題或預留的 Placeholder
  Widget _buildQuestionArea() {
    if (_aiGeneratedText.isEmpty) {
      return Container(
        key: const ValueKey<String>("placeholder"),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          "等待 AI 產生問題中...",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w300,
            color: Colors.grey[400],
            height: 1.5,
            letterSpacing: 1.0,
          ),
        ),
      );
    }

    return Container(
      key: ValueKey<String>(_aiGeneratedText),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        _aiGeneratedText,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: Colors.black,
          height: 1.5,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  /// 載入動畫
  Widget _buildLoadingIndicator() {
    return Container(
      key: const ValueKey<String>("loading"),
      height: 42,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
        ),
      ),
    );
  }

  /// 動態關鍵字區塊 (完美還原 image_8cc49f.png 細框線排版)
  Widget _buildDynamicKeywordsArea() {
    if (_chatStatus != ChatStatus.keywords) {
      return const SizedBox.shrink(); // 非關鍵字狀態則隱藏不佔空間
    }

    if (_isExtractingKeywords) {
      return Column(
        key: const ValueKey<String>("keywords_loading"),
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "AI 正在為您精準擷取關鍵詞...",
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      );
    }

    // 限制顯示的最多關鍵字個數
    final displayKeywords = _extractedKeywords.take(_maxKeywordLength).toList();

    return Padding(
      key: const ValueKey<String>("keywords_loaded"),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左側固定文字「提到的關鍵詞：」
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              "提到的關鍵詞：",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 右側動態 Wrap，彈性自動換行
          Expanded(
            child: Wrap(
              spacing: 12.0, // 水平間距
              runSpacing: 10.0, // 垂直換行間距
              children: displayKeywords.map((keyword) => _buildKeywordChip(keyword)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 建立與設計圖 100% 貼合的關鍵字標籤
  Widget _buildKeywordChip(String word) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6F6), // 極輕微的粉灰暖色調底色
        borderRadius: BorderRadius.circular(2), // 簡約的小微導角邊框
        border: Border.all(
          color: const Color(0xFFD4C9C9), // 細緻的淡粉灰色框線
          width: 0.8,
        ),
      ),
      child: Text(
        word,
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey[800],
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  /// 根據目前的狀態返回對應的控制介面
  Widget _buildControlSection() {
    switch (_chatStatus) {
      case ChatStatus.prepare:
        return _buildPrepareStateControls();
      case ChatStatus.chatting:
        return _buildListeningStateControls();
      case ChatStatus.completed:
        return _buildCompletedStateControls();
      case ChatStatus.keywords:
        return _buildKeywordsStateControls();
    }
  }

  /// 1. 準備開始聊天
  Widget _buildPrepareStateControls() {
    return SizedBox(
      key: const ValueKey<String>("prepare_state"),
      width: 150,
      height: 48,
      child: TextButton(
        onPressed: () {
          setState(() {
            _chatStatus = ChatStatus.chatting;
            _recordSeconds = 205;
            _startTimer();
          });
        },
        style: TextButton.styleFrom(
          backgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          '開始聊天',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[800],
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  /// 2. 正在聆聽與錄音中 (按鈕：結束錄音)
  Widget _buildListeningStateControls() {
    return Row(
      key: const ValueKey<String>("listening_state"),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[300],
              ),
              alignment: Alignment.center,
              child: Text(
                '正在聆聽中',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '已錄音 : ${_formatDuration(_recordSeconds)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(width: 40),

        SizedBox(
          width: 130,
          height: 48,
          child: TextButton(
            onPressed: () {
              setState(() {
                _chatStatus = ChatStatus.completed;
                _stopTimer();
              });
            },
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: EdgeInsets.zero,
            ),
            child: Text(
              '結束錄音',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 3. 錄音完成頁面 (按鈕：重新聊天 / 結束聊天)
  Widget _buildCompletedStateControls() {
    return Column(
      key: const ValueKey<String>("completed_state"),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.grey[600], size: 24),
            const SizedBox(width: 8),
            Text(
              '聊天完成',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey[800],
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 重新聊天
            SizedBox(
              width: 130,
              height: 48,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _chatStatus = ChatStatus.chatting;
                    _recordSeconds = 205;
                    _startTimer();
                  });
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  '重新聊天',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),

            // 結束聊天 -> 點擊進入 4. 擷取關鍵詞
            SizedBox(
              width: 130,
              height: 48,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _chatStatus = ChatStatus.keywords;
                  });
                  // 觸發模擬的 LLM 擷取任務
                  _fetchKeywordsFromLLM();
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[400],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: const Text(
                  '結束聊天',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 4. 關鍵字擷取成功頁面 (按鈕：確認生圖)
  Widget _buildKeywordsStateControls() {
    return SizedBox(
      key: const ValueKey<String>("keywords_state"),
      width: 150,
      height: 48,
      child: TextButton(
        onPressed: _isExtractingKeywords ? null : _triggerImageGeneration,
        style: TextButton.styleFrom(
          backgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          '確認生圖',
          style: TextStyle(
            fontSize: 16,
            color: _isExtractingKeywords ? Colors.grey[400] : Colors.grey[800],
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  /// 生圖進行中的載入覆蓋遮罩
  Widget _buildGeneratingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.4),
      alignment: Alignment.center,
      child: Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
              ),
              SizedBox(height: 16),
              Text(
                'AI 正在為您編織並生成圖片...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}