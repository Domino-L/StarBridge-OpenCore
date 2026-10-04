import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/social_identity_text.dart';

void main() {
  testWidgets('game ID is a secondary @ label, not part of the callsign', (
    tester,
  ) async {
    const secondary = Color(0xff7f9fb0);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SocialIdentityText(
            callsign: 'Navigator',
            gameId: 'Pilot-1',
            callsignStyle: TextStyle(fontWeight: FontWeight.w600),
            gameIdColor: secondary,
          ),
        ),
      ),
    );
    final label = tester.widget<Text>(find.byType(Text).last);
    final spans = (label.textSpan! as TextSpan).children!;
    expect(label.textSpan!.toPlainText(), 'Navigator  @Pilot-1');
    expect((spans[0] as TextSpan).style?.fontWeight, FontWeight.w600);
    expect((spans[1] as TextSpan).style?.color, secondary);
  });

  testWidgets('missing or fallback game ID is not duplicated', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SocialIdentityText(
            callsign: 'Pilot-1',
            gameId: 'Pilot-1',
            callsignStyle: TextStyle(),
            gameIdColor: Colors.blue,
          ),
        ),
      ),
    );
    final label = tester.widget<Text>(find.byType(Text).last);
    expect(label.textSpan!.toPlainText(), 'Pilot-1');
  });
}
