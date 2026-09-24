import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import 'local_privacy_port.dart';
import 'local_privacy_settings.dart';
import 'privacy_publication_port.dart';
import 'community_sharing.dart';
import 'community_member_sharing.dart';

enum LocalPrivacyStatus { initial, loading, ready, unavailable, signedOut }

enum CommunityTargetsFailure { none, serviceUnavailable, retryable }

/// Owns one account's draft; invalidation discards it before any new read starts.
final class LocalPrivacyController extends ChangeNotifier {
  LocalPrivacyController(this._port) {
    _subscription = _port.invalidations.listen((_) {
      _epoch++;
      _snapshot = null;
      draft = null;
      saving = false;
      errorKey = null;
      publicationView = const PrivacyPublicationView('inactive');
      publicationObserved = false;
      publicationBusy = false;
      status = LocalPrivacyStatus.initial;
      communityTargets = null;
      _pendingTargetNames.clear();
      communityTargetsFailed = false;
      communityTargetsFailure = CommunityTargetsFailure.none;
      _targetsReading = false;
      _settingsReading = false;
      notifyListeners();
      if (_opened || _publicationMonitors > 0) unawaited(refresh());
    });
  }
  final LocalPrivacyPort _port;
  bool get locationConfidenceSupported =>
      _port is LocationConfidencePrivacyPort &&
      (_port as LocationConfidencePrivacyPort).locationConfidenceSupported;
  late final StreamSubscription<void> _subscription;
  LocalPrivacySnapshot? _snapshot;
  LocalPrivacySettings? draft;
  LocalPrivacyStatus status = LocalPrivacyStatus.initial;
  String? errorKey;
  bool saving = false;
  bool needsReload = false;
  bool _opened = false;
  bool _disposed = false;
  CommunitySharingTargets? communityTargets;
  final _pendingTargetNames = <String, String>{};
  void renameCommunity(String code, String name) {
    if (_disposed) return;
    if (_targetsReading) _pendingTargetNames[code] = name;
    communityTargets = communityTargets?.renamed(code, name);
    notifyListeners();
  }

  bool communityTargetsFailed = false;
  CommunityTargetsFailure communityTargetsFailure =
      CommunityTargetsFailure.none;
  bool _targetsReading = false;
  bool _settingsReading = false;
  int _memberReads = 0;
  bool get communitySharingSupported =>
      _port is CommunitySharingPort &&
      (_port as CommunitySharingPort).communitySharingSupported;
  int _epoch = 0;
  Timer? _publicationTimer;
  Timer? _targetsTimer;
  bool publicationBusy = false;
  bool publicationObserved = false;
  int _publicationMonitors = 0;
  bool get savedPublicationEnabled =>
      _snapshot?.settings?.publicationEnabled == true;
  PrivacyPublicationView publicationView = const PrivacyPublicationView(
    'inactive',
  );
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

