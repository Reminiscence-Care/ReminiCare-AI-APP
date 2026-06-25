import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'llm_service.dart';

class OpenAILlmService extends LlmService {
  OpenAILlmService()
      : super(
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-4o-mini",
    apiKey: ReminiCareConfig.openaiApiKey,
  );
}