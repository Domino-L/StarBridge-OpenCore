import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../common/social_read_activity.dart';
import 'communities_module.dart';

class CommunityDirectoryNotice extends StatelessWidget {
  const CommunityDirectoryNotice(this.model, {this.progress, super.key});
  final CommunitiesModule model;
  final Widget? progress;
  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.of(context).text('communities.$key');
    final at = model.directory?.cachedAtUtc?.toLocal();
    final material = MaterialLocalizations.of(context);
    final caption = at == null
        ? null
        : t('shortcutsCached').replaceAll(
            '{time}',
            '${material.formatMediumDate(at)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (model.showDirectoryProgress)
            progress ??
                SocialReadActivity(
                  source: InteractionSource.programmatic,
                  opening: false,
                  label: t('loading'),
                  height: 4,
                ),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (model.error != null) Text(t(model.error!)),
              if (caption != null) Text(caption),
              if (model.error != null)
                StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  controlKey: const Key('community-directory-retained-retry'),
                  onActivate: model.busy ? null : (_) => model.refresh(),
                  child: Text(t('retry')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
