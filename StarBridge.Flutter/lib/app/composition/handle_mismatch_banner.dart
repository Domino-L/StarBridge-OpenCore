import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'handle_mismatch_module.dart';
import '../localization/app_strings.dart';

String handleMismatchPair(AppStrings strings, HandleMismatchNotice notice) =>
    strings
        .text('identity.notice.pair')
        .replaceAll('{expected}', notice.expectedHandle)
        .replaceAll(
          '{detected}',
          notice.detectedHandle ??
              strings.text('identity.notice.noObservation'),
        );

class HandleMismatchBanner extends StatelessWidget {
  const HandleMismatchBanner({
    required this.module,
    required this.onOpen,
    super.key,
  });
  final HandleMismatchModule module;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: module,
    builder: (context, _) {
      final notice = module.notice;
      if (notice == null) return const SizedBox.shrink();
      final strings = AppStrings.of(context), tokens = context.tokens;
      return Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          key: const ValueKey('handle-mismatch-banner'),
          color: tokens.colors.warningSoft,
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space.lg,
            vertical: tokens.space.xs,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('identity.notice.title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: tokens.colors.warning),
                  ),
                  Tooltip(
                    message: handleMismatchPair(strings, notice),
                    child: Text(
                      handleMismatchPair(strings, notice),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              );
              final action = TextButton(
                key: const ValueKey('handle-mismatch-action'),
                onPressed: onOpen,
                child: Text(strings.text('identity.notice.action')),
              );
              if (constraints.maxWidth < 650 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [content, action],
                );
              }
              return Row(
                children: [
                  Expanded(child: content),
                  action,
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
