import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

class OverlaySettingsLoading extends StatelessWidget {
  const OverlaySettingsLoading({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: context.tokens.space.md),
          Text(AppStrings.of(context).text('overlay.loading')),
        ],
      ),
    ),
  );
}
