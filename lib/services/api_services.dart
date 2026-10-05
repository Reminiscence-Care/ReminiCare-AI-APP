import 'ai/ai_models.dart';
import 'ai/cloud_vision_reranker.dart';
import 'ai/llm_client.dart';
import 'ai/provider_registry.dart';
import 'ai/reminiscence_ai_service.dart';
import 'audio_services/speech_services.dart';
import 'image_gen_api_service.dart';
import 'remini_care_config.dart';

class ApiServices {
  factory ApiServices() => _instance;
  ApiServices._();
  static final ApiServices _instance = ApiServices._();

  int _builtRevision = -1;
  ReminiscenceAiService? _ai;
  IImageGenerationClient? _image;
  ISTTService? _stt;
  ITTSService? _tts;
  ITopicImageReranker? _topicImageReranker;

  void resetCache() {
    _builtRevision = -1;
    _ai = null;
    _image = null;
    _stt = null;
    _tts = null;
    _topicImageReranker = null;
  }

  ReminiscenceAiService get reminiscenceAi {
    _ensureCurrent();
    return _ai ??= ReminiscenceAiService(
      OpenAiCompatibleLlmClient(
        config: _llmConfig(),
        apiKey: ReminiCareConfig.getValue(_llmConfig().apiKeyReference),
      ),
    );
  }

  IImageGenerationClient get image {
    _ensureCurrent();
    final config = _imageConfig();
    return _image ??= config.id == 'cloudflare'
        ? CloudflareWorkerImageClient(
            config: config,
            appToken: ReminiCareConfig.getValue(config.apiKeyReference),
          )
        : OpenAiCompatibleImageClient(
            config: config,
            apiKey: ReminiCareConfig.getValue(config.apiKeyReference),
          );
  }

  ImageProviderConfig get imageConfig => _imageConfig();

  ITopicImageReranker get topicImageReranker {
    _ensureCurrent();
    return _topicImageReranker ??= CloudTopicImageReranker(
      config: _visionConfig(),
      apiKey: ReminiCareConfig.getValue(_visionConfig().apiKeyReference),
    );
  }

  ISTTService get stt {
    _ensureCurrent();
    final cached = _stt;
    if (cached != null) return cached;
    final ISTTService service =
        ReminiCareConfig.getValue('selectedSpeechProvider') == 'ncku'
        ? NckuSpeechService()
        : YatingSpeechService();
    _stt = service;
    return service;
  }

  ITTSService get tts {
    _ensureCurrent();
    final cached = _tts;
    if (cached != null) return cached;
    final ITTSService service =
        ReminiCareConfig.getValue('selectedSpeechProvider') == 'ncku'
        ? NckuSpeechService()
        : YatingSpeechService();
    _tts = service;
    return service;
  }

  void _ensureCurrent() {
    if (_builtRevision == ReminiCareConfig.revision) return;
    resetCache();
    _builtRevision = ReminiCareConfig.revision;
  }

  LlmProviderConfig _llmConfig() {
    final id = ReminiCareConfig.getValue('selectedLlmProvider');
    if (id == 'custom') {
      return LlmProviderConfig(
        id: 'custom',
        displayName: 'Custom OpenAI-compatible',
        baseUrl: ReminiCareConfig.getValue('CUSTOM_LLM_BASE_URL'),
        model: ReminiCareConfig.getValue('CUSTOM_LLM_MODEL'),
        apiKeyReference: 'CUSTOM_LLM_API_KEY',
        isCustom: true,
      );
    }
    final preset =
        ProviderRegistry.llmPresets[id] ??
        ProviderRegistry.llmPresets['nvidia']!;
    final modelKey = switch (preset.id) {
      'openai' => 'OPENAI_LLM_MODEL',
      'gemini' => 'GEMINI_LLM_MODEL',
      _ => 'NVIDIA_LLM_MODEL',
    };
    final configuredModel = ReminiCareConfig.getValue(modelKey).trim();
    return LlmProviderConfig(
      id: preset.id,
      displayName: preset.displayName,
      baseUrl: preset.baseUrl,
      model: configuredModel.isEmpty ? preset.model : configuredModel,
      apiKeyReference: preset.apiKeyReference,
      timeout: preset.timeout,
    );
  }

  ImageProviderConfig _imageConfig() {
    final id = ReminiCareConfig.getValue('selectedImageProvider');
    if (id == 'cloudflare') {
      final preset = ProviderRegistry.imagePresets['cloudflare']!;
      return ImageProviderConfig(
        id: preset.id,
        displayName: preset.displayName,
        baseUrl: ReminiCareConfig.getValue('CLOUDFLARE_IMAGE_WORKER_URL'),
        generationModel: preset.generationModel,
        editModel: preset.editModel,
        apiKeyReference: preset.apiKeyReference,
        capabilities: preset.capabilities,
        timeout: preset.timeout,
      );
    }
    if (id == 'custom') {
      return ImageProviderConfig(
        id: 'custom',
        displayName: 'Custom OpenAI-compatible',
        baseUrl: ReminiCareConfig.getValue('CUSTOM_IMAGE_BASE_URL'),
        generationModel: ReminiCareConfig.getValue('CUSTOM_IMAGE_MODEL'),
        apiKeyReference: 'CUSTOM_IMAGE_API_KEY',
        capabilities: const {ProviderCapability.imageGeneration},
        isCustom: true,
      );
    }
    return ProviderRegistry.imagePresets[id] ??
        ProviderRegistry.imagePresets['cloudflare']!;
  }

  VisionProviderConfig _visionConfig() {
    final id = ReminiCareConfig.getValue('selectedVisionProvider');
    if (id == 'custom') {
      return VisionProviderConfig(
        id: 'custom',
        displayName: 'Custom Vision OpenAI-compatible',
        baseUrl: ReminiCareConfig.getValue('CUSTOM_VISION_BASE_URL'),
        model: ReminiCareConfig.getValue('CUSTOM_VISION_MODEL'),
        apiKeyReference: 'CUSTOM_VISION_API_KEY',
        isCustom: true,
      );
    }
    final preset =
        ProviderRegistry.visionPresets[id] ??
        ProviderRegistry.visionPresets['nvidia']!;
    final modelKey = switch (preset.id) {
      'openai' => 'OPENAI_VISION_MODEL',
      'gemini' => 'GEMINI_VISION_MODEL',
      _ => 'NVIDIA_VISION_MODEL',
    };
    final configuredModel = ReminiCareConfig.getValue(modelKey).trim();
    return VisionProviderConfig(
      id: preset.id,
      displayName: preset.displayName,
      baseUrl: preset.baseUrl,
      model: configuredModel.isEmpty ? preset.model : configuredModel,
      apiKeyReference: preset.apiKeyReference,
      timeout: preset.timeout,
    );
  }
}
