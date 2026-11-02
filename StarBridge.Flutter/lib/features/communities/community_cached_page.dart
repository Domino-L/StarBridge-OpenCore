import 'community_directory_models.dart';

/// Restores a cached page from a newly prepared, finite directory snapshot.
/// Cursors come only from rows actually read in that snapshot. It never reads
/// an account, retries a failed request, or accepts a different version midway.
Future<({CommunityDirectory directory, String? after, List<String?> previous})?>
prepareCachedCommunityPage({
  required String? after,
  required Future<void> firstPage,
  required bool Function() current,
  required CommunityDirectory? Function() snapshot,
  required Future<void> Function() advance,
}) async {
  final old = after?.split(':');
  final requested = old?.length == 2 ? int.tryParse(old!.first) : 0;
  final target = requested != null && requested >= 0 && requested < 256
      ? requested
      : 0;
  await firstPage;
  var value = snapshot();
  if (!current() || value == null || value.displayVersion == null) return null;
  final version = value.displayVersion;
  for (
    var page = 0;
    value!.items.length <= target && value.next != null;
    page++
  ) {
    final cursor = value.next!.split(':');
    final offset = cursor.length == 2 ? int.tryParse(cursor.first) : null;
    if (page >= 13 || cursor.last != version || offset != value.items.length) {
      return null;
    }
    final count = value.items.length;
    await advance();
    if (!current()) return null;
    value = snapshot();
    if (value == null ||
        value.displayVersion != version ||
        value.items.length <= count) {
      return null;
    }
  }
  if (!current() ||
      value.items.length > 256 ||
      value.items.any((row) => !row.displayOnly)) {
    return null;
  }
  final position = value.items.isEmpty
      ? 0
      : target.clamp(0, ((value.items.length - 1) ~/ 20) * 20);
  final end = (position + 20).clamp(0, value.items.length);
  return (
    directory: CommunityDirectory(
      'mine',
      '',
      List.unmodifiable(value.items.sublist(position, end)),
      next: end < value.items.length ? '$end:$version' : value.next,
      cachedAtUtc: value.cachedAtUtc,
      cacheComplete: value.cacheComplete,
      displayVersion: version,
    ),
    after: position == 0 ? null : '$position:$version',
    previous: [
      for (var offset = 0; offset < position; offset += 20)
        offset == 0 ? null : '$offset:$version',
    ],
  );
}
