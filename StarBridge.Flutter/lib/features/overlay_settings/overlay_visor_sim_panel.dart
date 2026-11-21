import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'overlay_members_size.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/styles/overlay_visor_sim_palette.dart';

import 'overlay_visor_editor_content.dart';
import 'overlay_workspace_models.dart';

export '../../design_system/styles/overlay_visor_sim_palette.dart'
    show OverlayVisorSimColors;

/// A visor block as the layout editor draws it (11-12 user: "编辑里的可以是简化版
/// 的面板，只有框和背景那种，其他都按照真实的来，还要固定大小"): a plain frame and
/// background in the decoration colour, and inside it the visor's own layout
/// (StarBridge.Desktop OverlayVisorDraw: Team, Events, Chat) with the same
/// fonts, sizes, rows, columns and colours. It is drawn in the visor's design
/// units scaled by the block's box alone, so text never grows or shrinks on its
/// own: a smaller editor shows everything smaller together. Long text is cut at
/// its field (the visor scrolls it). The lean comes from the editor's own
/// camera transform around this widget.
class OverlayVisorSimPanel extends StatelessWidget {
  const OverlayVisorSimPanel({
    required this.block,
    required this.content,
    required this.settings,
    required this.right,
    this.textOpacity = 1,
    this.backgroundOpacity = 1,
    this.decorationOpacity = 1,
    this.sampleLabel,
    super.key,
  });

  /// "示例数据" beside the block's title when what it shows is samples.
  final String? sampleLabel;

  /// team, events or chat.
  final String block;
  final OverlayVisorEditorContent content;
  final OverlayWorkspaceSettings settings;

  /// Reads from the right screen edge inward.
  final bool right;
  final double textOpacity, backgroundOpacity, decorationOpacity;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: OverlayVisorSimPainter(
      block: block,
      content: content,
      settings: settings,
      right: right,
      locale: AppStrings.of(context).locale,
      textOpacity: textOpacity,
      backgroundOpacity: backgroundOpacity,
      decorationOpacity: decorationOpacity,
      sampleLabel: switch (block) {
        'team' when content.sample => sampleLabel,
        'events' when content.eventsSample => sampleLabel,
        'chat' when content.chatSample => sampleLabel,
        _ => null,
      },
    ),
  );
}

class OverlayVisorSimPainter extends CustomPainter {
  OverlayVisorSimPainter({
    required this.block,
    required this.content,
    required this.settings,
    required this.right,
    required this.textOpacity,
    required this.backgroundOpacity,
    required this.decorationOpacity,
    this.sampleLabel,
    this.locale = const Locale('zh', 'CN'),
  });

  final Locale locale;
  @visibleForTesting
  double? debugPaintedWidth;
  @visibleForTesting
  List<({String text, double y, Rect? clip})> debugPaintedFields = const [];

  final String? sampleLabel;
  final String block;
  final OverlayVisorEditorContent content;
  final OverlayWorkspaceSettings settings;
  final bool right;
  final double textOpacity, backgroundOpacity, decorationOpacity;

  // OverlayVisorDraw / OverlayVisorPainter metrics (design units)
  static const rowInset = 16.0, columnGap = 10.0, rowHeight = 40.0;
  static const shipLine = 19.0, teamHeader = 20.0 + 24 + 7, pageLine = 20.0;
  static const pinnedGap = 3.0, titleGap = 14.0, denseRow = 35.0;
  static const looseRow = 60.0, eventLine = 70.0, chatLine = 28.0;
  static const eventTimeGap = 10.0, chatWhoGap = 10.0, labelHeight = 22.0;
  static const memberCaps = [180.0, 158.0];

  /// Body text is drawn 12 px and titles 13 px at 1440p medium (method E).
  static const _medium1440 = 1440 / 1080 * 0.53;
  static double drawnSize(double size) => size <= 15
      ? size * 12 / (15 * _medium1440)
      : size * 13 / (16 * _medium1440);

  static const hanFamily = 'Source Han Sans CN', numFamily = 'Rajdhani';

  double _number(String field, double fallback) =>
      (settings[field] as num?)?.toDouble() ?? fallback;

