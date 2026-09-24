import '../../design_system/icons/standard_icon.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_workspace_image.dart';

/// Public bundled system artwork, independent of organization/account media.
class CommunitySystemChoices extends StatelessWidget {
  const CommunitySystemChoices({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<String> selected;
  final ValueChanged<List<String>>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 540
            ? 3
            : constraints.maxWidth >= 280
            ? 2
            : 1;
        final width = ((constraints.maxWidth - 12 * (columns - 1)) / columns)
            .clamp(0.0, 280.0);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final id in const ['stanton', 'pyro', 'nyx'])
              Builder(
                builder: (context) {
                  final active = selected.contains(id);
                  final label = AppStrings.of(context).text(
                    'communities.option.systems.${id[0].toUpperCase()}${id.substring(1)}',
                  );
                  void toggle() {
                    final next = [...selected];
                    active ? next.remove(id) : next.add(id);
                    onChanged?.call(next);
                  }

                  return Semantics(
                    label: label,
                    button: true,
                    selected: active,
                    enabled: onChanged != null,
                    child: SizedBox(
                      key: ValueKey('community-system-$id'),
                      width: width,
                      child: Material(
                        color: active
                            ? tokens.colors.accentSoft
                            : tokens.surfaces.raised.fill,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: active
                                ? tokens.colors.accent
                                : tokens.surfaces.panel.border,
                            width: 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onChanged == null ? null : toggle,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AspectRatio(
                                aspectRatio: 2,
                                child: Image.asset(
                                  'assets/systems/$id.png',
                                  fit: BoxFit.cover,
                                  cacheWidth: 560,
                                  excludeFromSemantics: true,
                                  frameBuilder:
                                      (_, child, frame, synchronous) =>
                                          synchronous || frame != null
                                          ? child
                                          : const CommunityImageLoading(),
                                  errorBuilder: (_, _, _) => StandardIcon(
                                    StandardIconSemantic.public,
                                    size: 40,
                                    color: tokens.colors.textSecondary,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    StandardIcon(
                                      active
                                          ? StandardIconSemantic.checkCircle
                                          : StandardIconSemantic.circleOutline,
                                      color: active
                                          ? tokens.colors.accent
                                          : tokens.colors.textSecondary,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
