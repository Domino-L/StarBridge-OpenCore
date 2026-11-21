import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Appends JSON lines with a hard size bound: the current file plus one older
/// file, each at most [maxBytes]. Writes are queued so lines never interleave.
final class FramePaceLog {
  FramePaceLog(this.directory, {this.maxBytes = 1024 * 1024});

  static const fileName = 'frame-pace.jsonl';
  static const olderFileName = 'frame-pace.1.jsonl';

  final Directory directory;
  final int maxBytes;
  Future<void> _queue = Future.value();

  File get current =>
      File('${directory.path}${Platform.pathSeparator}$fileName');
  File get older =>
      File('${directory.path}${Platform.pathSeparator}$olderFileName');

  /// Never throws: a diagnostic line that cannot be written is dropped. Each
  /// line is bounded and rotated on its own, so one oversized line never takes
  /// the others with it.
  Future<void> append(List<Map<String, Object?>> lines) {
    if (lines.isEmpty) return _queue;
    final encoded = <List<int>>[];
    for (final line in lines) {
      try {
        encoded.add(utf8.encode('${jsonEncode(line)}\n'));
      } catch (_) {}
    }
    return _queue = _queue
        .then((_) async {
          for (final bytes in encoded) {
            try {
              await _write(bytes);
            } catch (_) {}
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _write(List<int> bytes) async {
    if (bytes.length > maxBytes) return;
    await directory.create(recursive: true);
    final file = current;
    final size = await file.exists() ? await file.length() : 0;
    if (size + bytes.length > maxBytes) {
      final previous = older;
      if (await previous.exists()) await previous.delete();
      if (await file.exists()) await file.rename(previous.path);
    }
    await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  /// Lets a caller (and tests) wait for queued lines.
  Future<void> get idle => _queue;
}
