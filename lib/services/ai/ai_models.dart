enum ProviderCapability { textGeneration, imageGeneration, imageEditing }

class LlmProviderConfig {
  const LlmProviderConfig({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.apiKeyReference,
    this.timeout = const Duration(seconds: 60),
    this.isCustom = false,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final String model;
  final String apiKeyReference;
  final Duration timeout;
  final bool isCustom;
}

class VisionProviderConfig {
  const VisionProviderConfig({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.apiKeyReference,
    this.timeout = const Duration(seconds: 45),
    this.isCustom = false,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final String model;
  final String apiKeyReference;
  final Duration timeout;
  final bool isCustom;
}

class ImageProviderConfig {
  const ImageProviderConfig({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.generationModel,
    required this.apiKeyReference,
    required this.capabilities,
    this.editModel,
    this.timeout = const Duration(minutes: 3),
    this.isCustom = false,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final String generationModel;
  final String? editModel;
  final String apiKeyReference;
  final Set<ProviderCapability> capabilities;
  final Duration timeout;
  final bool isCustom;

  bool supports(ProviderCapability capability) =>
      capabilities.contains(capability);
}

class LlmMessage {
  const LlmMessage(this.role, this.content);
  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}
