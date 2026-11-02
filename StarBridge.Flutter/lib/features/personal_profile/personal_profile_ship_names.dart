import 'package:flutter/widgets.dart';

import 'personal_profile_models.dart';

abstract final class PersonalProfileShipNames {
  static String primary(
    BuildContext context,
    PersonalProfileShipIdentity identity,
  ) => identity.nickname?.trim().isNotEmpty == true
      ? identity.nickname!.trim()
      : model(context, identity);

  static String model(
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
    if (identity.nickname?.trim().isNotEmpty == true) {
      return model(context, identity);
    }
    final primaryName = primary(context, identity);
    return primaryName == identity.englishName ? null : identity.englishName;
  }
}
