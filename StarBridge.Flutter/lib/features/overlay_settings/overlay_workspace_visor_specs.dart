import 'overlay_workspace_schema.dart';

// Existing roster page cap (OverlayVisorDraw.MaxRows), shared by sizing UI.
const overlayWorkspaceVisorMembersMaxRows = 20;

/// The visor's settings fields, as the Host sends them (CSV 81..96).
const overlayWorkspaceVisorFields = {
  'visorSize',
  'visorHolidayGold',
  'visorBadgeX',
  'visorBadgeY',
  'visorTilt',
  'visorChatPlate',
  'visorMembersAutoWidth',
  'visorMembersAutoHeight',
  'visorMembersWidth',
  'visorMembersHeight',
  'visorEventsAutoWidth',
  'visorChatAutoWidth',
  'visorEventsWidth',
  'visorChatWidth',
  'visorViewingDistance',
  'visorEventsX',
};

/// What a Host from before each visor setting means (its default).
const overlayWorkspaceVisorDefaults = <String, Object>{
  'visorSize': 'Medium',
  'visorHolidayGold': false,
  'visorBadgeX': -1.0,
  'visorBadgeY': -1.0,
  'visorTilt': 15.0,
  'visorChatPlate': true,
  'visorMembersAutoWidth': true,
  'visorMembersAutoHeight': true,
  'visorMembersWidth': 364.0,
  'visorMembersHeight': 394.0,
  'visorEventsAutoWidth': true,
  'visorChatAutoWidth': true,
  'visorEventsWidth': 364.0,
  'visorChatWidth': 364.0,
  // 11-11: the distance the visor's camera always had
  'visorViewingDistance': 1000.0,
  // 11-12: events at their screen edge, as before they could sit anywhere
  'visorEventsX': -1.0,
};

/// The visor projection's settings (0.7.3), only used while the visor is the
/// shown appearance (overlayWorkspaceFieldDisabledReason).
const overlayWorkspaceVisorFieldSpecs = <OverlayWorkspaceFieldSpec>[
  OverlayWorkspaceFieldSpec(
    'visorSize',
    'global',
    OverlayWorkspaceFieldKind.choice,
    '面罩大小',
    options: ['Small', 'Medium', 'Large'],
  ),
  // 11-07: how far the side panels fold toward the screen centre (立体程度).
  OverlayWorkspaceFieldSpec(
    'visorTilt',
    'global',
    OverlayWorkspaceFieldKind.number,
    '立体程度',
    minimum: 0,
    maximum: 60,
    divisions: 60,
    unit: OverlayWorkspaceUnit.degrees,
  ),
  // 11-11 user: "浮层外观应该让视距也可调" (600-3000 in steps of 50)
  OverlayWorkspaceFieldSpec(
    'visorViewingDistance',
    'global',
    OverlayWorkspaceFieldKind.number,
    '视距',
    minimum: 600,
    maximum: 3000,
    divisions: 48,
    unit: OverlayWorkspaceUnit.none,
  ),
  // 11-07 members size: each dimension adaptive (up to the value) or fixed
  // (the value); visor design units.
  OverlayWorkspaceFieldSpec(
    'visorMembersAutoWidth',
    'look.members',
    OverlayWorkspaceFieldKind.toggle,
    '成员面板宽度自适应',
  ),
  OverlayWorkspaceFieldSpec(
    'visorMembersWidth',
    'look.members',
    OverlayWorkspaceFieldKind.number,
    '成员面板宽度',
    minimum: 220,
    maximum: 480,
    divisions: 26,
    unit: OverlayWorkspaceUnit.visorPixels,
  ),
  // 11-10 user: the members height is always fixed ("就要固定上下高度"); the
  // saved switch is kept for older versions but not offered
  OverlayWorkspaceFieldSpec(
    'visorMembersAutoHeight',
    'look.members',
    OverlayWorkspaceFieldKind.toggle,
    '成员面板高度自适应',
    userVisible: false,
  ),
  OverlayWorkspaceFieldSpec(
    'visorMembersHeight',
    'look.members',
    OverlayWorkspaceFieldKind.number,
    '成员面板高度',
    // two to twenty rows (the roster's page limit) with the title line, counts
    // and the page line
    minimum: 191,
    maximum: 874,
    divisions: 683,
    unit: OverlayWorkspaceUnit.visorPixels,
  ),
  // 11-07 "2放": events and chat width, as the members width; their height
  // comes from the existing line counts.
  OverlayWorkspaceFieldSpec(
    'visorEventsAutoWidth',
    'look.events',
    OverlayWorkspaceFieldKind.toggle,
    '事件宽度自适应',
  ),
  OverlayWorkspaceFieldSpec(
    'visorEventsWidth',
    'look.events',
    OverlayWorkspaceFieldKind.number,
    '事件宽度',
    minimum: 220,
    maximum: 480,
    divisions: 26,
    unit: OverlayWorkspaceUnit.visorPixels,
  ),
  OverlayWorkspaceFieldSpec(
    'visorChatAutoWidth',
    'look.chat',
    OverlayWorkspaceFieldKind.toggle,
    '聊天宽度自适应',
  ),
  OverlayWorkspaceFieldSpec(
    'visorChatWidth',
    'look.chat',
    OverlayWorkspaceFieldKind.number,
    '聊天宽度',
    minimum: 220,
    maximum: 480,
    divisions: 26,
    unit: OverlayWorkspaceUnit.visorPixels,
  ),
  // 11-07 "可选": the chat group's plate and outline in the visor.
  OverlayWorkspaceFieldSpec(
    'visorChatPlate',
    'look.chat',
    OverlayWorkspaceFieldKind.toggle,
    '聊天底框',
  ),
  OverlayWorkspaceFieldSpec(
    'visorHolidayGold',
    'appearance',
    OverlayWorkspaceFieldKind.toggle,
    '节日金色',
  ),
  // 11-06 "角标自由": the DM badge's position, moved by dragging it on the
  // canvas (screen fractions; -1 = the default spot).
  // 11-12 user: "我觉得应该允许事件随意调整位置了": where the events sit
  // across (a screen fraction of their screen-edge side; -1 = at that edge),
  // set by dragging them in the editor or Alt+M.
  OverlayWorkspaceFieldSpec(
    'visorEventsX',
    // hidden, like the badge's place (set by dragging, not a control)
    'appearance',
    OverlayWorkspaceFieldKind.number,
    '事件横向位置',
    minimum: -1,
    maximum: 1,
    userVisible: false,
  ),
  OverlayWorkspaceFieldSpec(
    'visorBadgeX',
    'appearance',
    OverlayWorkspaceFieldKind.number,
    '私信角标横向位置',
    minimum: -1,
    maximum: 1,
    userVisible: false,
  ),
  OverlayWorkspaceFieldSpec(
    'visorBadgeY',
    'appearance',
    OverlayWorkspaceFieldKind.number,
    '私信角标纵向位置',
    minimum: -1,
    maximum: 1,
    userVisible: false,
  ),
];

/// Settings one gesture writes together (the visor's DM badge X and Y, the
/// members box width and height): one undo step, not one per field per frame
/// (review CX-VISOR-EDITOR-B88-R1).
const overlayWorkspaceVisorHistoryGroups = {
  'visorBadgeX': 'visorBadge',
  'visorBadgeY': 'visorBadge',
  'visorMembersWidth': 'visorMembersSize',
  'visorMembersHeight': 'visorMembersSize',
};