  /// The block's design width: its width setting (a maximum while adaptive).
  double get designWidth => switch (block) {
    'team' => _number('visorMembersWidth', 364).clamp(220, 480).toDouble(),
    'events' => _number('visorEventsWidth', 364).clamp(220, 480).toDouble(),
    _ => _number('visorChatWidth', 364).clamp(220, 480).toDouble(),
  };

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = size.width / designWidth;
    final box = Size(designWidth, size.height / s);
    final group = _Group(this, box);
    switch (block) {
      case 'team':
        group.team();
      case 'events':
        group.events();
      default:
        group.chat();
    }
    canvas.save();
    canvas.scale(s);
    // frame and background behind the drawn width (the visor plate: the drawn
    // group, anchored to its screen edge), then the text over them
    final bare = block == 'chat' && settings['visorChatPlate'] == false;
    if (!bare) {
      final w = math.min(group.width, box.width);
      final plate = Rect.fromLTWH(right ? box.width - w : 0, 0, w, box.height);
      // the background opacity is the plate's real opacity (11-13 user,
      // "背景可以"), as the visor draws it: up to 15% the faint tint it always
      // had, above it the decoration colour's own dark plate (m102b) that is solid
      // at 100%, the tint on top
      final v = backgroundOpacity.clamp(0.0, 1.0);
      const legacy = 0.15;
      final dark = math.max(0.0, (v - legacy) / (1 - legacy));
      if (dark > 0) {
        canvas.drawRect(
          plate,
          Paint()
            ..color = OverlayVisorSimPalette.plate(decoration)
                .withValues(alpha: dark),
        );
      }
      canvas.drawRect(
        plate,
        Paint()
          ..color = decoration.withValues(
            alpha: 0.16 * math.min(1.0, v / legacy),
          ),
      );
      canvas.drawRect(
        plate.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = decoration.withValues(
            alpha: 0.85 * decorationOpacity.clamp(0.0, 1.0),
          ),
      );
    }
    canvas.clipRect(Offset.zero & box);
    group.flush(canvas);
    canvas.restore();
    assert(() {
      debugPaintedWidth = math.min(group.width, box.width) * s;
      debugPaintedFields = List.unmodifiable([
        for (final f in group._fields) (text: f.run.text, y: f.y, clip: f.clip),
      ]);
      return true;
    }());
  }

  Color get decoration => content.decoration;

  @override
  bool shouldRepaint(OverlayVisorSimPainter old) =>
      old.block != block ||
      old.content != content ||
      old.settings != settings ||
      old.right != right ||
      old.locale != locale ||
      old.textOpacity != textOpacity ||
      old.backgroundOpacity != backgroundOpacity ||
      old.decorationOpacity != decorationOpacity ||
      old.sampleLabel != sampleLabel;
}

/// One text run (OverlayVisorRun): text, numeric font, weight, design size,
/// colour, a vertical offset and a gap before it.
final class _Run {
  _Run(
    this.text,
    this.numeric,
    this.weight,
    this.size,
    this.color, {
    this.dy = 0,
    this.gap = 0,
  });
  final String text;
  final bool numeric;
  final FontWeight weight;
  final double size, dy, gap;
  final Color color;
  TextPainter? _painter;

  TextPainter painter(double alpha) => _painter ??= TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: numeric
            ? OverlayVisorSimPainter.numFamily
            : OverlayVisorSimPainter.hanFamily,
        fontFamilyFallback: const [OverlayVisorSimPainter.hanFamily],
        fontSize: OverlayVisorSimPainter.drawnSize(size),
        fontWeight: weight,
        color: color.withValues(alpha: color.a * alpha),
        shadows: const [
          Shadow(color: OverlayVisorSimPalette.textEdge, blurRadius: 1.2),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  double width(double alpha) => gap + (text.isEmpty ? 0 : painter(alpha).width);
}

/// A field drawn at a place, cut to a width.
final class _Field {
  _Field(this.run, this.x, this.y, this.clip);
  final _Run run;
  final double x, y;
  final Rect? clip;
}

/// The visor's layout of one group (OverlayVisorDraw), collected as fields and
/// marks, then drawn.
final class _Group {
  _Group(this.p, this.box);
  final OverlayVisorSimPainter p;
  final Size box;
  final _fields = <_Field>[];
  final _marks = <void Function(Canvas)>[];

