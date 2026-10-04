import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// Shared information/menu settings structure, including the compact inspector.
class OverlayWorkspaceFrame extends StatelessWidget {
  const OverlayWorkspaceFrame({
    super.key,
    required this.navigation,
    required this.selector,
    required this.preview,
    required this.settings,
    required this.settingsOpen,
    required this.onToggleSettings,
    required this.toggleKey,
  });

  final Widget navigation, selector, preview, settings;
  final bool settingsOpen;
  final VoidCallback onToggleSettings;
  final Key toggleKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 1248) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 190, child: navigation),
            const SizedBox(width: 12),
            Expanded(child: preview),
            const SizedBox(width: 12),
            SizedBox(width: 380, child: settings),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: selector),
              const SizedBox(width: 8),
              OutlinedButton(
                key: toggleKey,
                onPressed: onToggleSettings,
                child: Text(
                  AppStrings.of(context).text(
                    settingsOpen
                        ? 'overlay.workspace.hideSettings'
                        : 'overlay.workspace.showSettings',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: preview),
                // Keep independent editors and their unsaved input mounted.
                Positioned.fill(
                  child: Offstage(
                    offstage: !settingsOpen,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Material(
                          elevation: 8,
                          color: context.tokens.surfaces.panel.fill,
                          child: settings,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
