import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../features/tools/catalog_port.dart';
import '../features/tools/catalog_recent.dart';

/// A bounded local UI preference, separate from all Host-owned business files.
/// Follows the queued UTF-8 file pattern used by the local diagnostics store.
final class CatalogRecentFileStore implements CatalogRecentStore {
  CatalogRecentFileStore(this.directory);
  final Directory directory;
  static CatalogRecentStore? forDevice() {
    final root = Platform.environment['LOCALAPPDATA'];
    return root == null
        ? null
        : CatalogRecentFileStore(
            Directory(
              '$root${Platform.pathSeparator}StarBridge${Platform.pathSeparator}ui-catalog-recent',
            ),
          );
  }

  File _file(String owner) => File(
    '${directory.path}${Platform.pathSeparator}${sha256.convert(utf8.encode(owner))}.json',
  );
  @override
  Future<CatalogRow> read(String owner) async {
    final file = _file(owner);
    if (!await file.exists()) return {};
    if (await file.length() > 16384) {
      throw const FormatException('Oversized UI history');
    }
    final value = jsonDecode(await file.readAsString(encoding: utf8));
    if (value is! Map || value['version'] != 1) {
      throw const FormatException('Invalid UI history');
    }
    return Map<String, Object?>.from(value);
  }

  @override
  Future<void> write(String owner, CatalogRow value) async {
    final bytes = utf8.encode(jsonEncode({'version': 1, ...value}));
    if (bytes.length > 16384) {
      throw const FormatException('Oversized UI history');
    }
    await directory.create(recursive: true);
    final target = _file(owner), pending = File('${_file(owner).path}.tmp');
    await pending.writeAsBytes(bytes, flush: true);
    await pending.rename(target.path);
  }
}
