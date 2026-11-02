import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_profile_controller.dart';
import 'community_profile_copy.dart';
import 'community_wide_image_crop.dart';
import 'community_wide_image_port.dart';

/// Banner and background editing. Both sit behind the one combined
/// `fleet.banner.edit` permission and only appear when the server has proved
/// it stores them (`wideImagesSupported`).
class CommunityProfileWideImages extends StatefulWidget {
  const CommunityProfileWideImages({
    required this.model,
    required this.port,
    required this.busy,
    required this.openDialog,
    required this.onChoosing,
    this.current = const {},
    super.key,
  });
  final CommunityProfileController model;
  final CommunityWideImagePort? port;
  final bool busy;
  final Future<String?> Function(Widget) openDialog;
  final ValueChanged<bool> onChoosing;

  /// Saved images by kind, shown until a draft replaces or clears them.
  final Map<String, Uint8List?> current;
  @override
  State<CommunityProfileWideImages> createState() =>
      _CommunityProfileWideImagesState();
}

class _CommunityProfileWideImagesState
    extends State<CommunityProfileWideImages> {
  final _decoded = <String, (String, Uint8List)>{};
  bool failed = false;
  String t(String key) => profileText(context, key);

  bool get canPick =>
      !widget.busy &&
      widget.model.profile!.canEditBanner &&
      widget.port?.canPickWideImage == true;

  Uint8List? draft(String kind) {
    final data = widget.model.changes['${kind}ImageData'] as String?;
    if (data == null) return null;
    final cached = _decoded[kind];
    if (cached != null && identical(cached.$1, data)) return cached.$2;
    final bytes = base64Decode(data.split(',').last);
    _decoded[kind] = (data, bytes);
    return bytes;
  }

  Future<void> pick(String kind) async {
    final port = widget.port;
    if (!canPick || port == null) return;
    widget.onChoosing(true);
    setState(() => failed = false);
    final model = widget.model;
    try {
      final source = await port.pickWideImage(kind);
      if (!mounted || model.invalidated || source == null) return;
      final image = await widget.openDialog(
        CommunityWideImageCrop(
          port: port,
          source: source,
          kind: kind,
          title: t(kind == 'banner' ? 'cropBanner' : 'cropBackground'),
        ),
      );
      if (mounted && !model.invalidated && image != null) {
        model.update('${kind}ImageData', image);
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (!model.invalidated) {
        try {
          await port.clearWideImage();
        } catch (_) {
          /* Account invalidation also clears the retained original. */
        }
      }
      widget.onChoosing(false);
    }
  }

  Widget row(String kind) {
    final profile = widget.model.profile!;
    final changes = widget.model.changes;
    final bytes = draft(kind);
    final clearing =
        changes['clear${kind == 'banner' ? 'Banner' : 'Background'}Image'] ==
        true;
    final exists = kind == 'banner' ? profile.hasBanner : profile.hasBackground;
    final status = bytes != null
        ? 'wideReplace'
        : clearing
        ? 'wideRemove'
        : exists
        ? 'wideSet'
        : 'wideEmpty';
    final aspect = communityWideImageAspect[kind]!;
    final shown = bytes ?? (clearing ? null : widget.current[kind]);
    const placeholder = Center(
      child: StandardIcon(StandardIconSemantic.image, size: 20),
    );
    return Padding(
      key: ValueKey('profile-wide-$kind'),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 192,
            child: AspectRatio(
              aspectRatio: aspect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.tokens.surfaces.panel.fill,
                  border: Border.all(
                    color: context.tokens.surfaces.panel.border,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: shown == null
                    ? placeholder
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Image.memory(
                          shown,
                          key: ValueKey(
                            bytes != null
                                ? 'profile-wide-$kind-draft'
                                : 'profile-wide-$kind-current',
                          ),
                          fit: BoxFit.cover,
                          cacheWidth: 384,
                          gaplessPlayback: true,
                          semanticLabel: t(kind),
                          errorBuilder: (_, _, _) => placeholder,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(kind), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  t(status),
                  key: ValueKey('profile-wide-$kind-status'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StarBridgeActionButton(
                      controlKey: ValueKey('profile-pick-$kind'),
                      onActivate: canPick ? (_) => pick(kind) : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const StandardIcon(
                            StandardIconSemantic.image,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t(
                              kind == 'banner'
                                  ? 'pickBanner'
                                  : 'pickBackground',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (exists || bytes != null)
                      StarBridgeActionButton(
                        kind: StarBridgeActionKind.quiet,
                        controlKey: ValueKey('profile-remove-$kind'),
                        onActivate:
                            !widget.busy && profile.canEditBanner && !clearing
                            ? (_) => bytes != null && !exists
                                  ? widget.model.update(
                                      '${kind}ImageData',
                                      null,
                                    )
                                  : widget.model.update(
                                      'clear${kind == 'banner' ? 'Banner' : 'Background'}Image',
                                      true,
                                    )
                            : null,
                        child: Text(
                          t(
                            kind == 'banner'
                                ? 'removeBanner'
                                : 'removeBackground',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('community-profile-wide-images'),
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: context.tokens.surfaces.raised.fill,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.tokens.surfaces.panel.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('wideImages'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              t('wideImagesHint'),
              key: const ValueKey('profile-wide-hint'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(height: 1.5),
            ),
            if (!widget.model.profile!.canEditBanner)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t('wideNoPermission'),
                  key: const ValueKey('profile-wide-no-permission'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            row('banner'),
            row('background'),
            if (failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t('imageFailed'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
