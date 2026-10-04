import '../../features/communities/community_fleet_summary.dart';
import '../../features/communities/community_ship_statistics.dart';

import 'package:flutter/foundation.dart';

/// Bounded aggregate snapshot; never transports source inventory/access refs.
final class MenuFleetSummary implements CommunityFleetSummary {
  MenuFleetSummary._(
    this.shipCount,
    this.modelCount,
    this.sharingMemberCount,
    this.pricedCount,
    this.totalCents,
    this.sizes,
    this.roles,
    this.matrix,
  );
  @override
  final int shipCount, modelCount, sharingMemberCount, pricedCount, totalCents;
  @override
  final Map<String, int> sizes, roles;
  final Map<String, Map<String, int>> matrix;
  @override
  int countAt(String size, String role) => matrix[size]?[role] ?? 0;
  @override
  bool operator ==(Object other) =>
      other is MenuFleetSummary &&
      shipCount == other.shipCount &&
      modelCount == other.modelCount &&
      sharingMemberCount == other.sharingMemberCount &&
      pricedCount == other.pricedCount &&
      totalCents == other.totalCents &&
      mapEquals(sizes, other.sizes) &&
      mapEquals(roles, other.roles) &&
      matrix.keys.every((size) => mapEquals(matrix[size], other.matrix[size]));
  @override
  int get hashCode => Object.hash(
    shipCount,
    modelCount,
    sharingMemberCount,
    pricedCount,
    totalCents,
  );

  static Map<String, Object?> project(CommunityFleetSummary stats) => {
    'shipCount': stats.shipCount,
    'modelCount': stats.modelCount,
    'sharingMemberCount': stats.sharingMemberCount,
    'pricedCount': stats.pricedCount,
    'totalCents': stats.totalCents,
    'sizes': stats.sizes,
    'roles': stats.roles,
    'matrix': {
      for (final size in stats.sizes.keys)
        size: {
          for (final role in stats.roles.keys) role: stats.countAt(size, role),
        },
    },
  };

  static MenuFleetSummary? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) throw const FormatException();
    int number(
      Object? value, [
      int maximum = CommunityFleetSummary.maximumShips,
    ]) {
      if (value is! int || value < 0 || value > maximum) {
        throw const FormatException();
      }
      return value;
    }

    Map<String, int> counts(Object? value, List<String> keys) {
      if (value is! Map ||
          value.length > keys.length ||
          value.keys.any((key) => !keys.contains(key))) {
        throw const FormatException();
      }
      return Map.unmodifiable({
        for (final entry in value.entries)
          entry.key as String: number(entry.value),
      });
    }

    final sizes = counts(raw['sizes'], CommunityShipStatistics.sizeOrder);
    final roles = counts(raw['roles'], CommunityShipStatistics.roleOrder);
    final matrix = raw['matrix'];
    if (matrix is! Map ||
        matrix.length != sizes.length ||
        matrix.keys.any((key) => !sizes.containsKey(key))) {
      throw const FormatException();
    }
    final rows = <String, Map<String, int>>{
      for (final size in sizes.keys)
        size: counts(matrix[size], roles.keys.toList()),
    };
    int sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);
    final total = number(raw['shipCount']);
    final models = number(raw['modelCount']),
        owners = number(raw['sharingMemberCount']);
    final priced = number(raw['pricedCount']);
    if (sum(sizes.values) != total ||
        sum(roles.values) != total ||
        models > total ||
        owners > total ||
        priced > total ||
        sizes.keys.any((size) => sum(rows[size]!.values) != sizes[size]) ||
        roles.keys.any(
          (role) =>
              sum(rows.values.map((row) => row[role] ?? 0)) != roles[role],
        )) {
      throw const FormatException();
    }
    return MenuFleetSummary._(
      total,
      models,
      owners,
      priced,
      number(raw['totalCents'], 9007199254740991),
      sizes,
      roles,
      Map.unmodifiable(rows),
    );
  }
}
