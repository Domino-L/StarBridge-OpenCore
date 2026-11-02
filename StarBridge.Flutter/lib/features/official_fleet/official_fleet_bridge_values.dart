import '../../platform/bridge/bridge_envelope.dart';

void requireSchema(Map<String, Object?> payload) {
  if (payload['schemaVersion'] != 1) {
    throw const BridgeFormatException(
      'Official fleet payload schema is incompatible.',
    );
  }
}

Map<String, Object?> requiredMap(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! Map) {
    throw BridgeFormatException('$key must be an object.');
  }
  return value.cast<String, Object?>();
}

String requiredString(Map<String, Object?> source, String key) {
  final value = optionalString(source, key);
  if (value == null) {
    throw BridgeFormatException('$key must be a non-empty string.');
  }
  return value;
}

String? optionalString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw BridgeFormatException('$key must be a string or null.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? optionalInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw BridgeFormatException('$key must be an integer or null.');
  }
  return value;
}

int? optionalNonNegativeInt(Map<String, Object?> source, String key) {
  final value = optionalInt(source, key);
  if (value != null && value < 0) {
    throw BridgeFormatException('$key must not be negative.');
  }
  return value;
}
