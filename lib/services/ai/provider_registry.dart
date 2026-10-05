import 'ai_models.dart';

abstract final class ProviderRegistry {
  static const llmPresets = <String, LlmProviderConfig>{
    'nvidia': LlmProviderConfig(
      id: 'nvidia',
      displayName: 'NVIDIA',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'deepseek-ai/deepseek-v4.1-flash',
      apiKeyReference: 'NVIDIA_API_KEY',
    ),
    'openai': LlmProviderConfig(
      id: 'openai',
      displayName: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      apiKeyReference: 'OPENAI_API_KEY',
    ),
    'gemini': LlmProviderConfig(
      id: 'gemini',
      displayName: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-2.5-flash',
      apiKeyReference: 'GEMINI_API_KEY',
    ),
  };

  static const imagePresets = <String, ImageProviderConfig>{
    'siliconflow': ImageProviderConfig(
      id: 'siliconflow',
      displayName: 'SiliconFlow',
      baseUrl: 'https://api.siliconflow.com/v1',
      generationModel: 'Qwen/Qwen-Image',
      editModel: 'Qwen/Qwen-Image-Edit',
      apiKeyReference: 'SILICONFLOW_API_KEY',
      capabilities: {
        ProviderCapability.imageGeneration,
        ProviderCapability.imageEditing,
      },
    ),
    'openai': ImageProviderConfig(
      id: 'openai',
      displayName: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      generationModel: 'gpt-image-2',
      apiKeyReference: 'OPENAI_API_KEY',
      capabilities: {ProviderCapability.imageGeneration},
    ),
  };

  static const visionPresets = <String, VisionProviderConfig>{
    'nvidia': VisionProviderConfig(
      id: 'nvidia',
      displayName: 'NVIDIA Vision',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'meta/llama-3.2-11b-vision-instruct',
      apiKeyReference: 'NVIDIA_API_KEY',
    ),
    'openai': VisionProviderConfig(
      id: 'openai',
      displayName: 'OpenAI Vision',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      apiKeyReference: 'OPENAI_API_KEY',
    ),
    'gemini': VisionProviderConfig(
      id: 'gemini',
      displayName: 'Google Gemini Vision',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-2.5-flash',
      apiKeyReference: 'GEMINI_API_KEY',
    ),
  };
}
