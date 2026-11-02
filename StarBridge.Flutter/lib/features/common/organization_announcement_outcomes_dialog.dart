import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../communities/community_announcements_copy.dart';
import '../communities/community_editor_surface.dart';
import '../direct_messages/communication_time_formatter.dart';
import 'organization_announcement_outcomes_controller.dart';

Future<void> showOrganizationAnnouncementOutcomes(
  BuildContext context,
  OrganizationAnnouncementOutcomesController controller,
) => showStarBridgeDialog<void>(
  context,
  useRootNavigator: false,
  builder: (_) =>
      OrganizationAnnouncementOutcomesDialog(controller: controller),
);

/// An account-own read surface. It never restores editing references or writes.
class OrganizationAnnouncementOutcomesDialog extends StatefulWidget {
  const OrganizationAnnouncementOutcomesDialog({
    required this.controller,
    super.key,
  });
  final OrganizationAnnouncementOutcomesController controller;
  @override
  State<OrganizationAnnouncementOutcomesDialog> createState() =>
      _OutcomesState();
}

class _OutcomesState extends State<OrganizationAnnouncementOutcomesDialog> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.controller;
    String t(String key) => communityAnnouncementText(context, key);
    return CommunityEditorSurface(
      embedded: false,
      child: SizedBox(
        width: 760,
        height: max(200, min(640, MediaQuery.sizeOf(context).height - 80)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: AnimatedBuilder(
            animation: model,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('ownOutcomes'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                StarBridgeActionButton(
                  controlKey: const Key('announcement-outcomes-refresh'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: model.loading || model.queryingRequestId != null
                      ? null
                      : (_) => model.refresh(),
                  child: Text(t('refresh')),
                ),
                if (model.loading) const LinearProgressIndicator(),
                if (model.error != null) Text(t(model.error!)),
                if (!model.complete) Text(t('outcomesIncomplete')),
                Expanded(
                  child: ListView(
                    children: [
                      if (model.complete && model.items.isEmpty)
                        Text(t('noOwnOutcomes')),
                      for (final row in model.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t(row.action == 'edit' ? 'save' : row.action),
                              ),
                              Text(
                                communicationTime(
                                  row.requestedAt,
                                  AppStrings.of(context).locale,
                                ),
                              ),
                              Text(
                                t(
                                  model.results[row.requestId]?.error ==
                                          'notFound'
                                      ? 'resultUnconfirmed'
                                      : switch (model
                                            .results[row.requestId]
                                            ?.status) {
                                          'accepted' => 'resultAccepted',
                                          'rejected' => 'resultRejected',
                                          _ => 'resultUnknown',
                                        },
                                ),
                              ),
                              StarBridgeActionButton(
                                controlKey: ValueKey(
                                  'announcement-query-${row.requestId}',
                                ),
                                kind: StarBridgeActionKind.quiet,
                                onActivate:
                                    model.loading ||
                                        model.queryingRequestId != null
                                    ? null
                                    : (_) => model.query(row.requestId),
                                child: Text(t('queryOriginal')),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: StarBridgeActionButton(
                    controlKey: const Key('announcement-outcomes-close'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: (source) =>
                        dismissStarBridgeDialog(context, source: source),
                    child: Text(t('close')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
