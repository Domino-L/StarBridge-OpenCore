import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../communities/communities_module.dart';
import 'organization_announcement_management_port.dart';
import 'organization_announcement_outcomes_controller.dart';

/// Current surface coordination only. The original form owns drafts; Native
/// Host owns durable prepared/sendStarted/unknown attempts and all authority.
final class OrganizationAnnouncementManagementSession extends ChangeNotifier {
  OrganizationAnnouncementManagementSession(
    this.port,
    this.sourceRef, {
    required this.outcomes,
    String Function()? requestId,
  }) : _requestId = requestId ?? _newRequestId {
    if (!identical(outcomes.port, port)) throw ArgumentError('Different port');
    _subscription = port.managementInvalidations.listen((_) => invalidate());
    outcomes.addListener(_outcomesChanged);
  }
  final OrganizationAnnouncementManagementPort port;
  final OrganizationAnnouncementOutcomesController outcomes;
  final String sourceRef;
  final String Function() _requestId;
  late final StreamSubscription<void> _subscription;
  OrganizationAnnouncementEditor? editor;
  OrganizationAnnouncementIntent? originalIntent;
  OrganizationAnnouncementOutcome? outcome;
  bool loading = false, sending = false, _closed = false;
  String? error;
  int _epoch = 0;
  bool get unresolved => originalIntent != null && outcome?.unresolved == true;
  bool get canPrepare => !_closed && !loading && !sending && !unresolved;
  bool canSubmit(String action) =>
      canPrepare &&
      editor != null &&
      port.managementAvailable &&
      editor!.allowedActions.contains(action);

  Future<void> prepare() async {
    if (!canPrepare) return;
    final epoch = _epoch;
    loading = true;
    editor = null;
    error = null;
    notifyListeners();
    try {
      if (!port.managementAvailable) {
        throw const CommunityFailure('unavailable');
      }
      await outcomes.refresh();
      if (!_current(epoch)) return;
      if (!outcomes.complete) {
        throw const CommunityFailure('localRecoveryUnavailable');
      }
      if (outcomes.hasUnresolvedSource(sourceRef)) {
        throw const CommunityFailure('outcomeUnknown');
      }
      final value = await port.readEditor(sourceRef);
      if (!_current(epoch)) return;
      if (value.sourceRef != sourceRef) throw const FormatException();
      editor = value;
      originalIntent = null;
      outcome = null;
    } catch (failure) {
      if (_current(epoch)) {
        editor = null;
        error = failure is CommunityFailure ? failure.code : 'dataInvalid';
      }
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> submit(String action, {String? title, String? content}) async {
    if (!canSubmit(action)) return;
    final baseline = editor!;
    OrganizationAnnouncementIntent intent;
    try {
      if (baseline.revision == 0x7fffffffffffffff) {
        throw const FormatException();
      }
      intent = OrganizationAnnouncementIntent(
        sourceRef: sourceRef,
        editRef: baseline.editRef,
        requestId: _requestId(),
        action: action,
        announcementRef: action == 'publish'
            ? null
            : baseline.current?.announcementRef,
        title: title,
        content: content,
      );
    } on FormatException {
      error = 'dataInvalid';
      notifyListeners();
      return;
    }
    final epoch = _epoch;
    originalIntent = intent;
    outcome = null;
    sending = true;
    error = null;
    editor = null; // Receipt history is never a reusable editing permission.
    notifyListeners();
    try {
      final result = await port.manage(intent);
      if (!_current(epoch)) return;
      if (result.requestId != intent.requestId ||
          result.sourceRef != sourceRef ||
          result.action != action ||
          result.status == 'accepted' &&
              result.revision != baseline.revision + 1) {
        throw const FormatException();
      }
      outcome = result;
      error = result.error;
    } catch (_) {
      if (_current(epoch)) {
        outcome = OrganizationAnnouncementOutcome.unknown(intent);
        error = 'outcomeUnknown';
      }
    } finally {
      if (_current(epoch)) {
        sending = false;
        notifyListeners();
      }
    }
  }

  Future<void> queryOriginal() async {
    final intent = originalIntent;
    if (_closed || sending || !unresolved || intent == null) return;
    final epoch = _epoch;
    final result = await outcomes.query(intent.requestId, original: intent);
    if (!_current(epoch) || result == null) return;
    outcome = result;
    error = result.error;
    // A historical accepted/rejected result releases uncertainty only. Explicit
    // prepare must acquire fresh admission; this never sends another mutation.
    notifyListeners();
  }

  void _outcomesChanged() {
    final intent = originalIntent;
    if (_closed || sending || !unresolved || intent == null) {
      return;
    }
    final result = outcomes.results[intent.requestId];
    if (result == null ||
        !const {'accepted', 'rejected'}.contains(result.status) ||
        result.requestId != intent.requestId ||
        result.sourceRef != sourceRef ||
        result.sourceRef != intent.sourceRef ||
        result.action != intent.action) {
      return;
    }
    outcome = result;
    error = result.error;
    // This releases matching uncertainty only. Editor/authority stays retired;
    // the page must explicitly prepare against current admission again.
    notifyListeners();
  }

  bool _current(int epoch) => !_closed && _epoch == epoch;
  void invalidate() {
    if (_closed) return;
    _epoch++;
    editor = null;
    originalIntent = null;
    outcome = null;
    loading = sending = false;
    error = 'identityUnavailable';
    notifyListeners();
  }

  static String _newRequestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    unawaited(_subscription.cancel());
    outcomes.removeListener(_outcomesChanged);
    super.dispose();
  }
}
