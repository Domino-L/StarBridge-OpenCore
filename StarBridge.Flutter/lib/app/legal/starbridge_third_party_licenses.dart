import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_strings.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_page_route.dart';
import 'third_party_license_browser.dart';

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
    (asset: 'assets/font-licenses/LICENSE-Saira.txt', package: 'Saira'),
    (asset: 'assets/font-licenses/LICENSE-Rajdhani.txt', package: 'Rajdhani'),
    (
      asset: 'assets/legal/TRADING-CATEGORY-ICONS.txt',
      package: 'Trading weapon icon / John Colburn / Game-icons.net',
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
    final navigator = Navigator.of(context);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    navigator.push<void>(
      StarBridgePageRoute<void>.fromContext(
        context,
        source: StarBridgeActivationOrigin.sourceOf(context),
        builder: (_) => themes.wrap(
          ThirdPartyLicenseBrowser(
            applicationName: strings.text('app.name'),
            applicationLegalese: strings.text('help.legal.licenses.legalese'),
          ),
        ),
      ),
    );
  }
}
