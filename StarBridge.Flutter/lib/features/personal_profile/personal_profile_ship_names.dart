import 'package:flutter/widgets.dart';

import 'personal_profile_models.dart';

abstract final class PersonalProfileShipNames {
  static String primary(
    BuildContext context,
    PersonalProfileShipIdentity identity,
  ) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode != 'zh') {
      return identity.englishName;
    }
    final useTraditional =
        locale.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(locale.countryCode);
    final localized = useTraditional
        ? identity.traditionalChineseName
        : identity.simplifiedChineseName;
    return localized.trim().isEmpty ? identity.englishName : localized;
  }

  static String? secondary(
    BuildContext context,
    PersonalProfileShipIdentity identity,
  ) {
    final primaryName = primary(context, identity);
    return primaryName == identity.englishName ? null : identity.englishName;
  }
}
