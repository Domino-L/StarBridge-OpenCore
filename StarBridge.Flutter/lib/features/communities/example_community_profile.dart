import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'communities_module.dart';
import 'community_profile_port.dart';
import 'community_workspace_port.dart';

/// In-memory editor data for the explicitly selected example session only.
/// Uses the real editor contract, with no Host, filesystem or network fallback.
final class ExampleCommunityProfile {
  final _fields = <String, Map<String, Object?>>{};
  final _revisions = <String, int>{};
  final _edits = <String, (String, int)>{};
  final _logos = <String, String>{};
  final _defaults = <String, Map<String, Object?>>{};
  int _sequence = 0;
  bool _closed = false;

  Map<String, Object?> fields(String target) => _fields[target] ?? const {};
  bool hasLogo(String target) => _logos.containsKey(target);

  Future<CommunityEditingProfile> read(
    Future<CommunityWorkspace> Function(String, String, int) workspace, {
    String? targetRef,
    String? editRef,
  }) async {
    if (_closed) throw const CommunityFailure('identityUnavailable');
    final lease = editRef == null ? null : _edits[editRef];
    final target = targetRef ?? lease?.$1;
    if (target == null || (targetRef != null && editRef != null)) {
      throw const CommunityFailure('refreshRequired');
    }
    final current = await workspace(target, '', 0);
    if (_closed) throw const CommunityFailure('identityUnavailable');
    final access = {
      for (final key in ['canEditProfile', 'canEditLogo', 'canEditBanner'])
        key: current.access[key] == true,
    };
    if (!access.values.any((value) => value)) {
      throw const CommunityFailure('notAllowed');
    }
    final ref = editRef ?? (++_sequence).toRadixString(16).padLeft(32, '0');
    final revision = _revisions[target] ?? 0;
    _edits[ref] = (target, revision);
    final data = _fields.putIfAbsent(
      target,
      () => {
        for (final key in communityProfileTextLimits.keys) key: '',
        for (final key in communityProfileFlags) key: false,
        'name': current.name,
        'description': current.description,
        'type': current.tags,
        'language': current.language,
        'activeTime': current.activeTime,
        'timeZoneId': current.timeZoneId ?? 'UTC',
        'joinPolicy': 'Approval',
        'inviteCodeCreationPolicy': 'management',
        'fleetInvitationCardPolicy': 'all_members',
        'publicMemberScaleMode': 'Exact',
        'publicShipScaleMode': 'TypeSummary',
        'activityCadence': '休闲',
        'recruitingTarget': '所有玩家',
        'publicListingEnabled': true,
        'publicShowDescription': true,
        'publicShowTags': true,
        'publicShowActiveSystems': true,
        'publicShowActivityTime': true,
        'activeSystemIds': current.activeSystemIds
            .map((id) => id.toLowerCase())
            .toList(),
        'activityWindows': [
          for (final window in current.activityWindows)
            {
              'days': window.days,
              'startTime': window.startTime,
              'endTime': window.endTime,
              'endsNextDay': window.endsNextDay,
            },
        ],
        'externalContacts': [
          for (final contact in current.externalContacts)
            {'platform': contact.$1, 'value': contact.$2},
        ],
        ...?_defaults[target],
      },
    );
    return CommunityEditingProfile.parse({
      'schemaVersion': 1,
      'targetRef': target,
      'editRef': ref,
      'code': current.code,
      'name': data['name'] as String? ?? current.name,
      'profileRevision': revision,
      'hasLogo': hasLogo(target),
      'hasBanner': false,
      'access': access,
      'profile': data,
    });
  }

