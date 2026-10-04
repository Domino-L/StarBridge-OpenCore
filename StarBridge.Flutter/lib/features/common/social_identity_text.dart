import 'package:flutter/material.dart';

/// Keep a callsign and its game ID visually distinct without changing either
/// value in the account or search models.
class SocialIdentityText extends StatelessWidget {
  const SocialIdentityText({
    super.key,
    required this.callsign,
    required this.gameId,
    required this.callsignStyle,
    required this.gameIdColor,
    this.maxLines = 1,
  });

  final String callsign;
  final String gameId;
  final TextStyle? callsignStyle;
  final Color gameIdColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final id = gameId.trim();
    final showId = id.isNotEmpty && id != callsign.trim();
    final displayId = id.startsWith('@') ? id : '@$id';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: callsign, style: callsignStyle),
          if (showId)
            TextSpan(
              text: '  $displayId',
              style:
                  callsignStyle?.copyWith(
                    color: gameIdColor,
                    fontWeight: FontWeight.w400,
                  ) ??
                  TextStyle(color: gameIdColor),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