  /// The drawn width (adaptive groups narrower than the box).
  late double width = box.width;

  bool get right => p.right;
  double get alpha => p.textOpacity.clamp(0.0, 1.0);
  OverlayVisorEditorContent get c => p.content;

  double _w(_Run run) => run.width(alpha);
  double at(double dx, double w) => right ? width - dx - w : dx;

  /// Box-relative x for a drawn-width-relative one: the drawn group hugs its
  /// screen edge inside the box.
  double get _origin => right ? box.width - width : 0;

  void seq(double dx, double y, List<_Run> runs) {
    final total = runs.fold(0.0, (sum, r) => sum + _w(r));
    var x = at(dx, total);
    for (final run in runs) {
      _fields.add(_Field(run, _origin + x + run.gap, y + run.dy, null));
      x += _w(run);
    }
  }

  void field(double dx, double y, double w, _Run run, {bool? alignLeft}) {
    final tw = _w(run);
    final x = at(dx, w);
    final left = alignLeft ?? !right;
    final clip = tw <= w + 0.5
        ? null
        : Rect.fromLTWH(
            _origin + x,
            y - 4,
            w,
            OverlayVisorSimPainter.drawnSize(run.size) * 1.7 + 8,
          );
    _fields.add(
      _Field(run, _origin + (tw <= w + 0.5 && !left ? x + w - tw : x), y, clip),
    );
  }

  _Run title(String text) =>
      _Run(text, false, FontWeight.w500, 13, OverlayVisorSimColors.dim);

  /// The title, and "示例数据" after it when the block shows samples.
  List<_Run> titled(String text) => [
    title(text),
    if (p.sampleLabel case final label?)
      _Run(
        label,
        false,
        FontWeight.w500,
        12,
        OverlayVisorSimPalette.sampleMark,
        dy: 1,
        gap: 8,
      ),
  ];

  // ---------------- team ----------------
  (_Run, _Run, _Run) rowRuns(OverlayVisorEditorMember m) {
    final inGame = m.state == 'InGame';
    final name = _Run(
      (m.pinned ? '★ ' : '') + m.name,
      true,
      FontWeight.w600,
      16,
      m.state == 'Offline'
          ? OverlayVisorSimColors.dim
          : OverlayVisorSimColors.ink,
    );
    final ship = _Run(
      inGame ? (m.ship.isNotEmpty ? m.ship : '—') : m.status,
      false,
      FontWeight.w500,
      15,
      inGame
          ? OverlayVisorSimColors.quiet
          : m.state == 'Away'
          ? OverlayVisorSimColors.warn
          : OverlayVisorSimColors.accent,
    );
    final place = _Run(
      m.place.isNotEmpty ? m.place : '—',
      false,
      FontWeight.w500,
      15,
      m.sameServer ? OverlayVisorSimColors.ok : OverlayVisorSimColors.quiet,
    );
    return (name, ship, place);
  }

  List<_Run> counts() => [
    _Run('${c.online}', true, FontWeight.w600, 16, OverlayVisorSimColors.ink),
    _Run(
      c.countLabels[0],
      false,
      FontWeight.w500,
      12,
      OverlayVisorSimColors.dim,
      dy: 1,
      gap: 4,
    ),
    _Run(
      '${c.inGame}',
      true,
      FontWeight.w600,
      16,
      OverlayVisorSimColors.accent,
      gap: 12,
    ),
    _Run(
      c.countLabels[1],
      false,
      FontWeight.w500,
      12,
      OverlayVisorSimColors.dim,
      dy: 1,
      gap: 4,
    ),
    _Run(
      '${c.sameServer}',
      true,
      FontWeight.w600,
      16,
      OverlayVisorSimColors.ok,
      gap: 12,
    ),
    _Run(
      c.countLabels[2],
      false,
      FontWeight.w500,
      12,
      OverlayVisorSimColors.dim,
      dy: 1,
      gap: 4,
    ),
  ];

  List<_Run> youAt() => [
    _Run('◆', false, FontWeight.w500, 11, p.decoration, gap: 2),
    _Run(
      c.youAt,
      false,
      FontWeight.w500,
      13,
      OverlayVisorSimColors.ink,
      gap: 4,
    ),
  ];

