import 'dart:convert';
import 'dart:typed_data';

abstract final class BridgeProtocol {
  static const currentVersion = 1;
  static const maximumFrameBytes = 1024 * 1024;
}

final class BridgeAccountContext {
  const BridgeAccountContext({
    required this.environment,
    required this.authority,
    required this.subject,
  });

  factory BridgeAccountContext.fromJson(Map<String, Object?> json) {
    return BridgeAccountContext(
      environment: _requiredString(json, 'environment'),
      authority: _requiredString(json, 'authority'),
      subject: _requiredString(json, 'subject'),
    );
  }

  final String environment;
  final String authority;
  final String subject;

  Map<String, Object?> toJson() => {
    'environment': environment,
    'authority': authority,
    'subject': subject,
  };
}

final class BridgeErrorBody {
  const BridgeErrorBody({
    required this.code,
    required this.message,
    required this.retryable,
  });

  factory BridgeErrorBody.fromJson(Map<String, Object?> json) {
    return BridgeErrorBody(
      code: _requiredString(json, 'code'),
      message: _requiredString(json, 'message'),
      retryable: json['retryable'] as bool? ?? false,
    );
  }

  final String code;
  final String message;
  final bool retryable;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'retryable': retryable,
  };
}

final class BridgeEnvelope {
  const BridgeEnvelope({
    required this.protocolVersion,
    required this.messageType,
    required this.name,
    required this.sessionGeneration,
    required this.payload,
    this.correlationId,
    this.accountContext,
    this.sequence,
    this.status,
    this.error,
  });

  factory BridgeEnvelope.fromJson(Map<String, Object?> json) {
    final context = json['accountContext'];
    final error = json['error'];
    final envelope = BridgeEnvelope(
      protocolVersion: _requiredInt(json, 'protocolVersion'),
      messageType: _requiredString(json, 'messageType'),
      name: _requiredString(json, 'name'),
      correlationId: json['correlationId'] as String?,
      sessionGeneration: _requiredInt(json, 'sessionGeneration'),
      accountContext: context is Map<String, Object?>
          ? BridgeAccountContext.fromJson(context)
          : context is Map
          ? BridgeAccountContext.fromJson(context.cast<String, Object?>())
          : null,
      sequence: json['sequence'] as int?,
      payload: _objectMap(json['payload']),
      status: json['status'] as String?,
      error: error is Map<String, Object?>
          ? BridgeErrorBody.fromJson(error)
          : error is Map
          ? BridgeErrorBody.fromJson(error.cast<String, Object?>())
          : null,
    );
    envelope.validateWireShape();
    return envelope;
  }

  final int protocolVersion;
  final String messageType;
  final String name;
  final String? correlationId;
  final int sessionGeneration;
  final BridgeAccountContext? accountContext;
  final int? sequence;
  final Map<String, Object?> payload;
  final String? status;
  final BridgeErrorBody? error;

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'messageType': messageType,
    'name': name,
    if (correlationId != null) 'correlationId': correlationId,
    'sessionGeneration': sessionGeneration,
    if (accountContext != null) 'accountContext': accountContext!.toJson(),
    if (sequence != null) 'sequence': sequence,
    'payload': payload,
    if (status != null) 'status': status,
    if (error != null) 'error': error!.toJson(),
  };

  void validateWireShape() {
    if (protocolVersion <= 0 || name.isEmpty || sessionGeneration < 0) {
      throw const BridgeFormatException(
        'Bridge envelope contains an invalid required field.',
      );
    }
    if ((messageType == 'request' || messageType == 'response') &&
        (correlationId == null || correlationId!.isEmpty)) {
      throw const BridgeFormatException(
        'Request and response require correlationId.',
      );
    }
    if (messageType == 'event' && (sequence == null || sequence! < 0)) {
      throw const BridgeFormatException(
        'Event requires a non-negative sequence.',
      );
    }
    if (messageType != 'request' &&
        messageType != 'response' &&
        messageType != 'event') {
      throw const BridgeFormatException('Unsupported bridge message type.');
    }
    if (messageType == 'response') {
      if (status != 'ok' && status != 'error' && status != 'cancelled') {
        throw const BridgeFormatException(
          'Response contains an invalid status.',
        );
      }
      if (status == 'error' && error == null) {
        throw const BridgeFormatException(
          'Error response requires an error body.',
        );
      }
    }
  }

  void requireCurrentVersion() {
    if (protocolVersion != BridgeProtocol.currentVersion) {
      throw BridgeVersionException(protocolVersion);
    }
  }
}

abstract final class BridgeFrameCodec {
  static Uint8List encode(BridgeEnvelope envelope) {
    envelope.validateWireShape();
    final payload = utf8.encode(jsonEncode(envelope.toJson()));
    if (payload.isEmpty || payload.length > BridgeProtocol.maximumFrameBytes) {
      throw const BridgeFormatException(
        'Bridge frame is empty or exceeds the size limit.',
      );
    }
    final frame = Uint8List(4 + payload.length);
    ByteData.sublistView(frame).setUint32(0, payload.length, Endian.little);
    frame.setRange(4, frame.length, payload);
    return frame;
  }

  static BridgeEnvelope decode(Uint8List frame) {
    if (frame.length < 5) {
      throw const BridgeFormatException('Bridge frame is truncated.');
    }
    final length = ByteData.sublistView(
      frame,
      0,
      4,
    ).getUint32(0, Endian.little);
    if (length <= 0 ||
        length > BridgeProtocol.maximumFrameBytes ||
        length != frame.length - 4) {
      throw const BridgeFormatException('Bridge frame length is invalid.');
    }
    final decoded = jsonDecode(utf8.decode(frame.sublist(4)));
    if (decoded is! Map) {
      throw const BridgeFormatException(
        'Bridge envelope must be a JSON object.',
      );
    }
    return BridgeEnvelope.fromJson(decoded.cast<String, Object?>());
  }
}

class BridgeFormatException implements Exception {
  const BridgeFormatException(this.message);
  final String message;
  @override
  String toString() => 'BridgeFormatException: $message';
}

final class BridgeVersionException extends BridgeFormatException {
  const BridgeVersionException(this.receivedVersion)
    : super('Bridge protocol version is incompatible.');
  final int receivedVersion;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw BridgeFormatException('$key must be a non-empty string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw BridgeFormatException('$key must be an integer.');
  }
  return value;
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map.unmodifiable(value);
  }
  if (value is Map) {
    return Map.unmodifiable(value.cast<String, Object?>());
  }
  throw const BridgeFormatException('payload must be a JSON object.');
}
