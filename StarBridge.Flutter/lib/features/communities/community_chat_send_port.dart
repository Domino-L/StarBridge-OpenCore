import 'community_chat_port.dart';

abstract interface class CommunityChatSendPort {
  bool get chatSendAvailable;
  Future<CommunityChatSendOutcome> sendChat(CommunityChatSendIntent intent);
}

final class CommunityChatSendIntent {
  CommunityChatSendIntent({
    required this.targetRef,
    required this.requestId,
    required String text,
    Map<String, Object?>? attachment,
  }) : text = text.trim(),
       attachment = attachment == null ? null : Map.unmodifiable(attachment) {
    if (!_reference.hasMatch(targetRef) ||
        !_reference.hasMatch(requestId) ||
        text.length > 1000 ||
        _controls.hasMatch(text) ||
        this.text.isEmpty && attachment == null) {
      throw const FormatException();
    }
    if (attachment != null) {
      if (attachment.keys.any(
            (key) => !{
              'kind',
              'title',
              'summary',
              'overlayPresetPackage',
            }.contains(key),
          ) ||
          attachment['title'] is! String ||
          (attachment['title'] as String).trim().isEmpty ||
          (attachment['title'] as String).length > 64 ||
          attachment['summary'] is! String ||
          (attachment['summary'] as String).trim().isEmpty ||
          (attachment['summary'] as String).length > 240 ||
          RegExp(r'[\x00-\x1f\x7f-\x9f]')
              .hasMatch('${attachment['title']}${attachment['summary']}')) {
        throw const FormatException();
      }
      CommunityChatDetail.parse({
        'avatarImageData': null,
        'attachment': attachment,
      });
    }
  }
  static final _reference = RegExp(r'^[a-f0-9]{32}$');
  static final _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]');
  final String targetRef, requestId, text;
  final Map<String, Object?>? attachment;
  Map<String, Object?> toPayload() => {
    'targetRef': targetRef,
    'requestId': requestId,
    'text': text,
    'attachment': attachment,
  };
}

final class CommunityChatSendOutcome {
  const CommunityChatSendOutcome(this.status, {this.error, this.sequence});
  factory CommunityChatSendOutcome.parse(
    Map<String, Object?> row,
    CommunityChatSendIntent intent,
  ) {
    if (row['schemaVersion'] != 1 ||
        row['targetRef'] != intent.targetRef ||
        row['requestId'] != intent.requestId ||
        !['accepted', 'rejected', 'unknown'].contains(row['status'])) {
      throw const FormatException();
    }
    final status = row['status'] as String;
    final error = row['error'];
    final sequence = row['sequence'];
    if (error != null && (error is! String || error.length > 64)) {
      throw const FormatException();
    }
    if (status == 'accepted') {
      if (error != null ||
          sequence is! int ||
          sequence <= 0 ||
          sequence >= 0x7fffffffffffffff) {
        throw const FormatException();
      }
      return CommunityChatSendOutcome(status, sequence: sequence);
    }
    if (sequence != null) throw const FormatException();
    return CommunityChatSendOutcome(status, error: error as String?);
  }
  final String status;
  final String? error;
  final int? sequence;
}
