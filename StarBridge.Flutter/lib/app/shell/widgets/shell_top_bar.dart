import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../../platform/window/window_chrome_port.dart';
import '../../feature_registry.dart';
import '../../localization/app_strings.dart';
import '../chrome/shell_chrome_port.dart';
import '../chrome/shell_chrome_projection.dart';
import '../shell_layout_mode.dart';
import 'overlay_scene_selector.dart';
import 'top_bar_actions.dart';
import 'window_controls.dart';

class ShellTopBar extends StatelessWidget {
  const ShellTopBar({
    required this.selected,
    required this.topBarDestinations,
    required this.accountMenuDestinations,
    required this.projection,
    required this.shellChrome,
    required this.mode,
    required this.onSelect,
    required this.onAccountLogin,
    required this.onAccountLogout,
    required this.onAccountIssueAction,
    required this.windowChrome,
    super.key,
  });

  final FeatureDescriptor selected;
  final List<FeatureDescriptor> topBarDestinations;
  final List<FeatureDescriptor> accountMenuDestinations;
  final ShellChromeProjection projection;
  final ShellChromePort shellChrome;
  final ShellLayoutMode mode;
  final ValueChanged<FeatureDescriptor> onSelect;
  final VoidCallback onAccountLogin;
  final VoidCallback onAccountLogout;
  final VoidCallback onAccountIssueAction;
  final WindowChromePort windowChrome;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    return Container(
      height: tokens.density.topBarHeight,
      decoration: BoxDecoration(
        color: tokens.surfaces.chrome.fill,
        border: Border(
          bottom: BorderSide(
            color: tokens.surfaces.chrome.border,
            width: tokens.stroke.hairline,
          ),
        ),
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => unawaited(windowChrome.beginDrag()),
              onDoubleTap: () => unawaited(windowChrome.toggleMaximize()),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tokens.space.lg),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedSwitcher(
                    duration: tokens.motion.pointerMicro,
                    switchInCurve: tokens.motion.enterCurve,
                    switchOutCurve: tokens.motion.exitCurve,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previousChildren, ?currentChild],
                      );
                    },
                    child: Column(
                      key: ValueKey(selected.route),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.text(selected.labelKey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          strings.text(selected.descriptionKey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          OverlaySceneSelector(
            projection: projection.overlay,
            port: shellChrome,
            mode: mode,
          ),
          SizedBox(width: tokens.space.xs),
          TopBarActions(
            descriptors: topBarDestinations,
            accountMenuDestinations: accountMenuDestinations,
            projection: projection,
            mode: mode,
            onSelect: onSelect,
            onAccountLogin: onAccountLogin,
            onAccountLogout: onAccountLogout,
            onAccountIssueAction: onAccountIssueAction,
          ),
          SizedBox(width: tokens.space.xs),
          WindowControls(windowChrome: windowChrome),
        ],
      ),
    );
  }
}