  void team() {
    final adaptive = p.settings['visorMembersAutoWidth'] != false;
    // RowsFor reserves the header, page line and pinned separator even when
    // absent, matching the densest layout's capacity (1..20).
    final capacity = OverlayMembersSize.rows(box.height);
    final text = AppStrings.resolve(p.locale).text;
    final rows = adaptive
        ? [
            ...c.members.take(capacity - 1),
            OverlayVisorEditorMember(
              name: text('overlay.sample.visorWidestMember'),
              ship: text('overlay.sample.visorWidestShip'),
              place: text('overlay.sample.visorWidestPlace'),
              status: '',
              state: 'InGame',
              sameServer: false,
              pinned: false,
            ),
          ]
        : c.members;
    final membersWidth = box.width;
    final room =
        membersWidth -
        OverlayVisorSimPainter.rowInset -
        OverlayVisorSimPainter.columnGap;
    final share =
        room / OverlayVisorSimPainter.memberCaps.reduce((a, b) => a + b);
    final caps = [
      for (final cap in OverlayVisorSimPainter.memberCaps)
        (cap * share).floorToDouble(),
    ];
    var columns = caps;
    if (adaptive) {
      var lead = 0.0, place = 0.0;
      for (final m in rows) {
        final (n, s, pl) = rowRuns(m);
        lead = math.max(lead, math.max(_w(n), _w(s)));
        place = math.max(place, _w(pl));
      }
      columns = [
        math.min(lead, caps[0]).ceilToDouble(),
        math.min(place, caps[1]).ceilToDouble(),
      ];
      final header = math.max(
        _w(title(c.membersTitle)) +
            (c.youAt.isNotEmpty
                ? OverlayVisorSimPainter.titleGap +
                      youAt().fold(0.0, (a, r) => a + _w(r))
                : 0),
        counts().fold(0.0, (a, r) => a + _w(r)),
      );
      final teamWidth =
          OverlayVisorSimPainter.rowInset +
          columns[0] +
          columns[1] +
          OverlayVisorSimPainter.columnGap;
      width = math.min(
        membersWidth,
        math.max(teamWidth, header.ceilToDouble()),
      );
    }
    final t = title(c.membersTitle);
    // the source's name is cut when too long (the visor scrolls it), the
    // count after it stays whole (11-13 user, B): its width is kept first,
    // "you are at" at most half the width and never over the count (review R3)
    final cut = p.sampleLabel == null ? c.membersTitle.lastIndexOf(' · ') : -1;
    final count = cut > 0 ? title(c.membersTitle.substring(cut)) : null;
    final countW = count == null ? 0.0 : _w(count);
    final mark = c.youAt.isNotEmpty ? youAt() : <_Run>[];
    final markW = math.min(
      mark.fold(0.0, (a, r) => a + _w(r)),
      math.min(
        width / 2,
        math.max(0.0, width - countW - OverlayVisorSimPainter.titleGap - 1),
      ),
    );
    final titleW = mark.isNotEmpty
        ? math.max(1.0, width - markW - OverlayVisorSimPainter.titleGap)
        : width;
    if (count != null) {
      final name = title(c.membersTitle.substring(0, cut));
      final nameW = math.min(_w(name), math.max(1.0, titleW - countW));
      field(right ? countW : 0, 0, nameW, name);
      field(right ? 0 : nameW, 0, countW, count);
    } else if (p.sampleLabel == null) {
      field(0, 0, titleW, t);
    } else {
      seq(0, 0, titled(c.membersTitle));
    }
    if (mark.isNotEmpty) {
      final diamond = mark[0];
      final dw = _w(diamond);
      final markX = right ? 0.0 : width - markW;
      _fields.add(_Field(diamond, _origin + markX + diamond.gap, 0, null));
      final textRun = _Run(
        mark[1].text,
        false,
        FontWeight.w500,
        13,
        OverlayVisorSimColors.ink,
      );
      field(
        right ? width - dw - (markW - dw) : markX + dw,
        0,
        math.max(1.0, markW - dw),
        textRun,
        alignLeft: true,
      );
    }
    var y = 20.0;
    seq(0, y, counts());
    y += 24 + 7;
    final pinned = rows.any((m) => m.pinned) && rows.any((m) => !m.pinned);
    final paged = c.page.isNotEmpty;
    final fixed = box.height;
    final pitch = rows.isEmpty
        ? OverlayVisorSimPainter.rowHeight
        : ((fixed -
                      OverlayVisorSimPainter.teamHeader -
                      (paged ? OverlayVisorSimPainter.pageLine : 0) -
                      (pinned ? OverlayVisorSimPainter.pinnedGap : 0)) /
                  rows.length)
              .clamp(
                OverlayVisorSimPainter.denseRow,
                OverlayVisorSimPainter.looseRow,
              )
              .toDouble();
    var pinnedDone = false;
    for (final m in rows) {
      if (!m.pinned && !pinnedDone && rows.any((x) => x.pinned)) {
        y += OverlayVisorSimPainter.pinnedGap;
        pinnedDone = true;
      }
      final top = y + (pitch - OverlayVisorSimPainter.rowHeight) / 2;
      _status(m, top);
      final (name, ship, place) = rowRuns(m);
      field(OverlayVisorSimPainter.rowInset, top, columns[0], name);
      field(
        OverlayVisorSimPainter.rowInset,
        top + OverlayVisorSimPainter.shipLine,
        columns[0],
        ship,
      );
      field(
        OverlayVisorSimPainter.rowInset +
            columns[0] +
            OverlayVisorSimPainter.columnGap,
        top + 1,
        columns[1],
        place,
        alignLeft: right,
      );
      y += pitch;
    }
    if (paged) {
      seq(0, y + 1, [
        _Run(c.page, false, FontWeight.w400, 12, OverlayVisorSimColors.dim),
      ]);
    }
  }

