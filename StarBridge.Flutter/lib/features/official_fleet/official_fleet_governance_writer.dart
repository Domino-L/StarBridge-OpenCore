import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../communities/communities_module.dart';
import 'official_fleet_governance_management.dart';

/// An uncertain write keeps the complete intent until its exact retry resolves.
final class FleetGovernanceWriter extends ChangeNotifier {
  FleetGovernanceWriter(this.port, this.source, this.onChanged) {
    _subscription = port.invalidations.listen((_) {
      ++_epoch;
      pending = null;
      busy = false;
      retired = true;
      result = 'identityUnavailable';
      notifyListeners();
    });
  }
  final OfficialFleetGovernanceManagementPort port;
  final String source;

  /// Set by whichever dialog has this writer open. A dialog cannot close while
  /// a write runs, so a write never finishes into one that has gone.
  Future<void> Function() onChanged;
  late final StreamSubscription<void> _subscription;
  ({String command, GovernanceRow fields})? pending;
  bool busy = false, retired = false;
  String? result;
  int _epoch = 0;

  Future<String?> submit(String command, GovernanceRow fields) async {
    if (busy || retired) return null;
    final retry = pending != null;
    final intent =
        pending ??
        (
          command: command,
          fields: jsonDecode(
            jsonEncode({
              ...fields,
              command == 'manageRoleTemplates' ? 'requestId' : 'operationId':
                  governanceOperationId(),
            }),
          ) as GovernanceRow,
        );
    final epoch = ++_epoch;
    busy = true;
    result = null;
    notifyListeners();
    String outcome;
    try {
      outcome = await _send(intent, retry);
    } on CommunityFailure catch (error) {
      outcome = error.code;
    } on Object {
      outcome = 'operationOutcomeUnknown';
    }
    if (epoch != _epoch) return null;
    pending =
        outcome == 'operationOutcomeUnknown' ||
            outcome == 'unavailable' && pending != null
        ? intent
        : null;
    result = outcome;
    if (const {
      'accepted',
      'duplicate',
      'conflict',
      'notAllowed',
    }.contains(outcome)) {
      try {
        await onChanged();
      } on Object {
        // The receipt remains true even when its following read fails.
      }
    }
    if (epoch != _epoch) return null;
    busy = false;
    notifyListeners();
    return outcome;
  }

  /// The Host answers a repeated template request from its journal only, so a
  /// retry asks for the receipt. Sending again is left for a request it never saw.
  Future<String> _send(
    ({String command, GovernanceRow fields}) intent,
    bool retry,
  ) async {
    if (retry &&
        intent.command == 'manageRoleTemplates' &&
        port.supports('readRoleTemplateOutcome')) {
      final known = await port.roleTemplateOutcome(
        source,
        intent.fields['requestId'] as String,
      );
      if (known != governanceOutcomeNotFound) return known;
    }
    return port.write(intent.command, source, intent.fields);
  }

  @override
  void dispose() {
    ++_epoch;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
