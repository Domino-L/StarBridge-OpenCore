import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_preset_sources.dart';
import 'overlay_scene_controller.dart';

/// Preview choices use Host-resolved IDs, never another implementation of the
/// automatic rule. Sample text stays local; this metadata grants no data access.
@immutable
final class OverlayPreviewSourcePresentation {
  const OverlayPreviewSourcePresentation(
    this.id,
    this.labelId,
    this.unavailable,
  );
  final String? id, labelId;
  final bool unavailable;

  static OverlayPreviewSourcePresentation? resolve(
    OverlayPresetSources? policy,
    OverlaySceneState? scenes,
    String moduleKey,
  ) {
    if (policy == null) return null;
    final module = switch (moduleKey) {
      'Notice' => OverlaySourceModule.notice,
      'Squads' => OverlaySourceModule.overview,
      'Members' => OverlaySourceModule.members,
      'Chat' => OverlaySourceModule.chat,
      'Events' => OverlaySourceModule.events,
      _ => null,
    };
    if (module == null) return null;
    String? choice(OverlaySourceBinding source) => switch (source.mode) {
      OverlaySourceMode.none => null,
      OverlaySourceMode.auto => 'auto',
      OverlaySourceMode.room => 'room',
      OverlaySourceMode.community =>
        source.ownerKey == scenes?.sourceOwnerKey &&
                scenes!.targets.any(
                  (target) => target.code == source.communityCode,
                )
            ? 'org:${source.communityCode}'
            : 'missing',
    };
    final ids = scenes?.resolvedSourceIds;
    String? actual(String selected) => selected == 'missing'
        ? null
        : ids?.containsKey(selected) == true
        ? ids![selected]
        : selected;
    final selected =
        scenes?.temporarySourceId ??
        choice(policy.binding) ??
        scenes?.accountPreferredId ??
        'auto';
    final base =
        scenes?.temporarySourceId == null &&
            policy.binding.mode == OverlaySourceMode.community &&
            actual(selected) == null
        ? actual('auto')
        : actual(selected);
    final override = choice(policy.forModule(module));
    if (module == OverlaySourceModule.chat && policy.chatSources.isNotEmpty) {
      final selected = policy.chatSources
          .map(choice)
          .whereType<String>()
          .toList();
      return OverlayPreviewSourcePresentation(
        'chatMultiple',
        'chatMultiple',
        selected.every((id) => actual(id) == null),
      );
    }
    final resolved = override == null ? base : actual(override);
    return OverlayPreviewSourcePresentation(
      resolved,
      override != null && (resolved != base || resolved == null)
          ? resolved ?? override
          : null,
      resolved == null,
    );
  }
}

class OverlayPreviewSourceScope extends StatelessWidget {
  const OverlayPreviewSourceScope({
    required this.sources,
    required this.child,
    this.scenes,
    super.key,
  });
  final OverlayPresetSources? sources;
  final ValueListenable<OverlaySceneState>? scenes;
  final Widget child;
  @override
  Widget build(BuildContext context) => scenes == null
      ? _SourceScope(sources: sources, child: child)
      : ValueListenableBuilder(
          valueListenable: scenes!,
          builder: (_, state, _) =>
              _SourceScope(sources: sources, scenes: state, child: child),
        );

  static OverlayPreviewSourcePresentation? of(
    BuildContext context,
    String module,
  ) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SourceScope>();
    return OverlayPreviewSourcePresentation.resolve(
      scope?.sources,
      scope?.scenes,
      module,
    );
  }

  static String label(BuildContext context, String id) {
    final strings = AppStrings.of(context);
    if (id.startsWith('org:')) {
      final scope = context.dependOnInheritedWidgetOfExactType<_SourceScope>();
      return scope?.scenes?.targets
              .where((t) => 'org:${t.code}' == id)
              .firstOrNull
              ?.name ??
          strings.text('overlay.source.missing');
    }
    return strings.text('overlay.source.${id == 'local' ? 'localName' : id}');
  }
}

class _SourceScope extends InheritedWidget {
  const _SourceScope({
    required this.sources,
    required super.child,
    this.scenes,
  });
  final OverlayPresetSources? sources;
  final OverlaySceneState? scenes;
  @override
  bool updateShouldNotify(_SourceScope oldWidget) =>
      sources != oldWidget.sources || scenes != oldWidget.scenes;
}

/// Bounded title badge uses the same tokens as the rest of the application.
class OverlayPreviewSourceTitle extends StatelessWidget {
  const OverlayPreviewSourceTitle({
    required this.moduleKey,
    required this.child,
    super.key,
  });
  final String moduleKey;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final id = OverlayPreviewSourceScope.of(context, moduleKey)?.labelId;
    if (id == null) return child;
    final tokens = context.tokens;
    return Row(
      children: [
        Expanded(child: child),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            key: Key('overlay-preview-source-$moduleKey'),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: tokens.colors.textSecondary.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              OverlayPreviewSourceScope.label(context, id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: tokens.colors.textSecondary,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
