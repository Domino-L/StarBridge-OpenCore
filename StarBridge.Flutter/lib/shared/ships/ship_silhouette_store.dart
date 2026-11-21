import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const shipSilhouetteAsset = 'assets/ships/catalog-silhouettes.bin';

/// One ship in the fixed 0..[ShipSilhouettePack.grid] contour grid, nose up.
class ShipSilhouette {
  ShipSilhouette._(this.outline, this.raised);
  final Path outline, raised;
}

/// Parsed optional contour pack. Paths are built once per ship that is shown,
/// so memory stays bounded by the fixed inventory.
class ShipSilhouettePack {
  ShipSilhouettePack._(this.grid, this._rows, this._byKey, this._points);

  /// Throws [FormatException] for anything but a complete version-one pack.
  factory ShipSilhouettePack.parse(ByteData bytes) {
    if (bytes.lengthInBytes < 8 ||
        bytes.getUint32(0, Endian.big) != 0x5342534C) {
      throw const FormatException('ship silhouette header');
    }
    final length = bytes.getUint32(4, Endian.little);
    if (8 + length > bytes.lengthInBytes) {
      throw const FormatException('ship silhouette index');
    }
    final index = jsonDecode(
      utf8.decode(bytes.buffer.asUint8List(bytes.offsetInBytes + 8, length)),
    ) as Map<String, dynamic>;
    final byKey = <String, int>{};
    final rows = <_SilhouetteRow>[];
    var cursor = 0;
    for (final ship in index['ships'] as List<dynamic>) {
      final row = ship as Map<String, dynamic>;
      final outline = (row['outline'] as List<dynamic>).cast<int>();
      final raised = (row['mid'] as List<dynamic>).cast<int>();
      for (final key in row['keys'] as List<dynamic>) {
        byKey[key as String] = rows.length;
      }
      rows.add(_SilhouetteRow(cursor, outline, raised));
      for (final loop in outline) {
        cursor += loop;
      }
      for (final loop in raised) {
        cursor += loop;
      }
    }
    final start = 8 + length + (8 + length).remainder(2);
    if (start + cursor * 4 != bytes.lengthInBytes) {
      throw const FormatException('ship silhouette points');
    }
    return ShipSilhouettePack._(
      (index['grid'] as num).toDouble(),
      rows,
      byKey,
      ByteData.sublistView(bytes, start),
    );
  }

  final double grid;
  final List<_SilhouetteRow> _rows;
  final Map<String, int> _byKey;
  final ByteData _points;
  final Map<int, ShipSilhouette> _built = {};

  /// First name that matches wins, so pass the most exact identity first.
  ShipSilhouette? find(Iterable<String?> names) {
    for (final name in names) {
      final row = _byKey[ShipSilhouetteStore.normalize(name)];
      if (row != null) return _built[row] ??= _build(_rows[row]);
    }
    return null;
  }

  ShipSilhouette _build(_SilhouetteRow row) {
    var at = row.start * 4;
    Path loops(List<int> lengths) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final length in lengths) {
        for (var i = 0; i < length; i++, at += 4) {
          final x = _points.getUint16(at, Endian.little).toDouble();
          final y = _points.getUint16(at + 2, Endian.little).toDouble();
          i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        path.close();
      }
      return path;
    }

    final outline = loops(row.outline);
    return ShipSilhouette._(outline, loops(row.raised));
  }
}

class _SilhouetteRow {
  const _SilhouetteRow(this.start, this.outline, this.raised);
  final int start;
  final List<int> outline, raised;
}

enum ShipSilhouetteLoad { pending, ready, absent }

/// Loads the optional pack once. Public source has no pack and a damaged pack
/// counts as absent, so both keep the category artwork.
class ShipSilhouetteStore extends ChangeNotifier {
  ShipSilhouetteStore._();
  static final instance = ShipSilhouetteStore._();

  /// Test runs never read a pack left in a developer's asset folder, so
  /// goldens do not depend on private local media.
  static final _isTestRun = Platform.environment.containsKey('FLUTTER_TEST');

  static String normalize(String? value) =>
      (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9一-鿿]'), '');

  ShipSilhouetteLoad _load = ShipSilhouetteLoad.pending;
  ShipSilhouettePack? _pack;
  bool _started = false;

  ShipSilhouetteLoad get load =>
      _isTestRun && _pack == null ? ShipSilhouetteLoad.absent : _load;
  ShipSilhouettePack? get pack => _pack;

  void ensureLoaded() {
    if (_started || _isTestRun) return;
    _started = true;
    loadFrom(rootBundle);
  }

  /// Any failure, including a missing asset in public source, means absent.
  @visibleForTesting
  Future<void> loadFrom(AssetBundle bundle) async {
    ShipSilhouettePack? pack;
    try {
      pack = ShipSilhouettePack.parse(await bundle.load(shipSilhouetteAsset));
    } on Object {
      pack = null;
    }
    debugUse(pack);
  }

  @visibleForTesting
  void debugUse(ShipSilhouettePack? pack) {
    _pack = pack;
    _load = pack == null ? ShipSilhouetteLoad.absent : ShipSilhouetteLoad.ready;
    notifyListeners();
  }
}
