import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_admissions_port.dart';
import 'community_workspace_port.dart';

final class CommunityManagementController extends ChangeNotifier {
  CommunityManagementController(
    this.port,
    this.targetRef, {
    this.section = 'applications',
  }) {
    _subscription = port.invalidations.listen((_) {
      invalidated = true;
      _epoch++;
      page = null;
      images.clear();
      pendingImages.clear();
      outcome = null;
      notifyListeners();
    });
  }
  final CommunityAdmissionsPort port;
  final String targetRef;
  late final StreamSubscription<void> _subscription;
  final images = <String, Uint8List>{};
  final pendingImages = <String>{};
  CommunityAdmissionsPage? page;
  CommunityAdmissionOutcome? outcome;
  String section;
  String? error;
  bool busy = false,
      submitting = false,
      invalidated = false,
      mediaFailed = false;
  int _epoch = 0;
  final _readClock = Stopwatch();
  DateTime get serverNow =>
      (page?.fetchedAt ?? DateTime.now()).add(_readClock.elapsed);
  bool _closed = false;
  bool get locked => busy || submitting || invalidated || _closed;
  bool _current(int epoch) => !_closed && !invalidated && epoch == _epoch;
  void _check(int epoch) {
    if (!_current(epoch)) throw const CommunityFailure('identityUnavailable');
  }

  Future<void> load({
    String? section,
    int offset = 0,
    bool quiet = false,
  }) async {
    if (_closed || invalidated || submitting) return;
    if (quiet && busy) return;
    final previous = page;
    final previousImages = quiet ? Map<String, Uint8List>.of(images) : null;
    if (section != null) this.section = section;
    final epoch = ++_epoch;
    busy = true;
    if (!quiet) {
      page = null;
      images.clear();
    }
    pendingImages.clear();
    error = null;
    mediaFailed = false;
    notifyListeners();
    try {
      final result = await port.readAdmissions(targetRef, this.section, offset);
      if (!_current(epoch)) return;
      page = result;
      if (port is CommunityWorkspacePort && result.section == 'applications') {
        pendingImages.addAll(
          result.items
              .where((row) => row['hasAvatar'] == true)
              .map((row) => row['entryRef'] as String),
        );
      }
      _readClock.reset();
      _readClock.start();
      busy = false;
      notifyListeners();
      if (port is CommunityWorkspacePort && result.section == 'applications') {
        final media = port as CommunityWorkspacePort;
        for (final row in result.items.where(
          (row) => row['hasAvatar'] == true,
        )) {
          _check(epoch);
          final ref = row['entryRef'] as String;
          try {
            final bytes = await assembleCommunityMedia(
              (offset, version) => media.readMedia(
                targetRef,
                'applicant',
                memberRef: ref,
                offset: offset,
                version: version,
              ),
              'applicant',
              memberRef: ref,
              checkCurrent: () => _check(epoch),
            );
            _check(epoch);
            images[ref] = bytes;
          } catch (failure) {
            _check(epoch);
            if (failure is CommunityFailure &&
                const {
                  'notAllowed',
                  'identityUnavailable',
                  'refreshRequired',
                }.contains(failure.code)) {
              rethrow;
            }
            mediaFailed = true;
          } finally {
            if (_current(epoch)) pendingImages.remove(ref);
          }
          notifyListeners();
        }
      }
    } catch (failure) {
      if (!_current(epoch)) return;
      busy = false;
      page = null;
      images.clear();
      pendingImages.clear();
      error = failure is CommunityFailure ? failure.code : 'unavailable';
      if (quiet && error == 'unavailable') {
        page = previous;
        images.addAll(previousImages!);
      }
      notifyListeners();
    }
  }

  Future<void> execute(
    CommunityAdmissionAction action, {
    String? entryRef,
    int? days,
    int? uses,
    bool confirmUncertainRetry = false,
  }) async {
    if (locked || page == null) return;
    final random = Random.secure();
    final intent = CommunityAdmissionIntent(
      requestId: List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      targetRef: targetRef,
      action: action,
      entryRef: entryRef,
      expiresInDays: days,
      maxUses: uses,
      confirmUncertainRetry: confirmUncertainRetry,
    );
    final epoch = ++_epoch;
    submitting = true;
    error = null;
    notifyListeners();
    try {
      final result = await port.manageAdmissions(intent);
      if (!_current(epoch)) return;
      outcome = result;
    } catch (_) {
      if (!_current(epoch)) return;
      outcome = const CommunityAdmissionOutcome(
        'unknown',
        error: 'outcomeUnknown',
      );
    }
    submitting = false;
    notifyListeners();
    // Acknowledged writes stay acknowledged even if the independent refresh fails.
    await load();
  }

  @override
  void dispose() {
    _closed = true;
    _readClock.stop();
    _epoch++;
    images.clear();
    pendingImages.clear();
    page = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
