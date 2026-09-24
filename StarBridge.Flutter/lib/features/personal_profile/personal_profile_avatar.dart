import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/embedded_avatar.dart';

class PersonalProfileAvatar extends StatelessWidget {
  const PersonalProfileAvatar({
    required this.callSign,
    required this.styleIndex,
    required this.size,
    this.imageData,
    super.key,
  });

  final String callSign;
  final int styleIndex;
  final double size;
  final String? imageData;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      clipBehavior: Clip.antiAlias,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: tokens.shape.large),
      child: EmbeddedAvatar(
        source: imageData,
        fallback: Text(
          callSign.trim().isEmpty
              ? '?'
              : callSign.trim().characters.first.toUpperCase(),
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: tokens.colors.textPrimary),
        ),
      ),
    );
  }
}
