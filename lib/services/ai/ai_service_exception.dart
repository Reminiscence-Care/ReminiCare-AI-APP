enum AiServiceErrorKind {
  authentication,
  billing,
  rateLimit,
  timeout,
  network,
  invalidResponse,
  unsupportedCapability,
  configuration,
}

class AiServiceException implements Exception {
  const AiServiceException(this.kind, this.message, {this.statusCode});
  final AiServiceErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AiServiceException($kind): $message';
}
