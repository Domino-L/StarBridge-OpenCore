import 'dart:async';
import 'dart:convert';

import '../../features/communities/communities_module.dart';
import '../../features/communities/community_directory_metadata_port.dart';
import '../../features/communities/community_workspace_port.dart';
import '../../features/communities/community_image_decoder.dart';
import 'menu_organization_avatars.dart';
import '../../shared/downloadable_image_cache.dart';

/// Optional photos never hold directory/chat readiness hostage. Downloads stay
/// account-scoped, bounded to three workers, and are retired on invalidation.
final class MenuDirectoryLogos implements DownloadableImageCache {
  MenuDirectoryLogos(
    this.port,
    this.onLogo, {
    DateTime Function()? now,
    CommunityImageDecoder decoder = decodeCommunityImage,
  }) : _now = now ?? DateTime.now,
       _images = MenuOrganizationAvatars(decoder: decoder);
  final DateTime Function() _now;
  final CommunitiesPort port;
  final void Function(String target, String? logo) onLogo;
  final MenuOrganizationAvatars _images;
  final _cache = <String, ({String? image, DateTime loaded})>{};
  final _pending = <String>{};
  final _waiters = <String, Completer<String?>>{};
  final _sources = <String, (String, String?, bool)>{};
  String _key(CommunityCard card) =>
      card.organizationRef != null &&
          const ['member', 'owner'].contains(card.relationship)
      ? 'organization:${card.organizationRef}'
      : 'target:${card.targetRef}:${card.organizationRef}:${card.relationship}';
  final _queue = <({CommunityCard card, int epoch, Completer<String?> done})>[];
  int _epoch = 0, _workers = 0;
  bool _disposed = false;
  bool _paused = false;
  final _admitted = Expando<int>();
  int get imageEpoch => _epoch;
  bool imagesCurrent(int epoch) => !_paused && epoch == _epoch;

  void retain(List<CommunityCard> cards) {
    final keys = cards.map(_key).toSet();
    _sources.removeWhere((key, _) => !keys.contains(key));
    _cache.removeWhere((key, _) => !keys.contains(key));
  }

  Future<CommunityDirectory> readDirectory({
    required String view,
    required String query,
    String? after,
  }) async {
    final started = _epoch;
    var page = await (port is CommunityDirectoryMetadataPort
        ? (port as CommunityDirectoryMetadataPort).readDirectoryMetadata(
            view: view,
            query: query,
            after: after,
          )
        : port.read(view: view, query: query, after: after));
    if (!imagesCurrent(started)) page = page.withoutDownloadedLogos();
    for (final row in page.items) {
      _admitted[row] = started;
    }
    return page;
  }

  Future<String?> read(CommunityCard card, {bool waitForImage = false}) {
    if (_disposed || _paused || (_admitted[card] ?? _epoch) != _epoch) {
      return Future.value(null);
    }
    final key = _key(card);
    _sources[key] = (card.targetRef, card.logo, card.logoDeferred);
    if (card.logo == null && !card.logoDeferred) {
      if (_cache.remove(key) != null) onLogo(card.targetRef, null);
      return Future.value(null);
    }
    final cached = _cache[key];
    if (!_disposed &&
        (card.logo != null ||
            card.logoDeferred && port is CommunityWorkspacePort) &&
        (cached == null ||
            _now().difference(cached.loaded) > const Duration(seconds: 30)) &&
        _pending.add(key)) {
      final done = Completer<String?>();
      _waiters[key] = done;
      _queue.add((card: card, epoch: _epoch, done: done));
      _start();
    }
    final pending = _waiters[key];
    if (waitForImage && pending != null) {
      final started = _epoch;
      return pending.future
          .timeout(const Duration(seconds: 2), onTimeout: () => null)
          .then(
            (image) => imagesCurrent(started) ? image ?? cached?.image : null,
          );
    }
    return Future.value(cached?.image);
  }

  void _start() {
    while (!_disposed && _workers < 3 && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _workers++;
      unawaited(
        _load(job.card, job.epoch)
            .then((image) {
              if (!job.done.isCompleted) job.done.complete(image);
            })
            .whenComplete(() {
              _workers--;
              _start();
            }),
      );
    }
  }

  Future<String?> _load(CommunityCard card, int epoch) async {
    final key = _key(card);
    bool current() =>
        !_disposed &&
        !_paused &&
        epoch == _epoch &&
        _sources[key]?.$2 == card.logo &&
        _sources[key]?.$3 == card.logoDeferred;
    void requireCurrent() {
      if (!current()) throw StateError('retired');
    }

    try {
      var data = card.logo;
      if (data == null) {
        final media = port as CommunityWorkspacePort;
        String? mime;
        final bytes = await assembleCommunityMedia(
          (offset, version) async {
            requireCurrent();
            final chunk = await media.readMedia(
              card.targetRef,
              'logo',
              offset: offset,
              version: version,
            );
            mime = chunk['mimeType'] as String?;
            return chunk;
          },
          'logo',
          checkCurrent: requireCurrent,
        );
        requireCurrent();
        data = 'data:$mime;base64,${base64Encode(bytes)}';
      }
      final image = await _images.logo(data, background: true);
      requireCurrent();
      // A decode/thumbnail failure is not authoritative removal of the logo.
      if (image == null) return null;
      if (!_cache.containsKey(key) && _cache.length >= 32) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = (image: image, loaded: _now());
      onLogo(_sources[key]!.$1, image);
      return image;
    } on Object {
      // Retry on a later poll; never cache failure as a permanent empty logo.
    } finally {
      if (epoch == _epoch) {
        _pending.remove(key);
        _waiters.remove(key);
      }
    }
    return null;
  }

  void clear() {
    _epoch++;
    _queue.clear();
    _pending.clear();
    for (final waiter in _waiters.values) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    _waiters.clear();
    _sources.clear();
    _cache.clear();
    _images.clear();
  }

  @override
  void beginImageMaintenance() {
    _paused = true;
    clear();
  }

  @override
  void endImageMaintenance() {
    clear();
    _paused = false;
  }

  void dispose() {
    _disposed = true;
    clear();
    _images.dispose();
  }
}
