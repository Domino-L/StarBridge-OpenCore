import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../common/organization_hangar_sharing.dart';
import '../common/organization_ship_image_features.dart';
import '../onboarding/connection_mode_port.dart';
import '../communities/communities_module.dart';
import '../communities/community_hangar_sharing_port.dart';

/// Private owner editor only. Public ships and holder identity have independent
/// authorized adapters. Native Host retains all instance IDs and authority facts.
final class BridgeOfficialFleetHangarSharing
    implements
        OrganizationHangarSharingPort,
        OrganizationHangarImageConsentPort {
  BridgeOfficialFleetHangarSharing(this.session, {this.connectionMode}) {
    connectionMode?.addListener(_modeChanged);
    _removeNetwork = session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async {
          _invalidate();
          await _cancelPending();
        },
        reconcile: () async {},
      ),
    );
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _invalidate();
      }
    }, onDone: _invalidate);
    _unobserve = session.observeGenerationChanges((_, _) => _invalidate());
    _capabilityKey = _currentCapabilityKey;
    _capabilities = session.capabilitiesChanged.listen((_) {
      final next = _currentCapabilityKey;
      if (next == _capabilityKey) return;
      _capabilityKey = next;
      _invalidate();
    });
  }
  final BridgeClientSession session;
  final ConnectionModeControl? connectionMode;
  final _pending = <BridgeRequestOperation>{};
  late final void Function() _removeNetwork;
  (Object, int?, ConnectionModeState, bool)? _modeKey;
  void _modeChanged() {
    final mode = connectionMode;
    if (mode == null) return;
    final next = (
      mode.snapshot.scope,
      mode.snapshot.revision,
      mode.snapshot.state,
      mode.allowsOnlineTraffic,
    );
    if (next != _modeKey) {
      _modeKey = next;
      _invalidate();
    }
  }

  Future<void> _cancelPending() =>
      Future.wait(_pending.toList().map((operation) => operation.cancel()));
  Future<BridgeEnvelope> _send(
    String name,
    Map<String, Object?> payload, {
    BridgeAccountContext? accountContext,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final operation = session.beginRequest(
      name,
      accountContext: accountContext,
      payload: payload,
      timeout: timeout,
    );
    _pending.add(operation);
    return operation.future.whenComplete(() => _pending.remove(operation));
  }

  final _changes = StreamController<void>.broadcast();
  final _edits = <String, (BridgeAccountContext, int, String?, bool, bool)>{};
  late final StreamSubscription<void> _capabilities;
  String _capabilityKey = '';
  String get _currentCapabilityKey => [
    _read,
    _page,
    _save,
    ...OrganizationShipImageFeatures.callableNames,
  ].where(session.hostCapabilities.contains).join('|');
  bool get _imageProtocol => OrganizationShipImageFeatures.callableNames.every(
    session.hostCapabilities.contains,
  );
  late final StreamSubscription<BridgeEnvelope> _events;
  late final void Function() _unobserve;
  bool _closed = false;
  int _epoch = 0;
  static const _read = 'officialFleet.hangarSharing',
      _page = 'officialFleet.hangarSharingPage',
      _save = 'officialFleet.saveHangarSharing';
  @override
  Stream<void> get invalidations => _changes.stream;
  @override
  bool get available =>
      !_closed &&
      [_read, _page, _save].every(session.hostCapabilities.contains);
  void _invalidate() {
    _epoch++;
    _edits.clear();
    if (!_closed) _changes.add(null);
  }

  Future<(BridgeAccountContext, int, int)> _account() async {
    if (!available ||
        session.connectionModeChanging ||
        connectionMode?.allowsOnlineTraffic == false) {
      throw const CommunityFailure('unavailable');
    }
    final epoch = _epoch, generation = session.activeGeneration;
    final value = await _send('account.getCurrent', const {'schemaVersion': 1});
    if (_closed ||
        epoch != _epoch ||
        generation != session.activeGeneration ||
        value.sessionGeneration != generation ||
        value.payload['schemaVersion'] != 1 ||
        value.payload['state'] != 'signedIn' ||
        value.accountContext == null) {
      throw const CommunityFailure('identityUnavailable');
    }
    return (value.accountContext!, generation, epoch);
  }

  bool _same(BridgeAccountContext a, BridgeAccountContext b) =>
      a.environment == b.environment &&
      a.authority == b.authority &&
      a.subject == b.subject;
  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> body,
    (BridgeAccountContext, int, int) scope, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (session.connectionModeChanging ||
        connectionMode?.allowsOnlineTraffic == false) {
      throw const CommunityFailure('unavailable');
    }
    final value = await _send(
      name,
      {'schemaVersion': 1, ...body},
      accountContext: scope.$1,
      timeout: timeout,
    );
    if (_closed ||
        scope.$3 != _epoch ||
        scope.$2 != session.activeGeneration ||
        value.sessionGeneration != scope.$2 ||
        value.accountContext == null ||
        !_same(scope.$1, value.accountContext!)) {
      throw const CommunityFailure('identityUnavailable');
    }
    return value.payload;
  }

  @override
  Future<OrganizationSharingDraft> read(
    String? sourceRef, {
    String? scopeRef,
  }) async {
    final scope = await _account();
    final draft = OrganizationSharingDraft.parseOfficial(
      await _request(_read, {
        'sourceRef': ?sourceRef,
        'scopeRef': ?scopeRef,
      }, scope),
      imageProtocolSupported: _imageProtocol,
    );
    // An authorized old scope may differ from the currently displayed fleet.
    _edits.clear();
    _edits[draft.editRef] = (
      scope.$1,
      scope.$2,
      draft.sourceRef,
      draft.allowImages,
      draft.canClearImages,
    );
    return draft;
  }

  @override
  Future<OrganizationSharingPage> page(
    String editRef,
    String sourceRef,
    int offset,
  ) async {
    final scope = await _account(), edit = _edits[editRef];
    if (edit == null ||
        edit.$2 != scope.$2 ||
        !_same(edit.$1, scope.$1) ||
        edit.$3 != sourceRef) {
      throw const CommunityFailure('refreshRequired');
    }
    final value = OrganizationSharingPage.parse(
      await _request(_page, {
        'editRef': editRef,
        'sourceRef': sourceRef,
        'offset': offset,
      }, scope),
    );
    if (value.editRef != editRef || value.offset != offset) {
      throw const FormatException();
    }
    return value;
  }

  @override
  Future<CommunityHangarSharingOutcome> save(
    String editRef,
    String? sourceRef,
    String? strategy,
    List<String> selectedRefs, {
    bool includeImages = false,
  }) async {
    final refs = List<String>.of(selectedRefs);
    if (!validOrganizationSharingReference(editRef) ||
        !const {
          'notShared',
          'organizationPool',
          'operationOnly',
        }.contains(strategy) ||
        refs.length > 10000 ||
        refs.any((v) => !validOrganizationSharingReference(v)) ||
        refs.toSet().length != refs.length ||
        strategy != 'organizationPool' && refs.isNotEmpty) {
      return const CommunityHangarSharingOutcome(
        'rejected',
        error: 'invalidDraft',
      );
    }
    var sent = false;
    try {
      final scope = await _account(), edit = _edits[editRef];
      if (edit == null ||
          edit.$2 != scope.$2 ||
          !_same(edit.$1, scope.$1) ||
          edit.$3 != sourceRef ||
          includeImages &&
              (!_imageProtocol ||
                  !edit.$4 ||
                  strategy != 'organizationPool' ||
                  refs.isEmpty)) {
        return const CommunityHangarSharingOutcome(
          'rejected',
          error: 'refreshRequired',
        );
      }
      // Never replay an editor after a timeout,401 or uncertain response.
      _edits.remove(editRef);
      sent = true;
      return CommunityHangarSharingOutcome.parse(
        await _request(
          _save,
          {
            'editRef': editRef,
            'sourceRef': sourceRef,
            'strategy': strategy,
            'selectedRefs': refs,
            if (includeImages) 'includeImages': true,
          },
          scope,
          timeout: includeImages
              ? const Duration(seconds: 15)
              : const Duration(seconds: 45),
        ),
      );
    } catch (_) {
      return CommunityHangarSharingOutcome(
        sent ? 'unknown' : 'rejected',
        error: sent ? 'outcomeUnknown' : 'identityUnavailable',
      );
    }
  }

  @override
  Future<CommunityHangarSharingOutcome> clearImages(
    String editRef,
    String sourceRef,
  ) async {
    var sent = false;
    try {
      final scope = await _account(), edit = _edits[editRef];
      if (!_imageProtocol ||
          edit == null ||
          !edit.$5 ||
          edit.$2 != scope.$2 ||
          !_same(edit.$1, scope.$1) ||
          edit.$3 != sourceRef) {
        return const CommunityHangarSharingOutcome(
          'rejected',
          error: 'refreshRequired',
        );
      }
      _edits.remove(editRef);
      sent = true;
      return CommunityHangarSharingOutcome.parse(
        await _request(
          _save,
          {'sourceRef': sourceRef, 'editRef': editRef, 'kind': 'clearImages'},
          scope,
          timeout: const Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return CommunityHangarSharingOutcome(
        sent ? 'unknown' : 'rejected',
        error: sent ? 'outcomeUnknown' : 'identityUnavailable',
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _edits.clear();
    _unobserve();
    _removeNetwork();
    connectionMode?.removeListener(_modeChanged);
    await _cancelPending();
    await _events.cancel();
    await _capabilities.cancel();
    await _changes.close();
  }
}
