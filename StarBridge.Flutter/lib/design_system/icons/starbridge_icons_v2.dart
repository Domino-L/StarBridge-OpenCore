// Approved Claude IconSystemV2 artwork; geometry retained without redesign.
// Split by responsibility to meet the application architecture gates.
import 'starbridge_icons_v2_navigation.dart';
import 'starbridge_icons_v2_social.dart';
import 'starbridge_icons_v2_permissions.dart';
import 'starbridge_icons_v2_game.dart';
import 'starbridge_icons_v2_data.dart';
import 'starbridge_icons_v2_actions.dart';
import 'starbridge_icons_v2_status.dart';
import 'starbridge_icons_v2_directions.dart';
import 'starbridge_icons_v2_spec.dart';
export 'starbridge_icons_v2_spec.dart';
export 'starbridge_icons_v2_pen.dart';

final List<IconSpec> catalog = List.unmodifiable([
  ...navigationIconsV2,
  ...socialIconsV2,
  ...permissionsIconsV2,
  ...gameIconsV2,
  ...dataIconsV2,
  ...actionsIconsV2,
  ...statusIconsV2,
  ...directionsIconsV2,
]);
final Map<String, IconSpec> catalogByKey = Map.unmodifiable({
  for (final s in catalog) s.key: s,
});
final Map<String, IconSpec> catalogBySemantic = Map.unmodifiable({
  for (final s in catalog)
    for (final reference in s.replaces) reference: s,
});
