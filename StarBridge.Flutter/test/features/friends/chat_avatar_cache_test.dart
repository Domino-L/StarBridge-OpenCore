import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/direct_messages/chat_avatar.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

const photo =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
Widget scene(String? source, {double size = 36}) => MaterialApp(
  localizationsDelegates: const [AppStringsDelegate()],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('en'),
  ),
  home: ChatAvatar(label: 'Fixture', source: source, size: size),
);

void main() {
  testWidgets(
    'chat avatar reuses decoded bytes through repeated parent updates',
    (tester) async {
      await tester.pumpWidget(scene(photo));
      await tester.pumpAndSettle();
      final first =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      for (var index = 0; index < 10; index++) {
        await tester.pumpWidget(scene(photo, size: 36 + index.toDouble()));
        final current =
            tester.widget<Image>(find.byType(Image)).image as ResizeImage;
        expect(
          (current.imageProvider as MemoryImage).bytes,
          same((first.imageProvider as MemoryImage).bytes),
        );
      }
      await tester.pumpWidget(scene(null));
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(scene('data:image/png;base64,%%%'));
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(scene('https://example.invalid/avatar.png'));
      expect(
        find.byType(Image),
        findsNothing,
        reason: 'Peer avatars cannot opt into remote URLs',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
