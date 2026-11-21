/// One line per page per minute for the opt-in "记录界面流畅度" diagnostics.
/// Static page routes, window shape and timings only: never account data or
/// page content.
final class FramePaceSummary {
  FramePaceSummary(String page) : _page = _clean(page);

  /// Frames over this total span count as visible stutter.
  static const slowUs = 33000;

  /// More than a 240 Hz screen draws in a minute. Past this, percentiles use
  /// the first frames only; counts and maxima still include every frame.
  static const maxFramesPerPage = 15000;

  String _page;
  final _frames = <String, _PageFrames>{};

  String get page => _page;
  set page(String value) => _page = _clean(value);

  static String _clean(String page) {
    final path = page.split('?').first.split('#').first;
    return path.isEmpty ? '/' : path;
  }

  /// [page] is the page the frame was drawn on, when it differs from the
  /// current one (timings arrive in batches, after a page may have changed).
  void frame({
    required int buildUs,
    required int rasterUs,
    required int totalUs,
    String? page,
  }) => (_frames[page == null ? _page : _clean(page)] ??= _PageFrames()).add(
    buildUs,
    rasterUs,
    totalUs,
  );

  /// The minute's lines, then starts the next minute. A minute without frames
  /// still writes the current page: a quiet window is also an answer.
  List<Map<String, Object?>> take({
    required DateTime now,
    required Map<String, Object?> context,
  }) {
    final pages = _frames.isEmpty ? {_page: _PageFrames()} : Map.of(_frames);
    _frames.clear();
    final at = now.toUtc().toIso8601String();
    return [
      for (final MapEntry(key: page, value: frames) in pages.entries)
        {
          'at': at,
          'page': page,
          ...context,
          'frames': frames.count,
          'over33': frames.slow,
          'rasterP50Ms': _at(frames.raster, .5),
          'rasterP90Ms': _at(frames.raster, .9),
          'rasterMaxMs': _ms(frames.rasterMax),
          'buildP50Ms': _at(frames.build, .5),
          'buildP90Ms': _at(frames.build, .9),
          'buildMaxMs': _ms(frames.buildMax),
        },
    ];
  }

  static double _at(List<int> values, double position) {
    if (values.isEmpty) return 0;
    final sorted = List.of(values)..sort();
    final index = ((sorted.length - 1) * position).round();
    return _ms(sorted[index]);
  }

  static double _ms(int us) => (us / 100).round() / 10;
}

final class _PageFrames {
  final build = <int>[];
  final raster = <int>[];
  int count = 0;
  int slow = 0;
  int buildMax = 0;
  int rasterMax = 0;

  void add(int buildUs, int rasterUs, int totalUs) {
    count++;
    if (totalUs > FramePaceSummary.slowUs) slow++;
    if (buildUs > buildMax) buildMax = buildUs;
    if (rasterUs > rasterMax) rasterMax = rasterUs;
    if (build.length >= FramePaceSummary.maxFramesPerPage) return;
    build.add(buildUs);
    raster.add(rasterUs);
  }
}