  /// The status mark and, when known, the health ring under it.
  void _status(OverlayVisorEditorMember m, double y) {
    final hollow = m.state == 'AppOnly' || m.state == 'Offline';
    final colour = switch (m.state) {
      'AppOnly' => OverlayVisorSimColors.accent,
      'Away' => OverlayVisorSimColors.warn,
      'Offline' => OverlayVisorSimColors.dim,
      _ =>
        m.sameServer ? OverlayVisorSimColors.ok : OverlayVisorSimColors.accent,
    };
    final x = _origin + (right ? width - 5 : 5.0);
    final a = alpha;
    _marks.add((canvas) {
      final d = Path()
        ..moveTo(x, y + 10 - 6)
        ..lineTo(x + 6, y + 10)
        ..lineTo(x, y + 10 + 6)
        ..lineTo(x - 6, y + 10)
        ..close();
      final paint = Paint()..color = colour.withValues(alpha: colour.a * a);
      if (hollow) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
      }
      canvas.drawPath(d, paint);
      final ry = y + OverlayVisorSimPainter.shipLine + 8;
      const r = 4.2;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      switch (m.vitals) {
        case 'Alive':
          final f = m.health.clamp(0.0, 1.0);
          final ring = f > 0.5
              ? OverlayVisorSimColors.healthHigh
              : f >= 0.25
              ? OverlayVisorSimColors.warn
              : OverlayVisorSimColors.bad;
          canvas.drawCircle(
            Offset(x, ry),
            r,
            stroke..color = ring.withValues(alpha: 0.22 * a),
          );
          canvas.drawArc(
            Rect.fromCircle(center: Offset(x, ry), radius: r),
            -math.pi / 2,
            -2 * math.pi * f,
            false,
            stroke..color = ring.withValues(alpha: a),
          );
        case 'Downed':
          canvas.drawCircle(
            Offset(x, ry),
            r,
            stroke
              ..color = OverlayVisorSimColors.bad.withValues(alpha: 0.8 * a),
          );
          final line = Paint()
            ..strokeWidth = 1.4
            ..color = OverlayVisorSimColors.bad.withValues(alpha: a);
          canvas.drawLine(Offset(x - 2.4, ry), Offset(x + 2.4, ry), line);
          canvas.drawLine(Offset(x, ry - 2.4), Offset(x, ry + 2.4), line);
        case 'Dead':
          canvas.drawCircle(
            Offset(x, ry),
            r,
            stroke
              ..color = OverlayVisorSimColors.dim.withValues(alpha: 0.22 * a),
          );
          final line = Paint()
            ..strokeWidth = 1.4
            ..color = OverlayVisorSimColors.bad.withValues(alpha: 0.9 * a);
          canvas.drawLine(
            Offset(x - 2.6, ry - 2.6),
            Offset(x + 2.6, ry + 2.6),
            line,
          );
          canvas.drawLine(
            Offset(x - 2.6, ry + 2.6),
            Offset(x + 2.6, ry - 2.6),
            line,
          );
        default:
          break;
      }
    });
  }

