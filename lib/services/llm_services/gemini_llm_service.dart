import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'llm_service.dart';

class GeminiLlmService extends LlmService {
  GeminiLlmService()
      : super(
    // 💡 超級黑科技：Gemini 官方原生支援的 OpenAI 相容端點！
    baseUrl: "https://generativelanguage.googleapis.com/v1beta/openai/",
    model: "gemini-2.5-flash",
    apiKey: ReminiCareConfig.geminiApiKey,
  );
}