import 'package:flutter/material.dart';

import '../../app/legal/cig_fankit_notice.dart';
import '../../app/localization/app_strings.dart';
import '../../design_system/brand/starbridge_app_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'client_license_dialog.dart';
import 'client_version_dialog.dart';
import 'settings_entry_dialog.dart';

class AboutLegalSettingsPage extends StatelessWidget {
  const AboutLegalSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.space.xl,
        tokens.space.lg,
        tokens.space.xl,
        tokens.space.xxl,
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tokens.density.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const StarBridgeAppIcon(
                    key: Key('settings-about-app-icon'),
                    size: 72,
                  ),
                  SizedBox(width: tokens.space.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.text('app.name'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        SizedBox(height: tokens.space.xxs),
                        Text(
                          strings.text('legal.about.description'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: tokens.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.lg),
              Text(
                strings.text('legal.page.title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: tokens.space.xs),
              Text(
                strings.text('legal.page.description'),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
              SizedBox(height: tokens.space.lg),
              ClientVersionButton(
                open: SettingsEntryOverrides.of(context)['client-version'],
              ),
              SizedBox(height: tokens.space.md),
              ClientLicenseButton(
                open: SettingsEntryOverrides.of(context)['client-license'],
              ),
              SizedBox(height: tokens.space.md),
              const StarBridgeSurface(
                key: Key('settings-cig-fankit-notice'),
                role: SurfaceRole.raised,
                child: CigFankitNoticeContent(),
              ),
              SizedBox(height: tokens.space.md),
              StarBridgeSurface(
                role: SurfaceRole.panel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('legal.distribution.title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.space.xs),
                    Text(
                      strings.text('legal.distribution.body'),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: tokens.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