  // ---------------- events ----------------
  _Run eventTitle(OverlayVisorEditorEvent e) => _Run(
    e.title,
    false,
    FontWeight.w600,
    16,
    OverlayVisorSimColors.tone(e.tone),
  );
  _Run eventTime(OverlayVisorEditorEvent e) =>
      _Run(e.time, true, FontWeight.w500, 13, OverlayVisorSimColors.dim);
  _Run eventDetail(OverlayVisorEditorEvent e) =>
      _Run(e.detail, false, FontWeight.w500, 15, OverlayVisorSimColors.ink);

  void events() {
    if (p.settings['visorEventsAutoWidth'] != false) {
      var natural = _w(title(c.eventsTitle));
      for (final e in c.events) {
        natural = math.max(
          natural,
          math.max(
            _w(eventTitle(e)) +
                OverlayVisorSimPainter.eventTimeGap +
                _w(eventTime(e)),
            _w(eventDetail(e)),
          ),
        );
      }
      width = math.min(natural, box.width).ceilToDouble();
    }
    seq(0, 0, titled(c.eventsTitle));
    var y = OverlayVisorSimPainter.labelHeight;
    for (final e in c.events) {
      final t = eventTitle(e);
      final tw = _w(t);
      seq(0, y, [t]);
      seq(tw + OverlayVisorSimPainter.eventTimeGap, y + 3, [eventTime(e)]);
      field(0, y + 24, width, eventDetail(e));
      y += OverlayVisorSimPainter.eventLine;
    }
  }

  // ---------------- chat ----------------
  _Run chatWho(OverlayVisorEditorChatLine line) =>
      _Run(line.who, true, FontWeight.w600, 16, OverlayVisorSimColors.accent);
  _Run chatText(OverlayVisorEditorChatLine line) =>
      _Run(line.text, false, FontWeight.w500, 15, OverlayVisorSimColors.ink);

  void chat() {
    if (p.settings['visorChatAutoWidth'] != false) {
      var natural = _w(title(c.chatTitle));
      for (final line in c.chat) {
        natural = math.max(
          natural,
          _w(chatWho(line)) +
              OverlayVisorSimPainter.chatWhoGap +
              _w(chatText(line)),
        );
      }
      width = math.min(natural, box.width).ceilToDouble();
    }
    seq(0, 0, titled(c.chatTitle));
    var y = OverlayVisorSimPainter.labelHeight;
    final lines = ((p.settings['chatMaxVisibleCount'] as num?)?.round() ?? 4)
        .clamp(1, 8);
    final shown = c.chat.length > lines
        ? c.chat.sublist(c.chat.length - lines)
        : c.chat;
    for (final line in shown) {
      final who = chatWho(line);
      final ww = math.min(_w(who), width / 2);
      field(0, y, ww, who);
      field(
        ww + OverlayVisorSimPainter.chatWhoGap,
        y,
        math.max(1.0, width - ww - OverlayVisorSimPainter.chatWhoGap),
        chatText(line),
        alignLeft: !right,
      );
      y += OverlayVisorSimPainter.chatLine;
    }
  }

  void flush(Canvas canvas) {
    for (final mark in _marks) {
      mark(canvas);
    }
    for (final f in _fields) {
      if (f.run.text.isEmpty) continue;
      if (f.clip != null) {
        canvas.save();
        canvas.clipRect(f.clip!);
      }
      f.run.painter(alpha).paint(canvas, Offset(f.x, f.y));
      if (f.clip != null) canvas.restore();
    }
  }
}
