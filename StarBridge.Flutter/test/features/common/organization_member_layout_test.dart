import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_compact_select.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_member_board.dart';

import '../friends/social_layout_test.dart' show app, loadFonts, size;

OrganizationMemberEntry _entry(
  int index, {
  bool actions = false,
  bool longNames = false,
  OrganizationMemberPresence presence = OrganizationMemberPresence.inGame,
}) => OrganizationMemberEntry(
  reference: 'layout-$index',
  role: longNames ? '远征指挥官 Long role $index' : 'Role $index',
  identity: OrganizationMemberIdentity(
    name: longNames ? '远航舰队成员 Long callsign $index' : 'Pilot $index',
    avatar: const Icon(Icons.person),
    gameId: 'Game_$index',
  ),
  presence: presence,
  runtime: MemberRuntimeCells(
    server: MemberRuntimeCell.value('Server $index'),
    ship: MemberRuntimeCell.value('Ship $index'),
    location: MemberRuntimeCell.value('Location $index'),
  ),
  actions: actions
      ? IconButton(
          key: Key('actions-$index'),
          onPressed: () {},
          icon: const Icon(Icons.more_horiz),
        )
      : null,
);

Future<void> _pump(
  WidgetTester tester, {
  required int count,
  double width = 1280,
  OrganizationMemberColumns columns = const OrganizationMemberColumns(),
  bool actions = false,
  bool longNames = false,
  double textScale = 1,
  OrganizationMemberPresence presence = OrganizationMemberPresence.inGame,
  String roleLabel = 'RSI 官网职位',
  ScrollController? scroll,
  OrganizationMemberPagination? pagination,
  String? note,
  String? footerNote,
  bool controlsEnabled = true,
}) async {
  size(tester, Size(width, 900));
  final search = TextEditingController();
  addTearDown(search.dispose);
  await tester.pumpWidget(
    app(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Column(
          children: [
            const Text('Fixed organization header'),
            Expanded(
              child: SingleChildScrollView(
                key: const Key('layout-owner'),
                controller: scroll,
                child: OrganizationMemberBoard(
                  key: UniqueKey(),
                  namespace: 'layout',
                  roleLabel: roleLabel,
                  rows: [
                    for (var i = 0; i < count; i++)
                      _entry(
                        i,
                        actions: actions,
                        longNames: longNames,
                        presence: presence,
                      ),
                  ],
                  columns: columns,
                  searchController: search,
                  onSearch: (_) {},
                  totalCount: count,
                  filters: const [],
                  note: note,
                  footerNote: footerNote,
                  controlsEnabled: controlsEnabled,
                  pagination:
                      pagination ??
                      OrganizationMemberPagination(
                        onPrevious: () {},
                        onNext: () {},
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(int index) => find.byKey(ValueKey('member-row-layout-$index'));
Finder _role(int index) => find.descendant(
  of: _row(index),
  matching: find.byType(OrganizationMemberRoleBadge),
);
Finder get _verticalScrollables => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable &&
      axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
);

void main() {
  setUpAll(loadFonts);

  testWidgets(
    'three rows size their board and pagination follows the last row',
    (tester) async {
      await _pump(tester, count: 3);
      final last = tester.getRect(_row(2));
      final footer = tester.getRect(
        find.byType(OrganizationMemberPaginationBar),
      );
      expect(footer.top - last.bottom, inInclusiveRange(0, 32));
      expect(_verticalScrollables, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page size and coverage follow pagination while existing notes stay above rows at narrow text scale',
    (tester) async {
      await _pump(
        tester,
        count: 3,
        width: 360,
        textScale: 2,
        note: 'Existing source note',
        footerNote: 'Coverage supplied by this source',
        pagination: OrganizationMemberPagination(
          page: 1,
          totalPages: 3,
          onNext: () {},
          onJump: (_) {},
          pageSize: 50,
          pageSizes: const [25, 50, 100],
          onPageSize: (_) {},
        ),
      );
      final selector = find.byKey(const Key('layout-page-size'));
      final footer = find.byType(OrganizationMemberPaginationBar);
      expect(
        find.descendant(
          of: find.byType(OrganizationMemberToolbar),
          matching: selector,
        ),
        findsNothing,
      );
      expect(find.descendant(of: footer, matching: selector), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('Existing source note')).dy,
        lessThan(tester.getTopLeft(_row(0)).dy),
      );
      await tester.ensureVisible(selector);
      await tester.pumpAndSettle();
      expect(selector.hitTestable(), findsOneWidget);
      final coverage = find.byKey(const Key('layout-footer-note'));
      expect(
        tester.getTopLeft(coverage).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(footer).dy),
      );
      expect(_verticalScrollables, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final boardEnabled in [false, true]) {
    testWidgets(
      'page-size and paging obey both board and source enable guards ($boardEnabled)',
      (tester) async {
        var commands = 0;
        await _pump(
          tester,
          count: 1,
          controlsEnabled: boardEnabled,
          pagination: OrganizationMemberPagination(
            enabled: !boardEnabled,
            page: 2,
            totalPages: 3,
            onPrevious: () => commands++,
            onNext: () => commands++,
            onJump: (_) => commands++,
            pageSize: 50,
            pageSizes: const [25, 50, 100],
            onPageSize: (_) => commands++,
          ),
        );
        for (final name in ['previous-page', 'next-page', 'jump']) {
          final button = find.byKey(Key('layout-$name'));
          expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
          await tester.tap(button);
        }
        final select = tester.widget<StarBridgeCompactSelect<int>>(
          find.byWidgetPredicate(
            (widget) => widget is StarBridgeCompactSelect<int>,
          ),
        );
        expect(select.onSelected, isNull);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('layout-jump-input')))
              .enabled,
          isFalse,
        );
        await tester.pumpAndSettle();
        expect(commands, 0);
        expect(find.byKey(const Key('layout-page-size')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'twenty complete rows use the same ancestor for inside and outside wheel input',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _pump(
        tester,
        count: 20,
        columns: const OrganizationMemberColumns.all(),
        scroll: scroll,
      );
      expect(_verticalScrollables, findsOneWidget);
      expect(find.byType(OrganizationMemberRow), findsNWidgets(20));
      final header = tester.getRect(find.text('Fixed organization header'));
      final owner = tester.getRect(find.byKey(const Key('layout-owner')));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(_row(0)),
          scrollDelta: const Offset(0, 180),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      scroll.jumpTo(0);
      await tester.pump();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: Offset(owner.right - 2, owner.center.dy),
          scrollDelta: const Offset(0, 180),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      await tester.ensureVisible(_row(19));
      await tester.pumpAndSettle();
      final last = tester.getRect(_row(19));
      expect(last.top, greaterThanOrEqualTo(owner.top));
      expect(last.bottom, lessThanOrEqualTo(owner.bottom + .1));
      expect(tester.getRect(find.text('Fixed organization header')), header);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two columns remain one row at 900 and keep their header visible',
    (tester) async {
      await _pump(tester, count: 1, width: 900);
      final identity = tester.getRect(find.byType(OrganizationMemberIdentity));
      final role = tester.getRect(_role(0));
      expect(role.center.dy, closeTo(identity.center.dy, 1));
      expect(tester.getSize(_row(0)).height, lessThan(95));
      final header = find.descendant(
        of: find.byType(OrganizationMemberHeader),
        matching: find.text('RSI 官网职位'),
      );
      expect(header, findsOneWidget);
      expect(tester.getRect(header).left, closeTo(role.left, 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'complete columns stay horizontal at 900 content width before text scaling',
    (tester) async {
      await _pump(
        tester,
        count: 1,
        width: 900,
        columns: const OrganizationMemberColumns.all(),
        actions: true,
      );
      final row = _row(0);
      final identity = tester.getRect(find.byType(OrganizationMemberIdentity));
      final role = tester.getRect(_role(0));
      final status = tester.getRect(find.byType(OrganizationMemberStatus));
      expect(role.center.dy, closeTo(identity.center.dy, 2));
      expect(status.center.dy, inInclusiveRange(identity.top, identity.bottom));
      expect(
        find.descendant(of: row, matching: find.text('RSI 官网职位')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(OrganizationMemberHeader),
          matching: find.text('RSI 官网职位'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _pump(
        tester,
        count: 1,
        width: 900,
        columns: const OrganizationMemberColumns.all(),
        actions: true,
        textScale: 2,
      );
      expect(
        tester.getRect(_role(0)).top,
        greaterThan(
          tester.getRect(find.byType(OrganizationMemberIdentity)).bottom,
        ),
      );
      expect(
        find.descendant(of: _row(0), matching: find.text('RSI 官网职位')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1280.0, 1600.0]) {
    testWidgets(
      'hidden runtime columns preserve left role alignment at $width',
      (tester) async {
        await _pump(
          tester,
          count: 1,
          width: width,
          columns: const OrganizationMemberColumns.all(),
          roleLabel: '角色',
        );
        final communityOffset =
            tester.getRect(_role(0)).left - tester.getRect(_row(0)).left;
        await _pump(tester, count: 1, width: width);
        final fleetOffset =
            tester.getRect(_role(0)).left - tester.getRect(_row(0)).left;
        expect(fleetOffset, closeTo(communityOffset, 2));
        expect(tester.getSize(_row(0)).width, closeTo(width, 1));
        final header = find.descendant(
          of: find.byType(OrganizationMemberHeader),
          matching: find.text('RSI 官网职位'),
        );
        expect(
          tester.getRect(header).left,
          closeTo(tester.getRect(_role(0)).left, 2),
        );
      },
    );
  }

  testWidgets(
    '760 content width puts role below identity and keeps actions beside identity',
    (tester) async {
      await _pump(
        tester,
        count: 1,
        width: 760,
        columns: const OrganizationMemberColumns.all(),
        actions: true,
      );
      final row = tester.getRect(_row(0));
      final identity = tester.getRect(find.byType(OrganizationMemberIdentity));
      final role = tester.getRect(_role(0));
      final action = tester.getRect(find.byKey(const Key('actions-0')));
      expect(role.top, greaterThan(identity.bottom));
      expect(action.center.dy, closeTo(identity.center.dy, 2));
      expect(action.right, closeTo(row.right - 16, 2));
      expect(
        find.descendant(of: _row(0), matching: find.text('RSI 官网职位')),
        findsOneWidget,
      );
      final status = tester.getRect(find.byType(OrganizationMemberStatus));
      expect(status.top, greaterThanOrEqualTo(identity.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'standalone unknown status uses public offline gray without a status dot',
    (tester) async {
      size(tester, const Size(900, 500));
      await tester.pumpWidget(
        app(
          const Center(
            child: OrganizationMemberStatus(
              presence: OrganizationMemberPresence.unknown,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dots = find.descendant(
        of: find.byType(OrganizationMemberStatus),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(find.text('离线'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(
        tester.widget<Text>(find.text('离线')).style?.color,
        tester
            .element(find.byType(OrganizationMemberStatus))
            .tokens
            .colors
            .offline,
      );
      expect(dots, findsNothing);
    },
  );

  testWidgets(
    '360 content width at 200 percent text keeps all rows and actions reachable without overflow',
    (tester) async {
      await _pump(
        tester,
        count: 3,
        width: 360,
        columns: const OrganizationMemberColumns.all(),
        actions: true,
        textScale: 2,
        longNames: true,
      );
      expect(_verticalScrollables, findsOneWidget);
      for (var index = 0; index < 3; index++) {
        await tester.ensureVisible(_row(index));
        await tester.pumpAndSettle();
        expect(find.text('远航舰队成员 Long callsign $index'), findsOneWidget);
        expect(find.text('远征指挥官 Long role $index'), findsOneWidget);
        final row = tester.getRect(_row(index));
        final action = tester.getRect(find.byKey(Key('actions-$index')));
        expect(action.right, lessThanOrEqualTo(row.right));
        final identity = tester.getRect(
          find.descendant(
            of: _row(index),
            matching: find.byType(OrganizationMemberIdentity),
          ),
        );
        expect(action.center.dy, closeTo(identity.center.dy, 2));
        expect(
          tester
              .widget<IconButton>(find.byKey(Key('actions-$index')))
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.byType(OrganizationMemberPaginationBar));
      await tester.pumpAndSettle();
      expect(
        find.byType(OrganizationMemberPaginationBar).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown row uses public offline and three original non-game cells',
    (tester) async {
      await _pump(
        tester,
        count: 1,
        columns: const OrganizationMemberColumns.all(),
        presence: OrganizationMemberPresence.unknown,
      );
      final card = tester.getRect(_row(0));
      final strips = find
          .descendant(of: _row(0), matching: find.byType(ColoredBox))
          .evaluate()
          .where((element) {
            final rect = tester.getRect(
              find.byElementPredicate(
                (candidate) => identical(candidate, element),
              ),
            );
            return (rect.width - 3).abs() < .1 &&
                (rect.left - card.left).abs() < 1.5;
          });
      expect(strips, hasLength(1));
      expect(
        (strips.single.widget as ColoredBox).color,
        tester.widget<Text>(find.text('离线')).style?.color,
      );
      expect(find.text('Server 0'), findsNothing);
      expect(find.text('Ship 0'), findsNothing);
      expect(find.text('Location 0'), findsNothing);
      expect(find.text('未进入游戏'), findsNWidgets(3));
      expect(find.text('离线'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    },
  );
}
