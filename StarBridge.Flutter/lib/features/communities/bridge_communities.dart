import 'dart:async';
import 'dart:convert';

import '../../platform/bridge/bridge_client_session.dart';
import 'communities_module.dart';
import 'community_creation_port.dart';
import 'community_logo_port.dart';
import 'community_image_data.dart';
import 'community_workspace_port.dart';
import 'community_visitor_profile_port.dart';
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
        CommunityVisitorProfilePort,
        CommunityCreationPort,
        CommunityLogoPort,
        CommunityWorkspacePort {
  BridgeCommunities(super.session, {super.ownAvatar});
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
  }) async {
    final epoch = requestEpoch;
    void current() {
      if (isClosed || epoch != requestEpoch) {
        throw const CommunityFailure('identityUnavailable');
      }
    }

    try {
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
      final rows = (value['items'] as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      var next = 0;
      Future<void> loadLogos() async {
        while (next < rows.length) {
          current();
          final index = next++;
          final row = rows[index];
          if (row['logoDeferred'] != true) continue;
          try {
            String? mime;
            final bytes = await assembleCommunityMedia(
              (offset, version) async {
                current();
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
              checkCurrent: current,
            );
            current();
            row['logoImageData'] = 'data:$mime;base64,${base64Encode(bytes)}';
          } on Object {
            // One unavailable/corrupt image must not discard a directory page.
            current();
            row['logoImageData'] = null;
          }
        }
      }

      // Bound parallel Bridge work; all chunks remain account/epoch guarded.
      await Future.wait(List.generate(3, (_) => loadLogos()));
      current();
      return parseCommunityDirectory({...value, 'items': rows});
    } on BridgeClientException catch (e) {
      throw CommunityFailure(switch (e.code) {
        'communities.upgradeRequired' => 'upgradeRequired',
        'communities.refreshRequired' => 'refreshRequired',
        'communities.identityUnavailable' ||
        'account.reauthorization_required' => 'identityUnavailable',
        'communities.dataInvalid' => 'dataInvalid',
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
