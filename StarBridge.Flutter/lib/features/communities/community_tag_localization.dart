import 'package:flutter/widgets.dart';

import '../../app/localization/app_strings.dart';
import 'community_creation_port.dart';
import 'legacy_community_tag_catalog.dart';

String _display(BuildContext context, String key, String fallback) {
  final value = AppStrings.of(context).text(key);
  return value == key ? fallback : value;
}

extension CommunityTagDisplay on CommunityTagOption {
  String localizedName(BuildContext context) =>
      _display(context, 'communities.tag.$id.name', name);

  String localizedDescription(BuildContext context) =>
      _display(context, 'communities.tag.$id.description', description);
}

extension CommunityTagCategoryDisplay on CommunityTagCategory {
  String localizedName(BuildContext context) =>
      _display(context, 'communities.tagCategory.$id.name', name);

  String localizedDescription(BuildContext context) =>
      _display(context, 'communities.tagCategory.$id.description', description);
}

/// Resolve legacy saved names before translating; never return display copy to
/// a storage or filtering contract. Unknown names are preserved verbatim.
String communityTagDisplayName(BuildContext context, String name) {
  for (final tag in LegacyCommunityTagCatalog.tags) {
    if (tag.id.toLowerCase() == name.toLowerCase() ||
        tag.name.toLowerCase() == name.toLowerCase()) {
      return tag.localizedName(context);
    }
  }
  return name;
}
