import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import 'legacy_profile_migration.dart';

Future<LegacyProfileImportSelection?> showLegacyProfileImportDialog(
  BuildContext context,
) {
  final modules = <String>{};
  final replace = <String>{};
  var callSign = false;
  var avatar = false;
  var full = false;
  String text(String key) => AppStrings.of(context).text('migration.$key');
  return showDialog<LegacyProfileImportSelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(text('selectTitle')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text('selectBody')),
                CheckboxListTile(
                  key: const Key('import-select-full'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(text('selectFull')),
                  subtitle: Text(text('fullScope')),
                  value: full,
                  onChanged: (value) => update(() => full = value == true),
                ),
                CheckboxListTile(
                  key: const Key('import-select-callsign'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(text('selectCallSign')),
                  value: callSign,
                  onChanged: full
                      ? null
                      : (value) => update(() => callSign = value == true),
                ),
                CheckboxListTile(
                  key: const Key('import-select-avatar'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(text('selectAvatar')),
                  value: avatar,
                  onChanged: full
                      ? null
                      : (value) => update(() => avatar = value == true),
                ),
                const Divider(),
                for (final id in [
                  'favorite-ships',
                  'hangar-summary',
                  'skilled-roles',
                ]) ...[
                  CheckboxListTile(
                    key: Key('import-select-$id'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(text('module.$id')),
                    value: modules.contains(id),
                    onChanged: full
                        ? null
                        : (value) => update(() {
                            if (value == true) {
                              modules.add(id);
                            } else {
                              modules.remove(id);
                              replace.remove(id);
                            }
                          }),
                  ),
                  if (modules.contains(id))
                    CheckboxListTile(
                      key: Key('import-replace-$id'),
                      contentPadding: const EdgeInsets.only(left: 24),
                      title: Text(text('replaceModule')),
                      value: replace.contains(id),
                      onChanged: full
                          ? null
                          : (value) => update(() {
                              value == true
                                  ? replace.add(id)
                                  : replace.remove(id);
                            }),
                    ),
                ],
                const Divider(),
                Text(
                  text(full ? 'fullScope' : 'moduleSafety'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('import-select-cancel'),
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(text('cancel')),
          ),
          FilledButton(
            key: const Key('import-select-preview'),
            onPressed: !full && modules.isEmpty && !callSign && !avatar
                ? null
                : () => Navigator.pop(
                    dialogContext,
                    LegacyProfileImportSelection(
                      modules: full ? const [] : modules.toList(),
                      replaceModules: full ? const [] : replace.toList(),
                      useLegacyCallSign: !full && callSign,
                      useLegacyAvatar: !full && avatar,
                      replaceAllDisplayContent: full,
                    ),
                  ),
            child: Text(text('preview')),
          ),
        ],
      ),
    ),
  );
}
