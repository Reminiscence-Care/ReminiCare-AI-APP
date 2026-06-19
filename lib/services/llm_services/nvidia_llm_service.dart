import 'package:remini_care_ai_app/services/llm_services/llm_service.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

class NvidiaLlmService extends LlmService {
  NvidiaLlmService()
      : super(
    baseUrl: "https://integrate.api.nvidia.com/v1",
    model: "qwen/qwen3-next-80b-a3b-instruct",
    apiKey: ReminiCareConfig.nvidiaApiKey,
  );
}