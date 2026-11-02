import 'package:flutter/foundation.dart';

/// A view index over the original registry entries, not a new registry or store.
/// Keeps Flutter LicensePage's first package, case-sensitive identities,
/// case-insensitive ordering, and every many-to-many binding (even duplicates).
final class ThirdPartyLicenseIndex {
  ThirdPartyLicenseIndex(Iterable<LicenseEntry> entries) {
    final bindings = <String, List<LicenseEntry>>{};
    for (final entry in entries) {
      for (final name in entry.packages) {
        (bindings[name] ??= <LicenseEntry>[]).add(entry);
      }
    }
    final first = bindings.keys.firstOrNull;
    final names = bindings.keys.toList()
      ..sort((a, b) {
        if (a == first) return -1;
        if (b == first) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    packages = List.unmodifiable([
      for (final name in names)
        ThirdPartyLicensePackage._(name, bindings[name]!),
    ]);
  }
  late final List<ThirdPartyLicensePackage> packages;
}

final class ThirdPartyLicensePackage {
  ThirdPartyLicensePackage._(this.name, List<LicenseEntry> entries)
    : entries = List.unmodifiable(entries);
  final String name;
  final List<LicenseEntry> entries;
}
