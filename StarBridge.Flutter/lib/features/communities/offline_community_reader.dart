import 'dart:async';
import 'dart:convert';

import '../../platform/bridge/bridge_client_session.dart';
import '../../shared/bounded_inline_avatar.dart';
import '../onboarding/connection_mode_port.dart';
import 'communities_module.dart';
import 'community_cached_presentation_port.dart';
import 'community_workspace_port.dart';

/// A borrowed, read-only source descriptor. No root response, role, member
/// lease or completed account state is cached here.
final class OfflineCommunityReader {
  OfflineCommunityReader(
    this.session, {
    required this.mode,
    required this.retainedReadId,
    required this.epoch,
    required this.request,
  });
  final BridgeClientSession session;
  final ConnectionModeControl? mode;
  final String? Function()? retainedReadId;
  final int Function() epoch;
  final Future<Map<String, Object?>> Function(String, Map<String, Object?>)
  request;
  final changes = StreamController<CommunityCachedLogo>.broadcast();
  bool _closed = false;

  Future<CommunityDirectory?> read({
    required String view,
    required String query,
    String? after,
    String? filters,
    required bool hydrate,
    bool Function()? imagesCurrent,
  }) async {
    final control = mode, retained = retainedReadId?.call();
    final offline =
        control?.failed == false &&
        control?.snapshot.state == ConnectionModeState.offline;
    if (!offline && retained == null) return null;
    if (_closed ||
        !session.hostCapabilities.contains('onboarding.mode.directory.v1')) {
      throw const CommunityFailure('offlineCacheUnavailable');
    }
    if (view != 'mine' || query.trim().isNotEmpty || filters != null) {
      throw const CommunityFailure('onlinePaused');
    }
    final generation = session.activeGeneration,
        revision = control?.snapshot.revision,
        modeScope = control?.snapshot.scope,
        started = epoch();
    if (offline && revision == null) {
      throw const CommunityFailure('offlineCacheUnavailable');
    }
    void current() {
      if (_closed ||
          generation != session.activeGeneration ||
          started != epoch() ||
          (offline
              ? control!.failed ||
                    control.snapshot.state != ConnectionModeState.offline ||
                    control.snapshot.revision != revision ||
                    control.snapshot.scope != modeScope
              : retainedReadId?.call() != retained)) {
        throw const CommunityFailure('identityUnavailable');
      }
    }

    Future<Map<String, Object?>> read(
      String kind,
      Map<String, Object?> payload,
    ) async {
      current();
      final value = await request(
        offline
            ? kind == 'communities'
                  ? 'onboarding.mode.communities'
                  : 'onboarding.mode.communityMedia'
            : 'account.offlineData.read',
        {
          if (offline)
            'revision': revision
          else ...{
            'readId': retained,
            'kind': kind,
          },
          ...payload,
        },
      );
      current();
      return value;
    }

    try {
      final cursor = after?.split(':');
      final offset = cursor == null
          ? 0
          : cursor.length == 2
          ? int.tryParse(cursor[0])
          : null;
      if (offset == null ||
          offset < 0 ||
          offset > 256 ||
          cursor != null && !RegExp(r'^[a-f0-9]{32}$').hasMatch(cursor[1])) {
        throw const FormatException();
      }
      final raw = await read('communities', {
        'offset': offset,
        if (cursor != null) 'directoryVersion': cursor[1],
      });
      if (raw.keys.any(
            (key) => !const {
              'schemaVersion',
              'source',
              'cachedAtUtc',
              'complete',
              'directoryVersion',
              'items',
              'nextOffset',
            }.contains(key),
          ) ||
          raw['schemaVersion'] != 1 ||
          raw['source'] != 'cached' ||
          raw['complete'] is! bool ||
          raw['directoryVersion'] is! String ||
          !RegExp(r'^[a-f0-9]{32}$')
              .hasMatch(raw['directoryVersion']! as String) ||
          raw['items'] is! List ||
          (raw['items'] as List).length > 20) {
        throw const FormatException();
      }
      final time = inlineAvatarObservedAt(raw['cachedAtUtc']);
      if (time == null) throw const FormatException();
      final version = raw['directoryVersion']! as String;
      if (cursor != null && cursor[1] != version) throw const FormatException();
      final ids = <String>{};
      final rows = <CommunityCard>[];
      final logos = <({String id, String hash})>[];
      for (final item in raw['items'] as List) {
        if (item is! Map ||
            item.keys.any(
              (key) => !const {
                'id',
                'name',
                'logoAvailable',
                'logoVersion',
                'logoCachedAtUtc',
              }.contains(key),
            )) {
          throw const FormatException();
        }
        final id = item['id'],
            name = item['name'],
            logo = item['logoAvailable'];
        if (id is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
            !ids.add(id) ||
            name is! String ||
            name.trim().isEmpty ||
            name.length > 512 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
            logo is! bool) {
          throw const FormatException();
        }
        if (logo) {
          final hash = item['logoVersion'];
          if (hash is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
              inlineAvatarObservedAt(item['logoCachedAtUtc']) == null) {
            throw const FormatException();
          }
          logos.add((id: id, hash: hash));
        } else if (item['logoVersion'] != null ||
            item['logoCachedAtUtc'] != null) {
          throw const FormatException();
        }
        rows.add(
          CommunityCard(
            targetRef: '',
            organizationRef: 'cached:$id',
            name: name,
            displayOnly: true,
            logoDeferred: logo,
          ),
        );
      }
      final next = raw['nextOffset'];
      if (next != null &&
          (next is! int ||
              next != offset + rows.length ||
              next <= offset ||
              next >= 256)) {
        throw const FormatException();
      }
      if (offset + rows.length > 256) throw const FormatException();
      if (hydrate && logos.isNotEmpty && (imagesCurrent?.call() ?? true)) {
        void imageCurrent() {
          current();
          if (!(imagesCurrent?.call() ?? true)) {
            throw StateError('Retired image read');
          }
        }

        unawaited(_hydrate(logos, version, read, imageCurrent));
      }
      return CommunityDirectory(
        view,
        query,
        List.unmodifiable(rows),
        next: next == null ? null : '$next:$version',
        cachedAtUtc: time,
        cacheComplete: raw['complete']! as bool,
        displayVersion: version,
      );
    } on CommunityFailure {
      rethrow;
    } on Object {
      current();
      throw const CommunityFailure('offlineCacheUnavailable');
    }
  }

