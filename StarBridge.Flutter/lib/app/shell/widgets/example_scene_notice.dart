import 'package:flutter/material.dart';

import '../../../design_system/icons/icon_semantic.dart';
import '../../../design_system/icons/starbridge_icon.dart';
import '../../../design_system/tokens/starbridge_tokens.dart';
import '../../localization/app_strings.dart';
import '../../runtime/example_scene_control.dart';

class ExampleSceneNotice extends StatelessWidget {
  const ExampleSceneNotice({required this.control, super.key});

  final ExampleSceneControl control;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    return Container(
      key: const Key('example-scene-notice'),
      constraints: BoxConstraints(minHeight: tokens.density.statusBarHeight),
      padding: EdgeInsetsDirectional.only(
        start: tokens.space.lg,
        end: tokens.space.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.warningSoft,
        border: Border(
          bottom: BorderSide(
            color: tokens.colors.warning.withValues(alpha: 0.55),
            width: tokens.stroke.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          StarBridgeIcon(
            StarBridgeIconSemantic.scene,
            size: tokens.icons.small,
            color: tokens.colors.warning,
          ),
          SizedBox(width: tokens.space.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${strings.text('exampleScene.notice.title')}  ',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.colors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: strings.text('exampleScene.notice.body'),
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: tokens.colors.textSecondary),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            key: const Key('example-scene-notice-exit'),
            onPressed: control.onToggle,
            style: TextButton.styleFrom(
              foregroundColor: tokens.colors.warning,
              minimumSize: Size(0, tokens.density.statusBarHeight),
              padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
            ),
            child: Text(strings.text('exampleScene.exit')),
          ),
        ],
      ),
    );
  }
}
