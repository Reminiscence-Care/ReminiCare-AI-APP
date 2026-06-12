import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/services/reminicare_ai_services.dart';
import 'package:remini_care_ai_app/services/spotify_api_services.dart';


class SearchByTextsOrSpeech extends StatefulWidget {
  final String? texts_or_speech;
  final String? languageLabel;
  const SearchByTextsOrSpeech({super.key, this.texts_or_speech, this.languageLabel});

  @override
  State<StatefulWidget> createState() => _SearchByTextsOrSpeechState();
}

class _SearchByTextsOrSpeechState extends State<SearchByTextsOrSpeech> {
  // 使用 Controller 來管理輸入框的文字
  final TextEditingController _textController = TextEditingController(text: '我要你的愛');
  final String spotifyClientId = ReminiCareConfig.spotifyClientId;
  final String spotifyClientSecret = ReminiCareConfig.spotifyClientSecret;
  late String? artistName;
  late String? trackName;
  late String? artistUrl;
  late String? trackUrl;
  @override
  void dispose() {
    _textController.dispose(); // 記得釋放資源
    super.dispose();
  }

  Future<void> _setEmbedUrls(String query) async {
    final spotifyApiServices = SpotifyApiServices(
      spotifyClientId,
      spotifyClientSecret
    );
    final List<String>? spotifySearchResults = await spotifyApiServices.getArtistAndTracks(query) as List<String>;
    artistName = spotifySearchResults?[0];
    trackName = spotifySearchResults?[1];
    artistUrl = spotifySearchResults?[2];
    trackUrl = spotifySearchResults?[3];
  }

  @override
  Widget build(BuildContext context) {
    // 判斷當前是否為文字模式
    final bool isTextMode = widget.texts_or_speech == 'texts';
    final String currentLanguage = widget.languageLabel ?? '國語歌';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '以前聽過的歌',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              Text(
                currentLanguage,
                style: const TextStyle(fontSize: 60, color: Colors.black87),
              ),
              const SizedBox(height: 60),

              // 2. 條件渲染區塊：根據變數決定顯示文字輸入還是語音按鈕
              if (isTextMode)
                _buildTextInputUI(currentLanguage)
              else
                _buildSpeechInputUI(currentLanguage),

              const SizedBox(height: 32),

              // 3. 條件渲染區塊：底部提示文字
              Text(
                isTextMode ? '文字輸入中' : '語音輸入中',
                style: const TextStyle(fontSize: 30, color: Colors.black87),
              ),
            ],
          ),
        ),
      )
    );
  }

  // 獨立出來的文字輸入 UI
  Widget _buildTextInputUI(String languageLabel) {
    return SizedBox(
      width: 220, // 限制輸入框的寬度
      child: TextField(
        controller: _textController,
        textAlign: TextAlign.center, // 讓文字置中
        cursorColor: Colors.white, // 模仿截圖中的白色游標
        cursorWidth: 3.0,
        autofocus: true, // 進來這頁自動彈出鍵盤

        // 將鍵盤右下角的按鈕設為「搜尋」樣式
        textInputAction: TextInputAction.search,

        // 當使用者按下鍵盤的搜尋/確認鍵時觸發
        onSubmitted: (String value) async {
          // 防呆機制：如果使用者沒打字就按搜尋，可以直接 return 不做任何事
          if (value.trim().isEmpty) return;
          await _setEmbedUrls(value);
          // 這裡放你的跳轉邏輯，並把輸入的文字 (value) 帶過去
          // 假設你的下一個頁面路由叫做 /search_results
          final queryParams = {
            'artistUrl': artistUrl,
            'trackUrl': trackUrl,
          };
          final uri = Uri(
            path: '/search_results/$artistName/$trackName/$languageLabel',
            queryParameters: queryParams
          ).toString();
          context.push(uri);
        },

        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.grey[300], // 淺灰背景色
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none, // 移除預設的黑框
          ),
        ),
        style: const TextStyle(fontSize: 18),
      ),
    );
  }

  // 獨立出來的語音輸入 UI
  Widget _buildSpeechInputUI(String languageLabel) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        shape: BoxShape.circle, // 圓形背景
      ),
      child: IconButton(
        icon: const Icon(Icons.mic, size: 40, color: Colors.black87),
        onPressed: () {
          // 這裡可以觸發開啟麥克風的邏輯
          String value = "123";
          if(value == "") {
            // 要 UI 提示重講
          }
          context.push('/search_results/$value/$languageLabel');
        },
      ),
    );
  }
}