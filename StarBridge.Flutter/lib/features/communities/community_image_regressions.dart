import 'dart:typed_data';

import '../../shared/diagnostics/loading_metrics.dart';

/// Loading-trace only (2026-10-21 report "V 部分还会出现加载"): remembers which
/// image contents were already shown, so a later loading/placeholder state for
/// the same content is counted as a regression rather than a first load.
/// Content fingerprints only; inactive (and empty) without a loading trace.
final _shown = <(int, int)>{}; // insertion-ordered: oldest first
const _capacity = 1024;

(int, int) _fingerprint(Uint8List bytes) {
  // Length plus a sparse sample: cheap, stable across copies of the content.
  var hash = 17;
  final step = bytes.length <= 512 ? 1 : bytes.length ~/ 512;
  for (var i = 0; i < bytes.length; i += step) {
    hash = 0x1fffffff & (hash * 31 + bytes[i]);
  }
  return (bytes.length, hash);
}

void markCommunityImageShown(Uint8List bytes) {
  final metrics = LoadingMetrics.current;
  if (metrics == null || metrics.stopped) return;
  final key = _fingerprint(bytes);
  _shown.remove(key);
  _shown.add(key);
  while (_shown.length > _capacity) {
    _shown.remove(_shown.first);
  }
}

bool communityImageWasShown(Uint8List bytes) {
  final metrics = LoadingMetrics.current;
  if (metrics == null || metrics.stopped) return false;
  return _shown.contains(_fingerprint(bytes));
}

void recordCommunityImageRegression(
  LoadingImageRegression cause, {
  LoadingImageSurface surface = LoadingImageSurface.communityWorkspaceImage,
}) {
  final metrics = LoadingMetrics.current;
  if (metrics == null || metrics.stopped) return;
  metrics.imageRegressed(surface, cause);
}
