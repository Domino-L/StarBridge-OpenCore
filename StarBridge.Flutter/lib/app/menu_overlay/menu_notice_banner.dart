import 'dart:async';

import 'package:flutter/material.dart';
import '../../design_system/icons/standard_icon.dart';

import '../../platform/window/menu_notice.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';

/// Local expiry also clears the presentation if the primary engine disconnects.
class MenuNoticeBanner extends StatefulWidget {
  const MenuNoticeBanner({super.key, required this.notice});
  final MenuNotice notice;
  @override
  State<MenuNoticeBanner> createState() => _MenuNoticeBannerState();
}

class _MenuNoticeBannerState extends State<MenuNoticeBanner> {
  Timer? _expiry;
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    _expiry?.cancel();
    _visible = true;
    _expiry = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void didUpdateWidget(MenuNoticeBanner old) {
    super.didUpdateWidget(old);
    if (!identical(old.notice, widget.notice)) _arm();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_visible
      ? const SizedBox.shrink()
      : Semantics(
          liveRegion: true,
          child: StarBridgeSurface(
            role: SurfaceRole.panel,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.notice.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: () {
                        _expiry?.cancel();
                        setState(() => _visible = false);
                      },
                      icon: const StandardIcon(StandardIconSemantic.close),
                    ),
                  ],
                ),
                Text(
                  widget.notice.message,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
}
