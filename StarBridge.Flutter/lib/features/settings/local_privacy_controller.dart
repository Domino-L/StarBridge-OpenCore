import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import 'local_privacy_port.dart';
import 'local_privacy_settings.dart';
import 'privacy_publication_port.dart';
import 'community_sharing.dart';
import 'community_member_sharing.dart';
import 'official_runtime_privacy_port.dart';
import 'official_runtime_privacy_module.dart';
import 'local_privacy_official_edits.dart';
import 'local_privacy_community_edits.dart';
import 'privacy_publication_monitor.dart';

import 'local_privacy_read_helpers.dart';
import 'coalesced_read.dart';

enum LocalPrivacyStatus { initial, loading, ready, unavailable, signedOut }

enum CommunityTargetsFailure { none, serviceUnavailable, retryable }

/// Owns one account's draft; invalidation discards it before any new read starts.
final class LocalPrivacyController extends ChangeNotifier
    with LocalPrivacyOfficialEdits, LocalPrivacyCommunityEdits {
  LocalPrivacyController(this._port)
    : _official = OfficialRuntimePrivacyModule(_port) {
    _subscription = _port.invalidations.listen((_) {
      _epoch++;
      _snapshot = null;
      draft = null;
      saving = false;
      _saveToken = null;
      _finishBackgroundReads();
      errorKey = null;
      publicationView = const PrivacyPublicationView('inactive');
      publicationObserved = false;
      publicationReadFailures = 0;
      publicationBusy = false;
      status = LocalPrivacyStatus.initial;
      communityTargets = null;
      _pendingTargetNames.clear();
      communityTargetsFailed = false;
      communityTargetsFailure = CommunityTargetsFailure.none;
      _settingsReading = false;
      _official.retire(saving: false);
      notifyListeners();
      if (_opened || _publicationMonitors > 0) unawaited(refresh());
    });
    if (_port case final OfficialRuntimePrivacyPort official) {
      _officialSubscription = official.officialRuntimePrivacyInvalidations
          .listen((_) {
            _official.retireUnder(saving, publicationBusy);
            notifyListeners();
            if (_opened && !saving && !publicationBusy) {
              unawaited(refreshOfficialRuntimePrivacy());
            }
          });
    }
  }
  final LocalPrivacyPort _port;
  bool get locationConfidenceSupported =>
      _port is LocationConfidencePrivacyPort &&
      (_port as LocationConfidencePrivacyPort).locationConfidenceSupported;
  late final StreamSubscription<void> _subscription;
  LocalPrivacySnapshot? _snapshot;
  @override
  LocalPrivacySettings? draft;
  LocalPrivacyStatus status = LocalPrivacyStatus.initial;
  String? errorKey;
  bool saving = false;
  bool needsReload = false;
  bool _opened = false;
  bool _disposed = false;
  final OfficialRuntimePrivacyModule _official;
  StreamSubscription<void>? _officialSubscription;
  @override
  OfficialRuntimePrivacyModule get officialModule => _official;

  Future<void> refreshOfficialRuntimePrivacy() async {
    if (_disposed ||
        !officialRuntimePrivacySupported ||
        saving ||
        publicationBusy ||
        _settingsReading ||
        officialScopeReading ||
        status != LocalPrivacyStatus.ready) {
      return;
    }
    final epoch = _epoch;
    final read = _official.refresh(revision);
    notifyListeners();
    final result = await read;
    if (!_current(epoch) || result == OfficialPrivacyRefreshResult.retired) {
      return;
    }
    if (result == OfficialPrivacyRefreshResult.conflict) {
      needsReload = true;
      errorKey = 'privacy.local.conflict';
    }
    notifyListeners();
  }

  @override
  CommunitySharingTargets? communityTargets;
  final _pendingTargetNames = <String, String>{};
  void renameCommunity(String code, String name) {
    if (_disposed) return;
    if (_targets.active) _pendingTargetNames[code] = name;
    communityTargets = communityTargets?.renamed(code, name);
    notifyListeners();
  }

  @override
  bool communityTargetsFailed = false;
  CommunityTargetsFailure communityTargetsFailure =
      CommunityTargetsFailure.none;
  final _targets = CoalescedRead();
  bool _settingsReading = false;
  Completer<void>? _settingsReadDone;
  bool _publicationReading = false;
  Completer<void>? _publicationReadDone;
  Object? _saveToken;
  void _finishBackgroundReads() {
    _targets.retire();
    _settingsReadDone?.complete();
    _settingsReadDone = null;
    _publicationReadDone?.complete();
    _publicationReadDone = null;
    _publicationReading = false;
  }

  int _memberReads = 0;
  bool get communitySharingSupported =>
      _port is CommunitySharingPort &&
      (_port as CommunitySharingPort).communitySharingSupported;
  int _epoch = 0;
  Timer? _targetsTimer;
  bool publicationBusy = false;
  bool publicationObserved = false;
  int publicationReadFailures = 0;
  int _publicationMonitors = 0;
  bool get savedPublicationEnabled =>
      _snapshot?.settings?.publicationEnabled == true;

  /// Receipts confirm saved publication only; drafts never activate grants.
  bool get savedCommunityChoicesPending => hasPendingCommunityChoices(
    _snapshot?.settings,
    communityTargets,
    supported: communitySharingSupported,
    failed: communityTargetsFailed,
  );

  @override
  PrivacyPublicationView publicationView = const PrivacyPublicationView('inactive');
  bool get publicationSupported =>
      _port is PrivacyPublicationPort &&
      (_port as PrivacyPublicationPort).publicationSupported;
  int get revision => _snapshot?.revision ?? 0;
  int get scopeEpoch => _epoch;
  bool get communityMemberSharingSupported =>
      _port is CommunityMemberSharingPort &&
      (_port as CommunityMemberSharingPort).communityMemberSharingSupported;

  Future<List<CommunitySharingMember>> readCommunityMembers(
    CommunitySharingScope scope,
  ) async {
    _memberReads++;
    try {
      return await _readCommunityMembers(scope);
    } finally {
      _memberReads--;
    }
  }

  Future<List<CommunitySharingMember>> _readCommunityMembers(
    CommunitySharingScope scope,
  ) async {
    if (!communityMemberSharingSupported) {
      throw const BridgeClientException('host.capability_missing');
    }
    final epoch = _epoch;
    void requireCurrent() {
      if (!_current(epoch) ||
          !canEdit ||
          !(communityTargets?.communities.any(
                (target) => target.matches(scope),
              ) ??
              false)) {
        throw const BridgeClientException('privacy_local.account_changed');
      }
    }

    return readCommunityMemberSnapshot(
      _port as CommunityMemberSharingPort,
      scope,
      requireCurrent: requireCurrent,
    );
  }

  @override
  bool get hasSaved => _snapshot?.settings != null;
  LocalPrivacySettings? get savedSettings => _snapshot?.settings;
  @override
  bool get canEdit =>
      status == LocalPrivacyStatus.ready &&
      !saving &&
      !needsReload &&
      !publicationBusy;
  bool get _ordinaryDirty => privacySettingsDiffer(draft, _snapshot?.settings);
  bool get dirty => _ordinaryDirty || officialDirty;
  bool get canSave =>
      _saveToken == null &&
      !officialScopeReading &&
      canEdit &&
      (dirty || officialReconfirmRequired ||
          !hasSaved ||
          publicationSupported &&
              draft?.publicationEnabled == true &&
              const {
                'inactive',
                'withdrawn',
                'failed',
              }.contains(publicationView.state));

  void open() {
    _opened = true;
    _targetsTimer ??= Timer.periodic(const Duration(seconds: 15), (_) async {
      if (draft == null && status != LocalPrivacyStatus.ready) {
        await refresh();
      } else {
        await refresh(silently: true);
        if (_opened && !_disposed) await refreshCommunityTargets();
      }
    });
    _startPublicationTimer();
    if (status == LocalPrivacyStatus.initial) unawaited(refresh());
  }

  void closeEditor() {
    _opened = false;
    if (_publicationMonitors == 0) _stopPublicationMonitoring();
    _targetsTimer?.cancel();
    _targetsTimer = null;
    stopAccountWait();
  }

  /// Read-only app chrome and the editor share one account-bound status timer.
  VoidCallback monitorPublication() {
    if (_disposed) return () {};
    _publicationMonitors++;
    _startPublicationTimer();
    if (status == LocalPrivacyStatus.initial) {
      unawaited(refresh());
    } else {
      unawaited(refreshPublication());
    }
    var released = false;
    return () {
      if (released) return;
      released = true;
      _publicationMonitors--;
      if (!_opened && _publicationMonitors == 0) _stopPublicationMonitoring();
    };
  }

  late final _publicationMonitor = PrivacyPublicationMonitor(
    _port,
    _readPublicationStatus,
  );
  void _readPublicationStatus() {
    if (_disposed) return;
    if (status == LocalPrivacyStatus.initial ||
        status == LocalPrivacyStatus.unavailable) {
      unawaited(refresh());
    } else {
      unawaited(refreshPublication());
    }
  }

  void _startPublicationTimer() {
    if (publicationSupported) _publicationMonitor.start();
  }

  void _stopPublicationMonitoring() => _publicationMonitor.stop();

  Future<void> refresh({bool silently = false}) async {
    if (_disposed ||
        saving ||
        publicationBusy ||
        _publicationReading ||
        _settingsReading) {
      return;
    }
    if (silently &&
        (status != LocalPrivacyStatus.ready ||
            dirty ||
            _targets.active ||
            _memberReads > 0)) {
      return;
    }
    var epoch = silently ? _epoch : ++_epoch;
    final originalDraft = draft;
    final originalRevision = _snapshot?.revision;
    final completed = Completer<void>();
    _settingsReadDone = completed;
    _settingsReading = true;
    _targets.retire();
    if (!silently) {
      publicationObserved = false;
      publicationReadFailures = 0;
      status = LocalPrivacyStatus.loading;
      draft = null;
      _snapshot = null;
    }
    if (!silently) {
      errorKey = null;
      needsReload = false;
      notifyListeners();
    }
    try {
      final result = await _port.read();
      if (!_current(epoch)) return;
      // Unchanged lease renewal must not invalidate an open confirmation.
      if (silently && result.revision != _snapshot?.revision) {
        epoch = ++_epoch;
      }
      errorKey = null;
      needsReload = false;
      // Reading renews save authority, not authority to replace a new draft.
      final preserveDraft = silently && (draft != originalDraft || saving);
      if (preserveDraft && result.revision != originalRevision) {
        needsReload = true;
        errorKey = 'privacy.local.conflict';
      } else {
        _snapshot = result;
        if (!preserveDraft) {
          draft = result.settings ?? LocalPrivacySettings.editorDefaults;
        }
      }
      status = LocalPrivacyStatus.ready;
      hasReadOnce = true;
    } catch (error) {
      if (!_current(epoch)) return;
      if (_accountError(error)) {
        status = LocalPrivacyStatus.signedOut;
        draft = null;
        _snapshot = null;
      } else if (silently) {
        // Bridge reads renew the revision lease. Keep the display, but forbid
        // writes until a subsequent successful read restores that lease.
        needsReload = true;
      } else {
        status = LocalPrivacyStatus.unavailable;
      }
      errorKey = 'privacy.local.readFailed';
    } finally {
      if (_current(epoch)) _settingsReading = false;
      if (identical(_settingsReadDone, completed)) {
        _settingsReadDone = null;
      }
      if (!completed.isCompleted) completed.complete();
    }
    notifyListeners();
    if (status == LocalPrivacyStatus.ready) {
      await refreshPublication();
      await refreshCommunityTargets();
      await refreshOfficialRuntimePrivacy();
    }
  }

  Future<void> refreshCommunityTargets() async {
    if (_disposed ||
        !communitySharingSupported ||
        _settingsReading ||
        status != LocalPrivacyStatus.ready) {
      return;
    }
    final epoch = _epoch;
    // A request during a round waits only for the next shared round.
    await _targets.run(
      () async {
        _pendingTargetNames.clear();
        try {
          final result = await (_port as CommunitySharingPort)
              .readCommunityTargets();
          if (!_current(epoch)) return;
          communityTargets = withTargetNames(result, _pendingTargetNames);
          communityTargetsFailed = false;
          communityTargetsFailure = CommunityTargetsFailure.none;
        } catch (error) {
          if (!_current(epoch)) return;
          communityTargetsFailed = true;
          communityTargetsFailure = communityScopesUnavailable(error)
              ? CommunityTargetsFailure.serviceUnavailable
              : CommunityTargetsFailure.retryable;
        }
      },
      current: () => _current(epoch),
      allowed: () =>
          communitySharingSupported &&
          !_settingsReading &&
          status == LocalPrivacyStatus.ready,
    );
    if (_current(epoch)) notifyListeners();
  }

  Future<void> refreshPublication() => _publication('status');
  bool get canRetryPublication =>
      publicationSupported &&
      canEdit &&
      hasSaved &&
      !dirty &&
      !officialReconfirmRequired && // reapplying it only fails again
      savedPublicationEnabled &&
      const {
        'inactive',
        'withdrawn',
        'failed',
        'reconnecting',
      }.contains(publicationView.state);
  Future<void> applyPublication() => _publication('apply');
  Future<void> stopPublication() => _publication('stop');
  Future<PrivacyPublicationView?> _publication(
    String action, {
    bool ignoreDraft = false,
    bool firstOfficialDefault = false,
  }) async {
    if (_disposed ||
        !publicationSupported ||
        publicationBusy ||
        (action == 'status' && _publicationReading) ||
        _settingsReading ||
        saving ||
        status != LocalPrivacyStatus.ready ||
        ((action == 'apply' || action == 'applyPreservingPause') &&
            (dirty && !ignoreDraft || !hasSaved || needsReload))) {
      return null;
    }
    final epoch = _epoch;
    final reading = action == 'status';
    final priorRead = _publicationReadDone;
    final completed = reading ? Completer<void>() : null;
    if (reading) {
      _publicationReading = true;
      _publicationReadDone = completed;
    } else {
      publicationBusy = true;
      notifyListeners();
    }
    try {
      if (!reading && priorRead != null) {
        await priorRead.future;
        if (!_current(epoch) || needsReload) return null;
      }
      final result = await (_port as PrivacyPublicationPort).publication(
        action,
        revision: revision,
        firstOfficialDefault: firstOfficialDefault,
      );
      if (_current(epoch)) {
        publicationView = result;
        publicationObserved = true;
        publicationReadFailures = 0;
        return result;
      }
    } catch (error) {
      if (_current(epoch)) {
        if (_accountError(error)) {
          status = LocalPrivacyStatus.signedOut;
          draft = null;
          _snapshot = null;
          _official.retire(saving: false);
          publicationView = const PrivacyPublicationView('inactive');
          publicationObserved = false;
          publicationReadFailures = 0;
        } else if (reading) {
          // Losing the local status read is not evidence of a failed remote
          // publication. Keep its receipt separate from read freshness.
          publicationReadFailures++;
        } else {
          publicationObserved = true;
          publicationView = PrivacyPublicationView(
            'failed',
            errorCode: error is BridgeClientException ? error.code : null,
          );
        }
      }
    } finally {
      if (_current(epoch)) {
        if (reading) {
          _publicationReading = false;
        } else {
          publicationBusy = false;
        }
        notifyListeners();
      }
      if (completed != null) {
        if (identical(_publicationReadDone, completed)) {
          _publicationReadDone = null;
        }
        if (!completed.isCompleted) completed.complete();
      }
    }
    return null;
  }

  @override
  void edit(LocalPrivacySettings value) {
    if (!canEdit) return;
    draft = value;
    errorKey = null;
    notifyListeners();
  }

  void discard() {
    if (_disposed || saving || publicationBusy) return;
    draft = _snapshot == null
        ? null
        : _snapshot!.settings ?? LocalPrivacySettings.editorDefaults;
    _official.discard();
    errorKey = needsReload ? 'privacy.local.conflict' : null;
    notifyListeners();
  }

  /// First fleet choices save only their scope, never unrelated editor defaults.
  Future<bool> confirmOfficialFirstChoice(
    int fields, {
    int? audience,
    bool automaticDefault = false,
  }) async {
    if (!canEditOfficial ||
        officialScope?.choiceRequired != true &&
            officialScope?.fleetChanged != true ||
        fields < 0 ||
        fields > 15) {
      return false;
    }
    if (dirty) {
      errorKey = 'privacy.official.pendingEdits';
      notifyListeners();
      return false;
    }
    editOfficialFields(fields);
    if (officialScope!.audienceRankSupported) {
      _official.editAudience(fields == 0 ? null : audience);
    }
    final scope = officialScope;
    final result = await _save(
      officialOnly: true,
      firstOfficialDefault:
          automaticDefault && _official.isFirstDefault(fields, audience),
      requireAppliedPublication: scope?.fleetChanged == true,
    );
    if (!result && identical(scope, officialScope)) _official.discard();
    return result;
  }

  Future<bool> save({
    bool refreshStatus = true,
    bool explicitEditsOnly = false,
    bool officialOnly = false,
    String? onlyCommunity,
    bool keepDraft = false,
  }) => _save(
    refreshStatus: refreshStatus,
    explicitEditsOnly: explicitEditsOnly,
    officialOnly: officialOnly,
    onlyCommunity: onlyCommunity,
    keepDraft: keepDraft,
  );

  Future<bool> _save({
    bool refreshStatus = true,
    bool explicitEditsOnly = false,
    bool officialOnly = false,
    String? onlyCommunity,
    bool keepDraft = false,
    bool requireAppliedPublication = false,
    bool firstOfficialDefault = false,
  }) async {
    if (!canSave || draft == null) return false;
    final epoch = _epoch;
    final kept = draft!, keptSaved = _snapshot?.settings;
    final scoped = keepDraft || onlyCommunity != null;
    // Bind the saved legacy Fleet grant before replacing one community.
    final base = onlyCommunity != null && keptSaved != null
        ? bindCommunityChoices(keptSaved)
        : keptSaved;
    if (onlyCommunity != null &&
        keptSaved != null &&
        base?.communities == null) {
      errorKey = 'privacy.local.readFailed';
      notifyListeners();
      return false;
    }
    // Partial page saves must not turn untouched first-use suggestions into
    // consent or grants. Reuse the same field-level rebase as scoped saves.
    final ordinaryDraft = explicitEditsOnly
        ? rebaseFirstPrivacyEdits(emptyPrivacySettings, kept, keptSaved)
        : kept;
    final submitted = scopedPrivacySubmission(
      ordinaryDraft,
      base,
      onlyCommunity,
    );
    final submittedOfficial = officialSubmitRequired && onlyCommunity == null
        ? officialScope
        : null;
    final submittedFields = officialDraftFields;
    final cancelOfficial = officialCancelSavedScope;
    final audience = _official.submitAudience;
    final officialEpoch = _official.epoch;
    if (officialOnly &&
        (submittedOfficial == null || _ordinaryDirty && !keepDraft)) {
      return false;
    }
    final saveOrdinary =
        !officialOnly && (submittedOfficial == null || _ordinaryDirty);
    bool committedOrdinary = false,
        sentOfficial = false,
        committedOfficial = false;
    final saveToken = Object();
    _saveToken = saveToken;
    saving = true;
    errorKey = null;
    if (submittedOfficial != null) {
      _official.stage = OfficialPrivacySaveStage.savingSettings;
    }
    notifyListeners();
    bool currentSave() =>
        _current(epoch) &&
        identical(_saveToken, saveToken) &&
        (submittedOfficial == null || officialEpoch == _official.epoch);
    try {
      // Serialize writes after the read that retires the old revision grant.
      final settingsRead = _settingsReadDone;
      final publicationRead = _publicationReadDone;
      if (settingsRead != null) await settingsRead.future;
      if (publicationRead != null) await publicationRead.future;
      if (!currentSave() || needsReload || status != LocalPrivacyStatus.ready) {
        return false;
      }
      if (saveOrdinary) {
        final result = await _port.save(submitted);
        if (!currentSave()) return false;
        _snapshot = result;
        draft = keepEdits(result.settings, kept, keptSaved, onlyCommunity);
        committedOrdinary = true;
      }
      if (submittedOfficial != null) {
        _official.stage = OfficialPrivacySaveStage.savingOfficial;
        notifyListeners();
        sentOfficial = true;
        final receipt = await (_port as OfficialRuntimePrivacyPort)
            .saveOfficialRuntimePrivacy(
              scope: submittedOfficial,
              expectedRevision: revision,
              fields: submittedFields!,
              cancelSavedScope: cancelOfficial,
              audience: audience,
            );
        if (!currentSave()) return false;
        committedOfficial = true;
        _official.stage = OfficialPrivacySaveStage.localSaved;
        notifyListeners();
        _official.stage = OfficialPrivacySaveStage.renewingLease;
        final result = await _port.read();
        if (!currentSave()) return false;
        if (result.revision != receipt.revision || result.settings == null) {
          throw const FormatException('Unconfirmed common privacy lease.');
        }
        final scope = await (_port as OfficialRuntimePrivacyPort)
            .readOfficialRuntimePrivacy();
        if (!currentSave()) return false;
        if (scope.revision != receipt.revision ||
            scope.savedFields != receipt.fields ||
            audience != null &&
                scope.maximumRankValue != audience.maximumRankValue ||
            !cancelOfficial &&
                (scope.scopeRef != submittedOfficial.scopeRef ||
                    scope.sourceRef != submittedOfficial.sourceRef ||
                    !scope.savedForCurrentSource ||
                    scope.fields != receipt.fields)) {
          throw const BridgeClientException('privacy_local.changed');
        }
        _snapshot = result;
        draft = keepDraft
            ? rebaseFirstPrivacyEdits(result.settings!, kept, keptSaved)
            : result.settings;
        _official.acceptSaved(scope);
      }
      saving = false;
      notifyListeners();
      // Only explicit automatic defaults may request first consent from Host.
      bool publicationApplied = false;
      if (refreshStatus) {
        if (officialOnly || onlyCommunity != null) {
          if (publicationSupported &&
              savedPublicationEnabled &&
              publicationObserved &&
              publicationReadFailures == 0 &&
              publicationView.allowsOrganizationApply(
                firstDefault: firstOfficialDefault,
              )) {
            if (submittedOfficial != null) {
              _official.stage = OfficialPrivacySaveStage.applying;
            }
            final applied = await _publication(
              'applyPreservingPause',
              ignoreDraft: scoped,
              firstOfficialDefault: firstOfficialDefault,
            );
            publicationApplied =
                currentSave() && applied?.confirmsSharing(revision) == true;
          }
        } else {
          if (submittedOfficial != null) {
            _official.stage = OfficialPrivacySaveStage.applying;
          }
          if (publicationSupported && submitted.publicationEnabled) {
            await _publication('apply', ignoreDraft: scoped);
          } else if (publicationSupported) {
            await stopPublication();
          }
        }
      }
      if (submittedOfficial != null && currentSave()) {
        _official.completeSave(
          refreshStatus && publicationObserved ? publicationView : null,
          revision,
        );
      }
      if (submittedOfficial != null && !currentSave()) return false;
      return !(firstOfficialDefault || requireAppliedPublication) ||
          publicationApplied;
    } catch (error) {
      if (!_current(epoch)) return false;
      saving = false;
      if (LocalPrivacyController._accountError(error)) {
        _snapshot = null;
        draft = null;
        status = LocalPrivacyStatus.signedOut;
        errorKey = 'privacy.local.accountChanged';
      } else {
        needsReload =
            error is BridgeClientException &&
            const {
              'privacy_local.conflict',
              'privacy_local.refresh_required',
            }.contains(error.code);
        errorKey = needsReload
            ? 'privacy.local.conflict'
            : 'privacy.local.saveFailed';
      }
      if (submittedOfficial != null) {
        _official.failSave(
          error,
          committedOfficial: committedOfficial,
          committedOrdinary: committedOrdinary,
          sentOfficial: sentOfficial,
        );
        needsReload = true;
      }
      notifyListeners();
      return false;
    } finally {
      if (identical(_saveToken, saveToken)) {
        _saveToken = null;
        saving = false;
        notifyListeners();
      }
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  static bool _accountError(Object error) =>
      error is BridgeClientException &&
      const {
        'privacy_local.account_changed',
        'privacy_publication.account_changed',
        'bridge.stale_generation',
      }.contains(error.code);

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _saveToken = null;
    _finishBackgroundReads();
    _stopPublicationMonitoring();
    _targetsTimer?.cancel();
    unawaited(_subscription.cancel());
    _official.retire(saving: false);
    unawaited(_officialSubscription?.cancel());
    unawaited(_port.close());
    super.dispose();
  }
}
