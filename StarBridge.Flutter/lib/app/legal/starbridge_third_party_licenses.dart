import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_strings.dart';

/// Bundled notices are registered by bootstrap, once per application isolate.
/// Opening the platform license browser never mutates the license registry.
abstract final class StarBridgeThirdPartyLicenses {
  static const _bundledLicenses = <({String asset, String package})>[
    (
      asset: 'assets/font-licenses/LICENSE-Source-Sans-3.md',
      package: 'Source Sans 3',
    ),
    (
      asset: 'assets/font-licenses/LICENSE-Source-Han-Sans.txt',
      package: 'Source Han Sans CN',
    ),
    (
      asset: 'assets/font-licenses/LICENSE-Source-Code-Pro.md',
      package: 'Source Code Pro',
    ),
  ];

  static void registerAtStartup() {
    LicenseRegistry.addLicense(() async* {
      for (final license in _bundledLicenses) {
        final text = await rootBundle.loadString(license.asset);
        yield LicenseEntryWithLineBreaks([license.package], text);
      }
    });
  }

  static void show(BuildContext context) {
    final strings = AppStrings.of(context);
    showLicensePage(
      context: context,
      applicationName: strings.text('app.name'),
      applicationLegalese: strings.text('help.legal.licenses.legalese'),
    );
  }
}
