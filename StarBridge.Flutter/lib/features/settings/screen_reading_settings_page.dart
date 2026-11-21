import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../app/preferences/app_preferences_port.dart';
import '../../app/preferences/app_preferences_projection.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'general_settings_motion.dart';
import 'general_settings_own_health.dart';

/// "屏幕读取"：本机设置里单独的一类（用户 11-10："甚至可以在设置里单独放一个屏幕读取类设置"）。
/// 每项读屏功能一个开关、一段说明；现在只有"读取自己的血量"。默认全部关闭。
class ScreenReadingSettingsPage extends StatelessWidget {
  const ScreenReadingSettingsPage({required this.preferences, super.key});

  final AppPreferencesPort preferences;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return GeneralSettingsMotion(
      preferences: preferences,
      builder: (context, motion) => ValueListenableBuilder<AppPreferencesProjection>(
        valueListenable: preferences.projection,
        builder: (context, projection, _) => SingleChildScrollView(
          key: const Key('settings-screen-reading'),
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
                  Text(
                    strings.text('settings.screenReading'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: tokens.space.xs),
                  Text(
                    strings.text('settings.screenReading.description'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                  SizedBox(height: tokens.space.lg),
                  StarBridgeSurface(
                    role: SurfaceRole.panel,
                    padding: EdgeInsets.all(tokens.space.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GeneralSettingsOwnHealth(
                          value: projection.effective.readOwnHealth,
                          enabled: projection.canEdit,
                          onChanged: (value) => motion.run(
                            () => preferences.setReadOwnHealth(value),
                          ),
                        ),
                        SizedBox(height: tokens.space.md),
                        // 子开关：只在读血打开时能改（用户 11-13，默认关）。
                        GeneralSettingsOwnHealthBackground(
                          value: projection.effective.readOwnHealthInBackground,
                          enabled: projection.canEdit &&
                              projection.effective.readOwnHealth,
                          onChanged: (value) => motion.run(
                            () => preferences.setReadOwnHealthInBackground(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
