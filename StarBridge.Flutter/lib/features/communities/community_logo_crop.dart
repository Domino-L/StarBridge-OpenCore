import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'community_logo_port.dart';
import 'community_creation_copy.dart';

class CommunityLogoCrop extends StatefulWidget {
  const CommunityLogoCrop({
    required this.port,
    required this.source,
    super.key,
  });
  final CommunityLogoPort port;
  final CommunityLogoSource source;
  @override
  State<CommunityLogoCrop> createState() => _CommunityLogoCropState();
}

class _CommunityLogoCropState extends State<CommunityLogoCrop> {
  double size = 1, horizontal = .5, vertical = .5;
  bool busy = false, failed = false;
  late final bytes = base64Decode(
    widget.source.previewImageData.split(',').last,
  );
  Future<void> apply() async {
    setState(() {
      busy = true;
      failed = false;
    });
    final source = widget.source;
    final side = math.min(source.width, source.height) * size;
    try {
      final result = await widget.port.cropLogo(
        source.sourceRef,
        horizontal * (source.width - side) / source.width,
        vertical * (source.height - side) / source.height,
        size,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              creationText(context, 'crop'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(creationText(context, 'cropHint')),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final source = widget.source;
                  final scale = math.min(
                    constraints.maxWidth / source.width,
                    constraints.maxHeight / source.height,
                  );
                  final width = source.width * scale,
                      height = source.height * scale;
                  final side = math.min(width, height) * size;
                  return Center(
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.memory(bytes, fit: BoxFit.fill),
                          ),
                          Positioned(
                            left: horizontal * (width - side),
                            top: vertical * (height - side),
                            width: side,
                            height: side,
                            child: GestureDetector(
                              onPanUpdate: busy
                                  ? null
                                  : (details) => setState(() {
                                      if (width > side) {
                                        horizontal =
                                            (horizontal +
                                                    details.delta.dx /
                                                        (width - side))
                                                .clamp(0, 1);
                                      }
                                      if (height > side) {
                                        vertical =
                                            (vertical +
                                                    details.delta.dy /
                                                        (height - side))
                                                .clamp(0, 1);
                                      }
                                    }),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  color: Colors.white.withValues(alpha: .08),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            for (final entry in [
              ('size', size, .2),
              ('horizontal', horizontal, 0.0),
              ('vertical', vertical, 0.0),
            ])
              Row(
                children: [
                  SizedBox(
                    width: 125,
                    child: Text(creationText(context, entry.$1)),
                  ),
                  Expanded(
                    child: Slider(
                      key: ValueKey('crop-${entry.$1}'),
                      value: entry.$2,
                      min: entry.$3,
                      onChanged: busy
                          ? null
                          : (value) => setState(() {
                              switch (entry.$1) {
                                case 'size':
                                  size = value;
                                case 'horizontal':
                                  horizontal = value;
                                case 'vertical':
                                  vertical = value;
                              }
                            }),
                    ),
                  ),
                ],
              ),
            if (failed)
              Text(
                creationText(context, 'imageFailed'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            OverflowBar(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: Text(creationText(context, 'cancel')),
                ),
                FilledButton(
                  onPressed: busy ? null : apply,
                  child: Text(creationText(context, 'useImage')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
