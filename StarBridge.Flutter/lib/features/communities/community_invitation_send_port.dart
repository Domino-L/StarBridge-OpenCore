abstract interface class CommunityInvitationSendPort {
  Stream<void> get invalidations;
  bool get invitationSendingAvailable;
  Future<List<CommunityInvitationOperation>> readInvitationOutbox();
  Future<CommunityInvitationProgress> sendInvitation({
    required String operationId,
    required String organizationRef,
    required String channel,
    required String destinationRef,
    required int maxUses,
  });
  Future<CommunityInvitationProgress> resumeInvitation(
    String operationId, {
    String action = 'check',
  });
}

final class CommunityInvitationOperation {
  const CommunityInvitationOperation(
    this.operationId,
    this.channel,
    this.phase,
    this.sourceName,
    this.destinationName,
    this.requestedAt,
    this.maxUses,
  );
  final String operationId, channel, phase, sourceName, destinationName;
  final DateTime requestedAt;
  final int maxUses;

  static List<CommunityInvitationOperation> parsePage(
    Map<String, Object?> data,
  ) {
    if (data.length != 2 ||
        data['schemaVersion'] != 1 ||
        data['items'] is! List) {
      throw const FormatException();
    }
    final rows = data['items']! as List;
    if (rows.length > 128) throw const FormatException();
    final seen = <String>{};
    return List.unmodifiable(
      rows.map((raw) {
        if (raw is! Map || raw.length != 7) throw const FormatException();
        final row = Map<String, Object?>.from(raw);
        final id = _text(row, 'operationId', 32);
        final channel = _text(row, 'channel', 16);
        final phase = _text(row, 'phase', 16);
        final time = DateTime.tryParse(_text(row, 'requestedAt', 64));
        final uses = row['maxUses'];
        if (!_id(id) ||
            !seen.add(id) ||
            !{'private', 'room'}.contains(channel) ||
            !{
              'prepared',
              'generating',
              'ready',
              'sending',
              'sent',
            }.contains(phase) ||
            time == null ||
            uses is! int ||
            uses < 1 ||
            uses > 50) {
          throw const FormatException();
        }
        return CommunityInvitationOperation(
          id,
          channel,
          phase,
          _text(row, 'sourceName', 512),
          _text(row, 'destinationName', 512),
          time,
          uses,
        );
      }),
    );
  }
}

final class CommunityInvitationProgress {
  const CommunityInvitationProgress(
    this.operationId,
    this.status, [
    this.error,
  ]);
  final String operationId, status;
  final String? error;
  static CommunityInvitationProgress parse(
    Map<String, Object?> data,
    String expected,
  ) {
    final id = _text(data, 'operationId', 32);
    final status = _text(data, 'status', 16);
    final error = data['error'];
    if (data['schemaVersion'] != 1 ||
        data.length < 3 ||
        data.length > 4 ||
        data.keys.any(
          (key) => !{
            'schemaVersion',
            'operationId',
            'status',
            'error',
          }.contains(key),
        ) ||
        id != expected ||
        !_id(id) ||
        !{'pending', 'unknown', 'rejected', 'sent'}.contains(status) ||
        error != null &&
            (error is! String ||
                !{
                  'dataInvalid',
                  'busy',
                  'unavailable',
                  'notAllowed',
                  'identityUnavailable',
                  'outcomeUnknown',
                  'refreshRequired',
                  'rateLimited',
                  'inviteInvalid',
                  'notFound',
                  'intentChanged',
                  'generationPending',
                  'deliveryPending',
                  'localRecoveryUnavailable',
                }.contains(error))) {
      throw const FormatException();
    }
    return CommunityInvitationProgress(id, status, error as String?);
  }
}

bool _id(String value) => RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
String _text(Map<String, Object?> data, String key, int max) {
  final value = data[key];
  if (value is! String ||
      value.length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException();
  }
  return value;
}
