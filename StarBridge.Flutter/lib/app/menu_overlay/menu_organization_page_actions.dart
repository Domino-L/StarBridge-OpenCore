import 'menu_feature_session.dart';
import 'menu_overlay_text.dart';

List<Map<String, Object?>> menuOrganizationPageActions(
  MenuFeatureSession session,
  int? next,
  int offset,
  void Function(int) select,
) => [
  if (next != null)
    session.button(
      const MenuOverlayText('menu.overlay.organizations.next'),
      (_) async => select(next),
      role: 'nextPage',
    ),
  if (offset > 0)
    session.button(
      const MenuOverlayText('menu.overlay.organizations.first'),
      (_) async => select(0),
      role: 'firstPage',
    ),
];