    // A revision race restarts the whole snapshot once; never mix two rosters.
    for (var attempt = 0; attempt < 2; attempt++) {
      final rows = <CommunitySharingMember>[];
      String? revision;
      try {
        do {
          requireCurrent();
          final page = await (_port as CommunityMemberSharingPort)
              .readCommunityMembers(
                scope,
                offset: rows.length,
                revision: revision,
              );
          requireCurrent();
          revision = page.revision;
          rows.addAll(page.members);
          if (rows.length == page.total) {
            if (rows.map((row) => row.accountId.toLowerCase()).toSet().length !=
                rows.length) {
              throw const FormatException('Duplicate members across pages.');
            }
            return List.unmodifiable(rows);
          }
        } while (rows.length < 100000);
        throw const FormatException('Member directory exceeds limit.');
      } on BridgeClientException catch (error) {
        if (error.code != 'privacy_publication.members_changed' ||
            attempt == 1) {
          rethrow;
        }
      }
    }
    throw const FormatException('Member directory changed.');
  }

  bool get hasSaved => _snapshot?.settings != null;
  bool get canEdit =>
      status == LocalPrivacyStatus.ready &&
      !saving &&
      !_settingsReading &&
      !needsReload &&
      !publicationBusy;
  bool get dirty =>
      draft != null &&
      jsonEncode(draft!.toJson()) !=
          jsonEncode(
            (_snapshot?.settings ?? LocalPrivacySettings.editorDefaults)
                .toJson(),
          );
  bool get canSave =>
      canEdit &&
      (dirty ||
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
      if (status == LocalPrivacyStatus.unavailable && draft == null) {
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
    if (_publicationMonitors == 0) {
      _publicationTimer?.cancel();
      _publicationTimer = null;
    }
    _targetsTimer?.cancel();
    _targetsTimer = null;
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
      if (!_opened && _publicationMonitors == 0) {
        _publicationTimer?.cancel();
        _publicationTimer = null;
      }
    };
  }

  void _startPublicationTimer() {
    if (!publicationSupported) return;
    _publicationTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed) return;
      if (status == LocalPrivacyStatus.initial ||
          status == LocalPrivacyStatus.unavailable) {
        unawaited(refresh());
      } else {
        unawaited(refreshPublication());
      }
    });
  }

  Future<void> refresh({bool silently = false}) async {
    if (_disposed || saving || publicationBusy || _settingsReading) return;
    if (silently &&
        (status != LocalPrivacyStatus.ready ||
            dirty ||
            _targetsReading ||
            _memberReads > 0)) {
      return;
    }
    var epoch = silently ? _epoch : ++_epoch;
    _settingsReading = true;
    _targetsReading = false;
    if (!silently) {
      publicationObserved = false;
      status = LocalPrivacyStatus.loading;
      draft = null;
      _snapshot = null;
    }
    errorKey = null;
    needsReload = false;
    notifyListeners();
    try {
      final result = await _port.read();
      if (!_current(epoch)) return;
      // Unchanged lease renewal must not invalidate an open confirmation.
      if (silently && result.revision != _snapshot?.revision) {
        epoch = ++_epoch;
      }
      _snapshot = result;
      draft = result.settings ?? LocalPrivacySettings.editorDefaults;
      status = LocalPrivacyStatus.ready;
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
    }
    notifyListeners();
    if (status == LocalPrivacyStatus.ready) {
      await refreshPublication();
      await refreshCommunityTargets();
    }
  }

  Future<void> refreshCommunityTargets() async {
    if (_disposed ||
        !communitySharingSupported ||
        _settingsReading ||
        _targetsReading ||
        status != LocalPrivacyStatus.ready) {
      return;
    }
    final epoch = _epoch;
    _targetsReading = true;
    _pendingTargetNames.clear();
    try {
      final result = await (_port as CommunitySharingPort)
          .readCommunityTargets();
      if (!_current(epoch)) return;
      communityTargets = result;
      for (final entry in _pendingTargetNames.entries) {
        communityTargets = communityTargets!.renamed(entry.key, entry.value);
      }
      communityTargetsFailed = false;
      communityTargetsFailure = CommunityTargetsFailure.none;
    } catch (error) {
      if (_current(epoch)) {
        communityTargetsFailed = true;
        communityTargetsFailure =
            error is BridgeClientException &&
                error.code == 'privacy_publication.community_scopes_unavailable'
            ? CommunityTargetsFailure.serviceUnavailable
            : CommunityTargetsFailure.retryable;
      }
    } finally {
      if (_current(epoch)) {
        _targetsReading = false;
        notifyListeners();
      }
    }
  }

  /// Explicitly bind legacy organization choices to their current membership.
  /// The closed main-fleet feature is separate and receives no authority here.
  LocalPrivacySettings bindCommunityChoices(
    LocalPrivacySettings value, {
    bool preserveExistingOrganizationChoice = true,
  }) {
    final targets = communityTargets;
    if (value.communities != null ||
        targets == null ||
        communityTargetsFailed) {
      return value;
    }
    final primary = targets.communities
        .where((t) => t.code == targets.primaryFleetCode)
        .firstOrNull;
    return value.copyWith(
      communities: [
        if (primary != null && preserveExistingOrganizationChoice)
          CommunitySharingScope(
            code: primary.code,
            joinedAt: primary.joinedAt,
            fields: value.fleetFields & 15,
            administratorsCanView: value.fleetAdministratorsCanView,
            allMembersCanView: value.fleetAllMembersCanView,
            visibilityGroupIds: value.fleetVisibilityGroupIds,
          ),
      ],
    );
  }

  void enableCommunityChoices() {
    if (canEdit) {
      edit(
        bindCommunityChoices(
          draft!,
          preserveExistingOrganizationChoice: hasSaved,
        ),
      );
    }
  }

  void editCommunity(CommunitySharingScope value) {
    if (!canEdit ||
        draft?.communities == null ||
        communityTargetsFailed ||
        !(communityTargets?.communities.any((t) => t.matches(value)) ??
            false)) {
      return;
    }
    edit(
      draft!.copyWith(
        communities: [
          ...draft!.communities!.where(
            (s) =>
                s.code.toLowerCase() != value.code.toLowerCase() &&
                communityTargets!.communities.any((t) => t.matches(s)),
          ),
          value,
        ],
      ),
    );
  }

  List<CommunitySharingTarget> get unconfirmedCommunities =>
      draft?.communities == null || communityTargetsFailed
      ? const []
      : (communityTargets?.communities ?? const [])
            .where((target) => !draft!.communities!.any(target.matches))
            .toList();

  Future<void> refreshPublication() => _publication('status');
  Future<void> applyPublication() => _publication('apply');
  Future<void> stopPublication() => _publication('stop');
  Future<void> _publication(String action) async {
    if (_disposed ||
        !publicationSupported ||
        publicationBusy ||
        _settingsReading ||
        saving ||
        status != LocalPrivacyStatus.ready ||
        (action == 'apply' && (dirty || !hasSaved || needsReload))) {
      return;
    }
    final epoch = _epoch;
    publicationBusy = true;
    if (action != 'status') notifyListeners();
    try {
      final result = await (_port as PrivacyPublicationPort).publication(
        action,
        revision: revision,
      );
      if (_current(epoch)) {
        publicationView = result;
        publicationObserved = true;
      }
    } catch (error) {
      if (_current(epoch)) {
        publicationObserved = true;
        publicationView = PrivacyPublicationView(
          'failed',
          errorCode: error is BridgeClientException ? error.code : null,
        );
      }
    } finally {
      if (_current(epoch)) {
        publicationBusy = false;
        notifyListeners();
      }
    }
  }

  void edit(LocalPrivacySettings value) {
    if (!canEdit) return;
    draft = value;
    errorKey = null;
    notifyListeners();
  }

  void discard() {
    if (_disposed || saving || _settingsReading) return;
    draft = _snapshot == null
        ? null
        : _snapshot!.settings ?? LocalPrivacySettings.editorDefaults;
    errorKey = needsReload ? 'privacy.local.conflict' : null;
    notifyListeners();
  }

  Future<bool> save({bool refreshStatus = true}) async {
    if (!canSave || draft == null) return false;
    final epoch = _epoch;
    final submitted = draft!;
    saving = true;
    errorKey = null;
    notifyListeners();
    try {
      final result = await _port.save(submitted);
      if (!_current(epoch)) return false;
      _snapshot = result;
      draft = result.settings;
      saving = false;
      notifyListeners();
      // Saving the visible master switch is the explicit sharing action. Do not
      // require another Apply button, or infer consent from background reads.
      if (refreshStatus) {
        if (publicationSupported && submitted.publicationEnabled) {
          await applyPublication();
        } else if (publicationSupported) {
          await stopPublication();
        }
      }
      return true;
    } catch (error) {
      if (!_current(epoch)) return false;
      saving = false;
      if (_accountError(error)) {
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
      notifyListeners();
      return false;
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  static bool _accountError(Object error) =>
      error is BridgeClientException &&
      const {
        'privacy_local.account_changed',
        'bridge.stale_generation',
      }.contains(error.code);

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _publicationTimer?.cancel();
    _targetsTimer?.cancel();
    unawaited(_subscription.cancel());
    unawaited(_port.close());
    super.dispose();
  }
}
