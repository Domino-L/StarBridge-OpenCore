import 'dart:math';

import 'package:flutter/foundation.dart';

import 'community_ship_report_port.dart';

final class CommunityShipReportController extends ChangeNotifier {
  CommunityShipReportController(
    this.port,
    this.targetRef,
    this.shipRef,
    this.version,
  );
  final CommunityShipReportPort port;
  final String targetRef, shipRef, version;
  String? reason;
  String details = '';
  CommunityShipReportIntent? intent;
  CommunityShipReportOutcome? outcome;
  bool busy = false, _closed = false;
  bool get unknown => outcome?.status == 'unknown';
  bool get accepted => outcome?.status == 'accepted';
  bool get editable => !busy && !unknown && !accepted && !_closed;
  bool get dirty =>
      !accepted && (reason != null || details.isNotEmpty || unknown);
  void edit(String? nextReason, String nextDetails) {
    if (!editable) return;
    reason = nextReason;
    details = nextDetails;
    outcome = null;
    notifyListeners();
  }

  Future<void> submit() async {
    if (!editable || reason == null) return;
    try {
      final random = Random.secure();
      intent = CommunityShipReportIntent(
        targetRef: targetRef,
        shipRef: shipRef,
        version: version,
        requestId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        reason: reason!,
        details: details,
      );
    } on FormatException {
      outcome = const CommunityShipReportOutcome(
        'rejected',
        error: 'dataInvalid',
      );
      notifyListeners();
      return;
    }
    await _run(false);
  }

  Future<void> check() async {
    if (busy || _closed || !unknown || intent == null) return;
    await _run(true);
  }

  Future<void> _run(bool checking) async {
    busy = true;
    notifyListeners();
    CommunityShipReportOutcome result;
    try {
      result = await (checking
          ? port.checkShipReport(intent!)
          : port.reportShipImage(intent!));
    } catch (_) {
      result = const CommunityShipReportOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
    if (_closed) return;
    // A lookup rejection does not prove that the original submission failed.
    outcome = checking && result.status != 'accepted'
        ? const CommunityShipReportOutcome('unknown', error: 'outcomeUnknown')
        : result;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    reason = null;
    details = '';
    intent = null;
    outcome = null;
    super.dispose();
  }
}
