/// The client's screen reading settings (local to this computer), where the own
/// health reading switch lives (user, 11-10: "读血不应该放在这里吧，这是一个本机设置",
/// "甚至可以在设置里单独放一个屏幕读取类设置").
const screenReadingSettingsRoute = '/settings/screen-reading';

/// Whether that settings section is in this build. Pages that lead to it show
/// their link only when it is, so a link never leads nowhere. The health
/// reading line sets this to true together with the section (its r4).
const screenReadingSettingsAvailable = true;
