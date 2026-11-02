import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../shared/downloadable_image_cache.dart';
import '../../shared/diagnostics/loading_read_scope.dart';
import 'communities_module.dart';
import 'community_creation_port.dart';
import 'community_logo_port.dart';
import 'community_wide_image_port.dart';
import 'community_image_data.dart';
import 'community_workspace_port.dart';
import 'community_directory_metadata_port.dart';
import 'community_visitor_profile_port.dart';
import 'community_cached_presentation_port.dart';
import 'offline_community_reader.dart';
import '../personal_profile/bridge_personal_profile_adapter.dart';
import '../personal_profile/personal_profile_models.dart';

import 'community_bridge_transport.dart';
import 'community_bridge_communication.dart';
import 'community_bridge_management.dart';
import 'community_bridge_hangar.dart';

final class BridgeCommunities extends CommunityBridgeTransport
    with
        CommunityBridgeCommunication,
        CommunityBridgeManagement,
        CommunityBridgeHangar
    implements
        DownloadableImageCache,
        CommunityVisitorProfilePort,
        CommunityCreationPort,
        CommunityLogoPort,
        CommunityWideImagePort,
        CommunityDirectoryMetadataPort,
        CommunityProgressiveDirectoryPort,
        CommunityCachedPresentationPort,
        CommunityWorkspacePort {
  BridgeCommunities(
    super.session, {
    super.ownAvatar,
    super.connectionMode,
    this.retainedReadId,
    this.retainedPreviousReadId,
    this.retainedSelectionChanges,
  }) {
    _selection = (session.activeGeneration, retainedReadId?.call());
    retainedSelectionChanges?.addListener(_selectionChanged);
  }
  final String? Function()? retainedReadId;
  final String? Function()? retainedPreviousReadId;
  final Listenable? retainedSelectionChanges;
  int _imageEpoch = 0;
  bool _imagesPaused = false;
  @override
  void beginImageMaintenance() {
    _imagesPaused = true;
    _imageEpoch++;
  }

  @override
  void endImageMaintenance() {
    _imageEpoch++;
    _imagesPaused = false;
  }

  late (int, String?) _selection;
  final _selectionChanges =
      StreamController<CommunityCachedSelectionChange>.broadcast(sync: true);
  void _selectionChanged() {
    if (isClosed) return;
    final next = (session.activeGeneration, retainedReadId?.call());
    final previous = _selection;
    if (next == previous) return;
    _selection = next;
    // Explicit offline reads belong to the mode revision, not this descriptor.
    if (connectionMode?.allowsOnlineTraffic == false) return;
    final retained = next.$2 != null;
    final renewal =
        retained &&
        next.$1 == previous.$1 &&
        previous.$2 != null &&
        retainedPreviousReadId?.call() == previous.$2;
    invalidateReadScope(notify: !retained);
    if (retained) {
      _selectionChanges.add(
        renewal
            ? CommunityCachedSelectionChange.renew
            : CommunityCachedSelectionChange.replace,
      );
    }
  }

  late final _offline = OfflineCommunityReader(
    session,
    mode: connectionMode,
    retainedReadId: retainedReadId,
    epoch: () => requestEpoch,
    request: readLocalDisplay,
  );
  @override
  Stream<CommunityCachedLogo> get cachedLogoChanges => _offline.changes.stream;
  @override
  Stream<CommunityCachedSelectionChange> get cachedSelectionChanges =>
      _selectionChanges.stream;
  @override
  Future<void> close() async {
    retainedSelectionChanges?.removeListener(_selectionChanged);
    await super.close();
    await _offline.close();
    await _selectionChanges.close();
  }

  @override
  bool get visitorProfilesAvailable =>
      !isClosed &&
      session.hostCapabilities.contains('communities.memberPersonalProfile');

  @override
  Future<PersonalProfileSnapshot> readMemberPersonalProfile(
    String targetRef,
    String memberRef,
  ) async {
    try {
      final payload = await sendRequest('communities.memberPersonalProfile', {
        'targetRef': targetRef,
        'memberRef': memberRef,
      });
      if (payload['editable'] != false) throw const FormatException();
      return parsePersonalProfileSnapshot(payload);
    } on BridgeClientException catch (error) {
      return PersonalProfileSnapshot.unavailable(
        failureKey: switch (error.code) {
          'profile.visitor_not_visible' => 'profile.visitor.notVisible',
          'communities.refreshRequired' => 'profile.visitor.refreshMembers',
          _ => 'profile.error.unavailable',
        },
      );
    } on Object {
      return const PersonalProfileSnapshot.unavailable();
    }
  }

  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) => _readDirectory(
    view: view,
    query: query,
    after: after,
    filters: filters,
    hydrateLogos: true,
  );

  @override
  Future<CommunityDirectory> readDirectoryMetadata({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) => _readDirectory(
    view: view,
    query: query,
    after: after,
    filters: filters,
    hydrateLogos: false,
  );

  @override
  Future<CommunityDirectoryRead> readDirectoryProgressively({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) {
    final ready = Completer<CommunityDirectoryRead>();
    // Single-subscription: buffers logos that arrive before the owner listens.
    final progress = StreamController<CommunityDirectory>();
    var wanted = true;
    // _readDirectory awaits its existing offline/admission path before this
    // callback can run; the original physical completion is already assigned.
    late final Future<CommunityDirectory> completion;
    completion = _readDirectory(
      view: view,
      query: query,
      after: after,
      filters: filters,
      hydrateLogos: true,
      imagesWanted: () => wanted,
      logoArrived: progress.add,
      metadataReady: (page) => ready.complete(
        CommunityDirectoryRead(
          page,
          images: completion,
          progress: progress.stream,
          retireImages: () => wanted = false,
        ),
      ),
    );
    unawaited(
      completion
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(progress.close),
    );
    unawaited(
      completion.then(
        (page) {
          // Cached/paused paths already return without waiting for online logos.
          if (!ready.isCompleted) ready.complete(CommunityDirectoryRead(page));
        },
        onError: (Object error, StackTrace stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      ),
    );
    return ready.future;
  }

  Future<CommunityDirectory> _readDirectory({
    required String view,
    required String query,
    String? after,
    String? filters,
    required bool hydrateLogos,
    void Function(CommunityDirectory)? metadataReady,
    void Function(CommunityDirectory)? logoArrived,
    bool Function()? imagesWanted,
  }) async {
    final epoch = requestEpoch;
    final imageEpoch = _imageEpoch;
    bool imagesCurrent() =>
        !_imagesPaused &&
        imageEpoch == _imageEpoch &&
        (imagesWanted?.call() ?? true);
    void current() {
      if (isClosed || epoch != requestEpoch) {
        throw const CommunityFailure('identityUnavailable');
      }
    }

    try {
      final cached = await _offline.read(
        view: view,
        query: query,
        after: after,
        filters: filters,
        hydrate: hydrateLogos,
        imagesCurrent: imagesCurrent,
      );
      if (cached != null) {
        return imagesCurrent() ? cached : cached.withoutDownloadedLogos();
      }
      final value = await sendRequest('communities.read', {
        'view': view,
        'query': query,
        'after': ?after,
        'filters': ?filters,
      });
      final result = parseCommunityDirectory(value);
      if (result.view != view || result.query != query.trim()) {
        throw const FormatException();
      }
      current();
      if (!imagesCurrent()) return result.withoutDownloadedLogos();
      if (!hydrateLogos) return result;
      final rows = (value['items'] as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      if (!rows.any((row) => row['logoDeferred'] == true)) return result;
      var next = 0;
      Future<void> loadLogos() async {
        while (next < rows.length) {
          current();
          if (!imagesCurrent()) return;
          final index = next++;
          final row = rows[index];
          if (row['logoDeferred'] != true) continue;
          try {
            String? mime;
            final bytes = await assembleCommunityMedia(
              (offset, version) async {
                current();
                if (!imagesCurrent()) throw StateError('Retired image read');
                final chunk = await readMedia(
                  result.items[index].targetRef,
                  'logo',
                  offset: offset,
                  version: version,
                );
                mime = chunk['mimeType'] as String?;
                return chunk;
              },
              'logo',
              checkCurrent: () {
                current();
                if (!imagesCurrent()) throw StateError('Retired image read');
              },
            );
            current();
            row['logoImageData'] = 'data:$mime;base64,${base64Encode(bytes)}';
            if (logoArrived != null && imagesCurrent()) {
              logoArrived(parseCommunityDirectory({...value, 'items': rows}));
            }
          } on Object {
            // One unavailable/corrupt image must not discard a directory page.
            current();
            row['logoImageData'] = null;
          }
        }
      }

      Future<CommunityDirectory> hydrate() async {
        // Bound parallel Bridge work; all chunks remain account/epoch guarded.
        await Future.wait(List.generate(3, (_) => loadLogos()));
        current();
        final hydrated = parseCommunityDirectory({...value, 'items': rows});
        return imagesCurrent() ? hydrated : hydrated.withoutDownloadedLogos();
      }

      if (metadataReady != null) {
        metadataReady(result);
        return await backgroundLoadingRead(hydrate);
      }
      return await hydrate();
    } on BridgeClientException catch (e) {
      throw CommunityFailure(switch (e.code) {
        'account.local_mode' => 'onlinePaused',
        'communities.upgradeRequired' => 'upgradeRequired',
        'communities.refreshRequired' => 'refreshRequired',
        'communities.identityUnavailable' ||
        'account.reauthorization_required' => 'identityUnavailable',
        'communities.dataInvalid' => 'dataInvalid',
        'communities.notAllowed' => 'notAllowed',
        'communities.readTransient' => 'readTransient',
        _ => 'unavailable',
      });
    } on FormatException {
      throw const CommunityFailure('dataInvalid');
    }
  }

  @override
  Future<String> execute(String action, String targetRef) async {
    try {
      final value = await sendRequest('communities.execute', {
        'action': action,
        'targetRef': targetRef,
      });
      final status = value['status'];
      return const {'accepted', 'rejected', 'unknown'}.contains(status)
          ? status as String
          : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) => workspaceRead(() async {
    final result = CommunityWorkspace.parse(
      await sendRequest('communities.workspace', {
        'targetRef': targetRef,
        'query': query.trim(),
        'offset': offset,
      }),
    );
    if (result.targetRef != targetRef ||
        result.query != query.trim() ||
        result.offset != offset) {
      throw const FormatException();
    }
    return result;
  });

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) => workspaceRead(
    () => sendRequest('communities.media', {
      'targetRef': targetRef,
      'kind': kind,
      'memberRef': ?memberRef,
      'offset': offset,
      'version': ?version,
    }),
    media: true,
  );

  @override
  Future<CommunityCreationOptions> creationOptions() async {
    try {
      return CommunityCreationOptions.parse(
        await sendRequest('communities.creationOptions', const {}),
      );
    } on FormatException {
      throw const CommunityFailure('dataInvalid');
    } on TypeError {
      throw const CommunityFailure('dataInvalid');
    } on BridgeClientException catch (e) {
      throw CommunityFailure(
        e.code == 'account.reauthorization_required'
            ? 'identityUnavailable'
            : 'unavailable',
      );
    }
  }

  @override
  Future<CommunityCreationOutcome> createCommunity(
    String requestId,
    Map<String, Object?> draft,
  ) async {
    try {
      final result = await sendRequest('communities.create', {
        'requestId': requestId,
        'draft': draft,
      });
      final status = result['status'];
      if (!const {'accepted', 'rejected', 'unknown'}.contains(status)) {
        return const CommunityCreationOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      }
      CommunityCard? organization;
      if (status == 'accepted') {
        final page = parseCommunityDirectory({
          'schemaVersion': 1,
          'view': 'mine',
          'query': '',
          'items': [result['organization']],
        });
        organization = page.items.single;
        if (organization.relationship != 'owner') throw const FormatException();
      }
      return CommunityCreationOutcome(
        status as String,
        error: result['error'] is String ? result['error'] as String : null,
        organization: organization,
      );
    } on BridgeClientException catch (e) {
      // Explicit Host preflight rejection occurs before a network write. Timeouts and
      // malformed replies still cannot prove whether the server committed the create.
      if (e.code == 'communities.dataInvalid') {
        return const CommunityCreationOutcome(
          'rejected',
          error: 'invalidDraft',
        );
      }
      return const CommunityCreationOutcome('unknown', error: 'outcomeUnknown');
    } catch (_) {
      // A transport failure cannot prove whether the server committed the create.
      return const CommunityCreationOutcome('unknown', error: 'outcomeUnknown');
    }
  }

  @override
  bool get canPickLogo =>
      !isClosed && session.hostCapabilities.contains('communities.logo');

  @override
  Future<CommunityLogoSource?> pickLogo() async {
    final value = await sendRequest('communities.pickLogo', const {});
    if (value['status'] == 'cancelled') return null;
    if (value['status'] != 'selected' || value['source'] is! Map) {
      throw const FormatException();
    }
    final source = Map<String, Object?>.from(value['source'] as Map);
    final ref = source['sourceRef'],
        image = source['previewImageData'],
        width = source['width'],
        height = source['height'];
    if (ref is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(ref) ||
        image is! String ||
        !image.startsWith('data:image/png;base64,') ||
        image.length > 700000 ||
        width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0 ||
        width * height > 16 * 1024 * 1024) {
      throw const FormatException();
    }
    return CommunityLogoSource(ref, image, width, height);
  }

  @override
  Future<String> cropLogo(
    String sourceRef,
    double x,
    double y,
    double size,
  ) async {
    final value = await sendRequest('communities.cropLogo', {
      'sourceRef': sourceRef,
      'x': x,
      'y': y,
      'size': size,
    });
    final data = value['imageData'];
    if (value['status'] != 'cropped' ||
        data is! String ||
        !data.startsWith('data:image/png;base64,') ||
        data.length > 700000) {
      throw const FormatException();
    }
    return data;
  }

  @override
  Future<void> clearLogo() async {
    await sendRequest('communities.clearLogo', const {});
  }

  @override
  bool get canPickWideImage =>
      !isClosed && session.hostCapabilities.contains('communities.wideImage');

  void _requireWideImage([String? kind]) {
    if (!canPickWideImage) throw const CommunityFailure('unavailable');
    if (kind != null && kind != 'banner' && kind != 'background') {
      throw const FormatException();
    }
  }

  @override
  Future<CommunityLogoSource?> pickWideImage(String kind) async {
    _requireWideImage(kind);
    final value = await sendRequest('communities.pickWideImage', {
      'kind': kind,
    }, timeout: const Duration(minutes: 5));
    if (value['status'] == 'cancelled') return null;
    if (value['status'] != 'selected' || value['source'] is! Map) {
      throw const FormatException();
    }
    final source = Map<String, Object?>.from(value['source'] as Map);
    final ref = source['sourceRef'],
        image = source['previewImageData'],
        width = source['width'],
        height = source['height'];
    if (ref is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(ref) ||
        image is! String ||
        !image.startsWith('data:image/png;base64,') ||
        image.length > 700000 ||
        width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0 ||
        width * height > 16 * 1024 * 1024 ||
        base64Decode(image.substring(22)).isEmpty) {
      throw const FormatException();
    }
    return CommunityLogoSource(ref, image, width, height);
  }

  @override
  Future<String> cropWideImage(
    String sourceRef,
    String kind,
    double x,
    double y,
    double width,
  ) async {
    _requireWideImage(kind);
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(sourceRef) ||
        !x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        width < .2 ||
        width > 1 ||
        x + width > 1 + 1e-12) {
      throw const FormatException();
    }
    final value = await sendRequest('communities.cropWideImage', {
      'sourceRef': sourceRef,
      'kind': kind,
      'x': x,
      'y': y,
      'width': width,
    });
    final data = value['imageData'];
    const prefix = 'data:image/jpeg;base64,';
    if (value['status'] != 'cropped' ||
        data is! String ||
        !data.startsWith(prefix) ||
        data.length > 2796236) {
      throw const FormatException();
    }
    final bytes = base64Decode(data.substring(prefix.length));
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw const FormatException();
    }
    return data;
  }

  @override
  Future<void> clearWideImage() async {
    _requireWideImage();
    final value = await sendRequest('communities.clearWideImage', const {});
    if (value['status'] != 'cleared') throw const FormatException();
  }
}

CommunityDirectory parseCommunityDirectory(Map<String, Object?> value) {
  String text(Object? value, int max) {
    if (value is! String || value.length > max) throw const FormatException();
    return value;
  }

  if (value['schemaVersion'] != 1) throw const FormatException();
  final view = text(value['view'], 16);
  if (!const {'mine', 'discover'}.contains(view)) throw const FormatException();
  final rows = value['items'];
  if (rows is! List || rows.length > 20) throw const FormatException();
  final items = rows.map((raw) {
    final row = Map<String, Object?>.from(raw as Map);
    final ref = text(row['targetRef'], 32);
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(ref)) throw const FormatException();
    final relation = text(row['relationship'], 16),
        mode = text(row['joinMode'], 16);
    if (!const {'owner', 'member', 'pending', 'none'}.contains(relation) ||
        !const {
          'direct',
          'application',
          'inviteOnly',
          'unavailable',
        }.contains(mode)) {
      throw const FormatException();
    }
    final actions = (row['actions'] as List).cast<String>();
    if (actions.length > 1 ||
        actions.any(
          (a) => !const {'join', 'apply', 'withdraw', 'leave'}.contains(a),
        )) {
      throw const FormatException();
    }
    final count = row['memberCount'];
    if (count != null && (count is! int || count < 0)) {
      throw const FormatException();
    }
    final logo = row['logoImageData'];
    return CommunityCard(
      targetRef: ref,
      name: text(row['name'], 512),
      organizationRef: row['organizationRef'] == null
          ? null
          : text(row['organizationRef'], 32),
      tags: row['tags'] == null ? '' : text(row['tags'], 2048),
      recruiting: row['recruiting'] == true,
      recruitingTarget: row['recruitingTarget'] == null
          ? ''
          : text(row['recruitingTarget'], 512),
      memberScale: row['memberScale'] == null
          ? ''
          : text(row['memberScale'], 16),
      recruitingNote: row['recruitingNote'] == null
          ? ''
          : text(row['recruitingNote'], 2048),
      systems: row['systems'] is List
          ? List<String>.from(row['systems'] as List).take(20).toList()
          : const [],
      description: text(row['description'], 8192),
      language: text(row['language'], 512),
      activeTime: text(row['activeTime'], 1024),
      memberCount: count as int?,
      relationship: relation,
      joinMode: mode,
      actions: List.unmodifiable(actions),
      logo: logo is String && decodeCommunityLogo(logo) != null ? logo : null,
      logoDeferred: row['logoDeferred'] == true,
    );
  }).toList();
  return CommunityDirectory(
    view,
    text(value['query'], 128),
    List.unmodifiable(items),
    totalCount: value['totalCount'] is int && (value['totalCount'] as int) >= 0
        ? value['totalCount'] as int
        : null,
    next: value['next'] == null ? null : text(value['next'], 256),
  );
}
