import '../../shared/downloadable_image_cache.dart';
import 'community_cached_presentation_port.dart';
import 'community_directory_models.dart';

/// Optional image admission is independent of directory/account admission.
/// Metadata and view state remain with the owner while old bytes are retired.
final class CommunityDirectoryImages implements DownloadableImageCache {
  CommunityDirectoryImages(this.workspace, this.port, this.retire);
  final DownloadableImageCache workspace;
  final Object port;
  final void Function() retire;
  int epoch = 0;
  bool paused = false, referencesStale = false;
  bool current(int started) => !paused && started == epoch;
  void acceptedRead(int started) => referencesStale = !current(started);
  CommunityDirectory admit(CommunityDirectory value, int started) =>
      current(started) ? value : value.withoutDownloadedLogos();

  CommunityDirectory retainPending(
    CommunityDirectory value,
    List<CommunityCard> previous,
    int started,
  ) {
    if (!current(started)) return value;
    var changed = false;
    final retained = value.mapItems((row) {
      // Same organization (Host organizationRef is stable per account scope;
      // targetRef is re-issued on every read). Display bytes only: the old
      // logo stays until this read's own copy arrives, instead of a shield.
      final old = previous
          .where((old) => old.key == row.key && !old.displayOnly)
          .firstOrNull;
      if (!row.displayOnly &&
          row.logoDeferred &&
          row.logo == null &&
          old?.logo != null) {
        changed = true;
        return row.withDownloadedLogo(old!.logo!);
      }
      return row;
    });
    return changed ? retained : value;
  }

  /// Apply only bytes to rows still admitted by the current metadata owner.
  static List<CommunityCard> loadedRows(
    List<CommunityCard> current,
    CommunityDirectory loaded,
  ) => List.unmodifiable(current.map((row) => _loadedRow(row, loaded)));

  static CommunityDirectory loadedPage(
    CommunityDirectory current,
    CommunityDirectory loaded,
  ) => current.mapItems((row) => _loadedRow(row, loaded));

  static CommunityCard _loadedRow(
    CommunityCard row,
    CommunityDirectory loaded,
  ) {
    final image = loaded.items
        .where(
          (other) =>
              other.key == row.key &&
              other.targetRef == row.targetRef &&
              !other.displayOnly,
        )
        .firstOrNull
        ?.logo;
    return !row.displayOnly && image != null
        ? row.withDownloadedLogo(image)
        : row;
  }

  static List<CommunityCard> retireRows(List<CommunityCard> rows) =>
      List.unmodifiable(rows.map((row) => row.withoutDownloadedLogo()));
  void _retire() {
    epoch++;
    referencesStale = true;
    retire();
  }

  @override
  void beginImageMaintenance() {
    paused = true;
    _retire();
    workspace.beginImageMaintenance();
    if (port case final DownloadableImageCache cache) {
      cache.beginImageMaintenance();
    }
  }

  @override
  void endImageMaintenance() {
    if (port case final DownloadableImageCache cache) {
      cache.endImageMaintenance();
    }
    workspace.endImageMaintenance();
    _retire();
    paused = false;
  }

  ({List<CommunityCard> joined, CommunityDirectory? directory})? cachedLogo(
    CommunityCachedLogo value,
    List<CommunityCard> joined,
    String? joinedVersion,
    CommunityDirectory? directory,
  ) {
    if (paused) return null;
    final rows = value.directoryVersion == joinedVersion
        ? withCachedCommunityLogo(
            joined,
            value.organizationKey,
            value.imageData,
          )
        : joined;
    final page = value.directoryVersion == directory?.displayVersion
        ? directory?.withCachedLogo(value.organizationKey, value.imageData)
        : directory;
    return identical(rows, joined) && identical(page, directory)
        ? null
        : (joined: rows, directory: page);
  }

  List<CommunityCard> mergeJoined(
    CommunityDirectory value,
    List<CommunityCard> previous,
    String? previousVersion,
    int started,
  ) =>
      current(started) &&
          value.displayVersion != null &&
          value.displayVersion == previousVersion
      ? value.items.map((row) {
          final old = previous.where((old) => old.key == row.key).firstOrNull;
          return row.displayOnly && row.logoDeferred && old?.logo != null
              ? row.withCachedLogo(old!.logo!)
              : row;
        }).toList()
      : value.items;
}