  Future<CommunityProfileOutcome> save(
    Future<CommunityWorkspace> Function(String, String, int) workspace,
    String requestId,
    String editRef,
    Map<String, Object?> changes,
  ) async {
    if (_closed) {
      return const CommunityProfileOutcome(
        'rejected',
        error: 'identityUnavailable',
      );
    }
    final edit = _edits[editRef];
    if (edit == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId)) {
      return const CommunityProfileOutcome(
        'rejected',
        error: 'refreshRequired',
      );
    }
    try {
      final current = await workspace(edit.$1, '', 0);
      if (_closed) {
        return const CommunityProfileOutcome(
          'rejected',
          error: 'identityUnavailable',
        );
      }
      if ((_revisions[edit.$1] ?? 0) != edit.$2) {
        return const CommunityProfileOutcome('rejected', error: 'conflict');
      }
      final next = {...?_fields[edit.$1]};
      var logo = _logos[edit.$1];
      for (final entry in changes.entries) {
        final access = switch (entry.key) {
          'logoText' || 'logoImageData' || 'clearLogoImage' => 'canEditLogo',
          'clearBannerImage' => 'canEditBanner',
          _ => 'canEditProfile',
        };
        if (current.access[access] != true) {
          return const CommunityProfileOutcome('rejected', error: 'notAllowed');
        }
        final value = communityProfileChange(entry.key, entry.value);
        if (entry.key == 'logoImageData') {
          final bytes = base64Decode((value as String).split(',').last);
          if (bytes.isEmpty || bytes.length > 512 * 1024) {
            throw const FormatException();
          }
          logo = value;
        } else if (entry.key == 'clearLogoImage') {
          if (value == true) logo = null;
        } else if (entry.key != 'clearBannerImage') {
          next[entry.key] = value;
        }
      }
      _fields[edit.$1] = Map.unmodifiable(next);
      if (logo == null) {
        _logos.remove(edit.$1);
      } else {
        _logos[edit.$1] = logo;
      }
      final revision = edit.$2 + 1;
      _revisions[edit.$1] = revision;
      return CommunityProfileOutcome('accepted', revision: revision);
    } on CommunityFailure catch (failure) {
      return CommunityProfileOutcome('rejected', error: failure.code);
    } on FormatException {
      return const CommunityProfileOutcome('rejected', error: 'dataInvalid');
    }
  }

  CommunityCard project(CommunityCard card) {
    final p = fields(card.targetRef);
    if (p.isEmpty) {
      _defaults[card.targetRef] = {
        'recruitingEnabled': card.recruiting,
        'recruitingTarget': card.recruitingTarget,
        'joinPolicy': switch (card.joinMode) {
          'direct' => 'Open',
          'application' => 'Approval',
          _ => 'Invite',
        },
      };
      return card;
    }
    return CommunityCard(
      targetRef: card.targetRef,
      organizationRef: card.organizationRef,
      name: p['name'] as String? ?? card.name,
      description: p['description'] as String? ?? card.description,
      tags: p['type'] as String? ?? card.tags,
      language: p['language'] as String? ?? card.language,
      activeTime: p['activeTime'] as String? ?? card.activeTime,
      systems: [
        for (final id
            in (p['activeSystemIds'] as List?)?.cast<String>() ?? card.systems)
          switch (id.toLowerCase()) {
            'stanton' => 'Stanton',
            'pyro' => 'Pyro',
            'nyx' => 'Nyx',
            _ => id,
          },
      ],
      recruiting: p['recruitingEnabled'] as bool? ?? card.recruiting,
      recruitingTarget:
          p['recruitingTarget'] as String? ?? card.recruitingTarget,
      recruitingNote: p['recruitingNote'] as String? ?? card.recruitingNote,
      memberScale: card.memberScale,
      memberCount: card.memberCount,
      relationship: card.relationship,
      actions: card.actions,
      joinMode: switch (p['joinPolicy']) {
        'Open' => 'direct',
        'Approval' => 'application',
        'Invite' => 'inviteOnly',
        _ => card.joinMode,
      },
      logo: _logos[card.targetRef],
    );
  }

  Map<String, Object?> media(String target, int offset, String? version) {
    final image = _logos[target];
    if (_closed || image == null) throw const CommunityFailure('notFound');
    final bytes = base64Decode(image.split(',').last);
    final hash = sha256.convert(bytes).toString();
    if (version != null && version != hash) {
      throw const CommunityFailure('mediaChanged');
    }
    if (offset < 0 || offset >= bytes.length || offset % (192 * 1024) != 0) {
      throw const CommunityFailure('dataInvalid');
    }
    final end = (offset + 192 * 1024).clamp(0, bytes.length);
    return {
      'schemaVersion': 1,
      'kind': 'logo',
      'memberRef': null,
      'mimeType': image.substring(5, image.indexOf(';')),
      'version': hash,
      'totalBytes': bytes.length,
      'offset': offset,
      'next': end < bytes.length ? end : null,
      'data': base64Encode(bytes.sublist(offset, end)),
    };
  }

  void close() {
    _closed = true;
    _fields.clear();
    _revisions.clear();
    _edits.clear();
    _logos.clear();
    _defaults.clear();
  }
}