  Future<void> _hydrate(
    List<({String id, String hash})> logos,
    String directoryVersion,
    Future<Map<String, Object?>> Function(String, Map<String, Object?>) read,
    void Function() current,
  ) async {
    try {
      // Let the owner publish names and their original time before optional I/O.
      await Future<void>.delayed(Duration.zero);
      var next = 0;
      Future<void> worker() async {
        while (next < logos.length) {
          current();
          final row = logos[next++];
          try {
            String? mime;
            final bytes = await assembleCommunityMedia(
              (offset, version) async {
                final value = await read('communityMedia', {
                  'id': row.id,
                  'offset': offset,
                  'directoryVersion': directoryVersion,
                  'version': version ?? row.hash,
                });
                mime = value['mimeType'] as String?;
                return value;
              },
              'logo',
              checkCurrent: current,
            );
            current();
            final image = boundedInlineAvatar(
              'data:$mime;base64,${base64Encode(bytes)}',
            );
            if (image != null) {
              changes.add(
                CommunityCachedLogo(
                  directoryVersion,
                  'cached:${row.id}',
                  image,
                ),
              );
            }
          } on Object {
            current();
          } // An independent media miss keeps the name.
        }
      }

      await Future.wait(List.generate(3, (_) => worker()));
    } on Object {
      /* Cancellation/retirement never publishes a stale image. */
    }
  }

  Future<void> close() async {
    _closed = true;
    await changes.close();
  }
}
