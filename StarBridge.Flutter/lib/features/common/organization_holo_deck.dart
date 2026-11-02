import 'package:flutter/widgets.dart';

import 'organization_holo_art.dart';

/// What the holo header (upper screen) and the slim bar (lower screen) show
/// for one organization. The main fleet and communities each build one from
/// their own data; the shell itself knows nothing about either (user
/// decision 2026-10-23: organizations use exactly the main fleet's look).
class OrganizationHoloDeck {
  const OrganizationHoloDeck({
    required this.name,
    required this.code,
    this.banner,
    this.logo,
    this.tag,
    this.line,
    this.stats = const [],
    this.readouts = const [],
    this.readoutsKey,
  });

  final String name;

  /// The short code beside the name and in the large outline type (the
  /// main fleet's SID, a community's code).
  final String code;
  final OrganizationHoloArt? banner, logo;

  /// The viewer's place in the organization, in a skewed tag (main fleet:
  /// "我的官网职位 · Master · 5★"); null leaves the tag out.
  final String? tag;

  /// One line under the name (the current announcement, a description);
  /// [narrow] headers may give it two lines.
  final Widget Function(bool narrow)? line;

  /// The large counters on the deck and the small ones in the bar, in order.
  final List<OrganizationHoloStat> stats;

  /// Short facts read like the counters (label over value), placed before
  /// them on the deck only (user report 2026-10-28: a separate information
  /// row under the title left empty bands; facts belong in the deck).
  final List<OrganizationHoloReadout> readouts;
  final Key? readoutsKey;
}

class OrganizationHoloReadout {
  const OrganizationHoloReadout(
    this.label,
    this.value, {
    this.muted = false,
    this.onCopy,
    this.copyLabel = '',
    this.copyKey,
  });

  final String label, value;

  /// The value is a placeholder (nothing set or shown).
  final bool muted;
  final VoidCallback? onCopy;
  final String copyLabel;
  final Key? copyKey;
}

class OrganizationHoloStat {
  const OrganizationHoloStat(this.label, this.value, {this.accent = false});

  final String label;

  /// Null keeps the counter's place with a dash while the count is unknown.
  final int? value;

  /// Drawn in the accent colour (the online count).
  final bool accent;
}
