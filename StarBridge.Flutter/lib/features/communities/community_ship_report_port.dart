abstract interface class CommunityShipReportPort {
  bool get shipReportAvailable;
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  );
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  );
}

final class CommunityShipReportIntent {
  CommunityShipReportIntent({
    required this.targetRef,
    required this.shipRef,
    required this.version,
    required this.requestId,
    required this.reason,
    String details = '',
  }) : details = details.trim() {
    final reference = RegExp(r'^[a-f0-9]{32}$');
    if (!reference.hasMatch(targetRef) ||
        !reference.hasMatch(shipRef) ||
        !reference.hasMatch(requestId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(version) ||
        !reasons.contains(reason) ||
        details.length > 1000 ||
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]').hasMatch(details)) {
      throw const FormatException();
    }
  }
  static const reasons = [
    'harassment',
    'spam',
    'impersonation',
    'hate_or_threat',
    'inappropriate_content',
    'fraud_or_scam',
    'privacy',
    'other',
  ];
  final String targetRef, shipRef, version, requestId, reason, details;
  Map<String, Object?> toPayload() => {
    'targetRef': targetRef,
    'shipRef': shipRef,
    'version': version,
    'requestId': requestId,
    'reason': reason,
    'details': details,
  };
}

final class CommunityShipReportOutcome {
  const CommunityShipReportOutcome(this.status, {this.error});
  factory CommunityShipReportOutcome.parse(
    Map<String, Object?> row,
    CommunityShipReportIntent intent,
  ) {
    final status = row['status'], error = row['error'];
    if (row['schemaVersion'] != 1 ||
        row['targetRef'] != intent.targetRef ||
        row['shipRef'] != intent.shipRef ||
        row['requestId'] != intent.requestId ||
        !['accepted', 'rejected', 'unknown'].contains(status) ||
        error != null && (error is! String || error.length > 64) ||
        status == 'accepted' && error != null ||
        status == 'unknown' && error != 'outcomeUnknown') {
      throw const FormatException();
    }
    return CommunityShipReportOutcome(
      status as String,
      error: error as String?,
    );
  }
  final String status;
  final String? error;
}
