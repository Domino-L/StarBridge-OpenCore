import 'dart:async';

import 'communities_module.dart' show CommunitiesPort;
import 'community_directory_images.dart';
import 'community_directory_metadata_port.dart';
import 'community_directory_models.dart';
import 'community_cached_presentation_port.dart';

/// Session-owned directory presentation and its optional image completions.
/// Metadata admission stays with the caller's account/query epoch. This owner
/// keeps the two image lanes independent and never releases physical IO early.
final class CommunityDirectoryReadOwner {
  CommunityDirectoryReadOwner(this.port, this.images, this.changed);
  final CommunitiesPort port;
  final CommunityDirectoryImages images;
  final void Function() changed;
  List<CommunityCard> joined = const [];
  CommunityDirectory? directory;
  CommunityCard? selected;
  CommunityDirectoryRead? _directoryRead, _joinedRead;
  bool _closed = false;
  final _names = <String, ({int revision, String name})>{};
  int _nameRevision = 0;
  int get nameRevision => _nameRevision;

  void clearNames() => _names.clear();

  /// Keep confirmed presentation changes newer than a pending metadata read.
  /// No commands, account admission or external rename callbacks live here.
  void rename(String key, String name) {
    _names[key] = (revision: ++_nameRevision, name: name);
    CommunityCard update(CommunityCard row) =>
        row.key == key ? row.withName(name) : row;
    joined = List.unmodifiable(joined.map(update));
    if (directory case final current?) {
      directory = CommunityDirectory(
        current.view,
        current.query,
        List.unmodifiable(current.items.map(update)),
        next: current.next,
        totalCount: current.totalCount,
        cachedAtUtc: current.cachedAtUtc,
        cacheComplete: current.cacheComplete,
        displayVersion: current.displayVersion,
      );
    }
    if (selected case final current?) selected = update(current);
  }

  CommunityDirectory mergeNames(CommunityDirectory value, int revision) =>
      value.mapItems((row) {
        final changed = _names[row.key];
        return changed != null && changed.revision > revision
            ? row.withName(changed.name)
            : row;
      });

  void cachedLogo(CommunityCachedLogo value, String? joinedVersion) {
    if (_closed) return;
    final update = images.cachedLogo(value, joined, joinedVersion, directory);
    if (update == null) return;
    joined = update.joined;
    directory = update.directory;
    changed();
  }

  void retireLogos() {
    joined = CommunityDirectoryImages.retireRows(joined);
    directory = directory?.withoutDownloadedLogos();
    selected = selected?.withoutDownloadedLogo();
    changed();
  }

  Future<CommunityDirectoryRead> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) async {
    final source = port;
    if (source is CommunityProgressiveDirectoryPort) {
      return await (source as CommunityProgressiveDirectoryPort)
          .readDirectoryProgressively(
            view: view,
            query: query,
            after: after,
            filters: filters,
          );
    }
    return CommunityDirectoryRead(
      await port.read(view: view, query: query, after: after, filters: filters),
    );
  }

  CommunityDirectory joinedMetadata(
    CommunityDirectoryRead read,
    int revision,
    int imageEpoch,
  ) => _metadata(read, revision, imageEpoch, joined);

  CommunityDirectory directoryMetadata(
    CommunityDirectoryRead read,
    int revision,
    int imageEpoch,
  ) => _metadata(read, revision, imageEpoch, directory?.items ?? const []);

  CommunityDirectory _metadata(
    CommunityDirectoryRead read,
    int revision,
    int imageEpoch,
    List<CommunityCard> previous,
  ) => images.retainPending(
    images.admit(mergeNames(read.page, revision), imageEpoch),
    previous,
    imageEpoch,
  );

  void retireDirectory() {
    _directoryRead?.retireImages();
    _directoryRead = null;
  }

  void retireJoined() {
    _joinedRead?.retireImages();
    _joinedRead = null;
  }

  void retireAll() {
    retireDirectory();
    retireJoined();
  }

  void watchJoined(
    CommunityDirectoryRead read,
    int imageEpoch,
    bool Function() current,
  ) {
    _joinedRead = read;
    _watch(read, imageEpoch, current, (loaded) {
      joined = CommunityDirectoryImages.loadedRows(joined, loaded);
      _updateSelected(loaded);
      changed();
    });
  }

  void watchDirectory(
    CommunityDirectoryRead read,
    int imageEpoch,
    bool Function() current, {
    bool Function()? mirrorJoined,
  }) {
    _directoryRead = read;
    _watch(read, imageEpoch, current, (loaded) {
      if (directory case final page?) {
        directory = CommunityDirectoryImages.loadedPage(page, loaded);
      }
      _updateSelected(loaded);
      if (mirrorJoined?.call() == true) {
        joined = CommunityDirectoryImages.loadedRows(joined, loaded);
      }
      changed();
    });
  }

  void _updateSelected(CommunityDirectory loaded) {
    if (selected case final card?) {
      selected = CommunityDirectoryImages.loadedRows([card], loaded).single;
    }
  }

  void _watch(
    CommunityDirectoryRead read,
    int imageEpoch,
    bool Function() current,
    void Function(CommunityDirectory) publish,
  ) {
    final completion = read.images;
    if (completion == null) return;
    bool admitted() => !_closed && images.current(imageEpoch) && current();
    // Each arrived logo is shown at once; the slowest one no longer holds
    // back the other cards (2026-10-20 寻找组织 report).
    final partial = read.progress?.listen((loaded) {
      if (admitted()) publish(loaded);
    }, onError: (Object _, StackTrace _) {});
    void finished() {
      unawaited(partial?.cancel());
      if (identical(_directoryRead, read)) _directoryRead = null;
      if (identical(_joinedRead, read)) _joinedRead = null;
    }

    unawaited(
      completion.then<void>(
        (loaded) {
          if (admitted()) publish(loaded);
          finished();
        },
        onError: (Object _, StackTrace _) {
          // Optional image failure cannot replace admitted metadata. Account/query
          // and maintenance invalidation still own their original hard fences.
          finished();
        },
      ),
    );
  }

  void dispose() {
    _closed = true;
    retireAll();
  }
}
