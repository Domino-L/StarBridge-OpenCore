import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/routing/open_destination_intent.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'settings_capability_overview.dart';
import 'settings_models.dart';
import 'settings_entry_dialog.dart';
import 'client_version_dialog.dart';
import 'about_legal_settings_page.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';

/// Reuses existing entry routing; grouping does not enable unavailable services.
class GeneralSettingsDataSections extends StatelessWidget {
  const GeneralSettingsDataSections({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final locale = strings.locale;
    final traditional =
        locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
    final english = locale.languageCode == 'en';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlannedSettingsCapabilities(
          section: SettingsSection.generalData,
          capabilityIds: const {'local-data-management', 'local-data-storage'},
          title: english
              ? 'Local data'
              : traditional
              ? '本機資料'
              : '本地数据',
          showIntro: false,
        ),
        SizedBox(height: context.tokens.space.md),
        PlannedSettingsCapabilities(
          section: SettingsSection.generalData,
          capabilityIds: const {'entitlement-redemption'},
          title: english
              ? 'Redemption'
              : traditional
              ? '兌換'
              : '兑换',
          showIntro: false,
        ),
        SizedBox(height: context.tokens.space.md),
        PlannedSettingsCapabilities(
          section: SettingsSection.generalData,
          capabilityIds: const {'application-updates'},
          title: english
              ? 'Application'
              : traditional
              ? '應用資訊'
              : '应用信息',
          showIntro: false,
        ),
        SizedBox(height: context.tokens.space.sm),
        Wrap(
          spacing: context.tokens.space.sm,
          runSpacing: context.tokens.space.sm,
          children: [
            OutlinedButton(
              key: const Key('general-overlay-settings'),
              onPressed:
                  Actions.maybeFind<OpenDestinationIntent>(context) == null
                  ? null
                  : () => Actions.invoke(
                      context,
                      const OpenDestinationIntent('/overlay'),
                    ),
              child: Text(strings.text('navigation.overlay')),
            ),
            ClientVersionButton(
              open: SettingsEntryOverrides.of(context)['client-version'],
            ),
            OutlinedButton(
              key: const Key('general-about-application'),
              onPressed: () {
                final openers = SettingsEntryOverrides.of(context);
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => SettingsEntryOverrides(
                      openers: openers,
                      child: Scaffold(
                        appBar: AppBar(
                          leading: Builder(
                            builder: (routeContext) => IconButton(
                              key: const Key('general-about-back'),
                              tooltip: MaterialLocalizations.of(routeContext)
                                  .closeButtonTooltip,
                              icon: const StarBridgeIcon(
                                StarBridgeIconSemantic.windowClose,
                              ),
                              onPressed: () => Navigator.of(routeContext).pop(),
                            ),
                          ),
                          title: Text(
                            english
                                ? 'About'
                                : traditional
                                ? '關於應用'
                                : '关于应用',
                          ),
                        ),
                        body: const AboutLegalSettingsPage(),
                      ),
                    ),
                  ),
                );
              },
              child: Text(
                english
                    ? 'About'
                    : traditional
                    ? '關於應用'
                    : '关于应用',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
