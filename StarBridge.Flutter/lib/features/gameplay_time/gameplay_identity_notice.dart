import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'gameplay_time_controller.dart';

/// The identity notice of the gameplay panel, for pages that people visit
/// even with playtime recording off (local game recognition). It reads the
/// same Host refusal as the gameplay panel and adds no new Host state.
class GameplayIdentityNotice extends StatelessWidget {
  const GameplayIdentityNotice({
    required this.controller,
    required this.onConfirmIdentity,
    super.key,
  });

  final GameplayTimeController controller;
  final Future<void> Function(BuildContext) onConfirmIdentity;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<GameplayTimeView>(
        valueListenable: controller,
        builder: (context, state, _) {
          if (!state.visible ||
              state.error != 'identityUnconfirmed' &&
                  !state.connectionUnavailable) {
            return const SizedBox.shrink();
          }
          final tokens = context.tokens;
          final strings = AppStrings.of(context);
          return Padding(
            padding: EdgeInsets.only(bottom: tokens.space.md),
            child: Column(
              key: const Key('gameplay-identity-notice'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.text(state.connectionUnavailable
                      ? 'gameplay.${state.pauseReason}'
                      : 'gameplay.identityError'),
                  style: TextStyle(color: tokens.colors.warning),
                ),
                if (!state.connectionUnavailable) ...[
                  SizedBox(height: tokens.space.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StarBridgeActionButton(
                      kind: StarBridgeActionKind.secondary,
                      controlKey: const Key('gameplay-identity-notice-confirm'),
                      onActivate: (_) => unawaited(onConfirmIdentity(context)),
                      child: Text(strings.text('gameplay.confirmIdentity')),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
}
