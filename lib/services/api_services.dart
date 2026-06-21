import 'package:flutter/foundation.dart';
import 'package:remini_care_ai_app/services/audio_services/voice_assistant_services.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

// 引入所有已有的 Service 實作
import 'audio_services/speech_services.dart';
import 'image_gen_api_service.dart';
import 'llm_services/nvidia_llm_service.dart';
import 'llm_services/openai_llm_service.dart';
import 'llm_services/gemini_llm_service.dart';

// =========================================================================
// 💡 1. 定義通用的 LLM 介面 (Interface)
// 確保未來不管是 OpenAI, Nvidia 還是 Gemini，都具備相同的函式特徵！
// =========================================================================
abstract class ILLMService {
  Future<String> generateInitialQuestion();
  Future<String> generateChatReply(String userMessage, List<Map<String, String>> history);
  Future<String> generateExtendedQuestion(String previousQuestion, String elderResponse);
  Future<String> extractElderName(String transcript);
  Future<Map<String, dynamic>> extractSceneData(String transcript);
  Future<List<String>> extractKeywords(String transcript);
  Future<List<Map<String, String>>> recommendationSongsName(String? language);
  Future<Map<String, dynamic>> getSingerAndSongNameFromQuery(String query);
  String get modelName;
}

// =========================================================================
// 🏭 2. 全局 API 服務工廠 (Singleton Service Locator)
// =========================================================================
class ApiServices {
  // 單例模式實作
  static final ApiServices _instance = ApiServices._internal();
  factory ApiServices() => _instance;
  ApiServices._internal();

  // 內部快取的實例
  ILLMService? _llmService;
  ISTTService? _sttService;
  ITTSService? _ttsService;
  IImageGenService? _imageGenService;

  /// 🧹 當使用者在「設定頁面」修改了 API 供應商並儲存時，請呼叫此方法！
  /// 呼叫後會清空舊實例，下次使用時會根據新設定自動實例化正確的 Service。
  void resetCache() {
    _llmService = null;
    _sttService = null;
    _ttsService = null;
    _imageGenService = null;
    debugPrint("🔄 [ApiServices] 已重置所有 API 實例快取，準備套用新設定！");
  }

  // -------------------------------------------------------------------------
  // 🧠 取得當前設定的 LLM 服務
  // -------------------------------------------------------------------------
  ILLMService get llm {
    if (_llmService != null) return _llmService!;

    // 假設您在 ReminiCareConfig 裡新增了 'selectedLlmProvider' 欄位
    // 如果沒有設定，預設使用 nvidia
    final provider = ReminiCareConfig.getValue('selectedLlmProvider') ?? 'nvidia';

    switch (provider) {
      case 'openai':
      // 需確保 OpenAILlmService 有 implements ILLMService
        _llmService = OpenAILlmService() as ILLMService;
        break;
      case 'gemini':
      // 需確保 GeminiLlmService 有 implements ILLMService
        _llmService = GeminiLlmService() as ILLMService;
        break;
      case 'nvidia':
      default:
      // 需確保 NvidiaLlmService 有 implements ILLMService
        _llmService = NvidiaLlmService() as ILLMService;
        break;
    }
    debugPrint("🔌 [ApiServices] LLM 服務已掛載: $provider");
    return _llmService!;
  }

  // -------------------------------------------------------------------------
  // 🎙️ 取得當前設定的 語音辨識 (STT) 服務
  // -------------------------------------------------------------------------
  ISTTService get stt {
    if (_sttService != null) return _sttService!;

    final provider = ReminiCareConfig.getValue('selectedSpeechProvider') ?? 'yating';
    switch (provider) {
      case 'ncku':
        _sttService = NckuSpeechService();
        break;
      case 'yating':
      default:
        _sttService = YatingSpeechService();
        break;
    }
    debugPrint("🔌 [ApiServices] STT 服務已掛載: $provider");
    return _sttService!;
  }

  // -------------------------------------------------------------------------
  // 🔊 取得當前設定的 語音合成 (TTS) 服務
  // -------------------------------------------------------------------------
  ITTSService get tts {
    if (_ttsService != null) return _ttsService!;

    // 通常 STT 跟 TTS 會是同一家，但也可以拆開
    final provider = ReminiCareConfig.getValue('selectedSpeechProvider') ?? 'yating';
    switch (provider) {
      case 'ncku':
        _ttsService = NckuSpeechService();
        break;
      case 'yating':
      default:
        _ttsService = YatingSpeechService();
        break;
    }
    debugPrint("🔌 [ApiServices] TTS 服務已掛載: $provider");
    return _ttsService!;
  }

  // -------------------------------------------------------------------------
  // 🎨 取得當前設定的 影像生成 服務
  // -------------------------------------------------------------------------
  IImageGenService get image {
    if (_imageGenService != null) return _imageGenService!;

    final provider = ReminiCareConfig.getValue('selectedImageProvider') ?? 'siliconflow';
    switch (provider) {
      case 'openai':
        _imageGenService = OpenAIImageService(
          apiKeyProvider: () => ReminiCareConfig.openaiApiKey,
        );
        break;
      case 'siliconflow':
      default:
        _imageGenService = SiliconFlowImageService(
          rawBaseUrl: "https://api.siliconflow.com/v1",
          apiKeyProvider: () => ReminiCareConfig.siliconFlowApiKey,
          generationModel: "Qwen/Qwen-Image",
          editModel: "Qwen/Qwen-Image-Edit",
          defaultNegativePrompt: "Simplified Chinese, deformed strokes, extra strokes, missing strokes, broken characters, typos, gibberish, illegible text, messy scribbles, distorted text, blurred text, worst quality, low resolution, bad anatomy, watermark, signature",
        );
        break;
    }
    debugPrint("🔌 [ApiServices] 生圖服務已掛載: $provider");
    return _imageGenService!;
  }
}