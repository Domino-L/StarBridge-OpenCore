#include "menu_overlay_window.h"
#include "menu_overlay_focus.h"
#include <cstdio>

// Hidden Win32 fixture, not an acceptance client; never reveals or steals focus.
int main() {
  const HWND foreground = GetForegroundWindow();
  int failed = 0;
  auto check = [&failed](bool condition, const char* name) {
    printf("%s|%s\n", condition ? "PASS" : "FAIL", name);
    if (!condition) ++failed;
  };
  HWND created = nullptr;
  {
    MenuOverlayWindow window;
    check(window.Create(), "create independent DWM candidate");
    created = window.handle();
    if (!created) return 1;
    check(!IsWindowVisible(created), "creation remains hidden");
    check(GetWindow(created, GW_OWNER) == nullptr, "does not own or raise desktop client");
    check((GetWindowLongPtrW(created, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0, "tool window");
    check(window.Begin() == 0, "cannot open without child");
    check(!window.Attach(nullptr), "invalid child refused");
    HWND child = CreateWindowExW(0, L"STATIC", L"", WS_CHILD, 0, 0, 10, 10,
        created, nullptr, GetModuleHandleW(nullptr), nullptr);
    check(window.Attach(child), "attach fixture child");
    // Test the classifier with an owned hidden target, not the agent runner's
    // desktop (which legitimately has no foreground in a headless session).
    HWND target = CreateWindowExW(0, L"STATIC", L"", WS_POPUP,
        0, 0, 10, 10, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    check(target && IsMenuRevealForeground(target, target, created),
        "original foreground permits reveal");
    check(IsMenuRevealForeground(created, foreground, created),
        "own menu foreground permits reveal");
    check(IsMenuRevealForeground(child, foreground, created),
        "own Flutter child foreground permits reveal");
    HWND unrelated = CreateWindowExW(0, L"STATIC", L"", WS_POPUP,
        0, 0, 10, 10, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    check(!IsMenuRevealForeground(unrelated, foreground, created),
        "unrelated same-process window still rejects reveal");
    check(!IsMenuRevealForeground(nullptr, foreground, created),
        "missing foreground rejects reveal");
    DestroyWindow(target);
    DestroyWindow(unrelated);
    int hidden = 0;
    window.on_hidden = [&hidden]() { ++hidden; };
    const auto opening = window.Begin();
    check(opening > 0 && window.session().wanted(), "opening lease created");
    check(!IsWindowVisible(created), "await first frame hidden");
    check(window.Begin() == 0, "duplicate begin refused");
    window.Hide(true);
    check(hidden == 1 && !window.session().wanted(), "hide dispatches once");
    check(!window.Reveal(opening), "cancelled frame cannot reveal HWND");
    window.Hide();
    check(hidden == 1, "repeated hide silent");
    check(!window.RegisterShortcut(0, 0), "invalid shortcut refused");
    check(!window.RegisterShortcut(0x80000000, 'M'), "invalid modifiers refused");
    // Temporarily reserve an uncommon chord in this fixture; never send it.
    // A pre-existing OS/user registration is not overwritten by either call.
    constexpr UINT modifiers = MOD_CONTROL | MOD_SHIFT | MOD_ALT;
    const bool fixture_reserved = RegisterHotKey(created, 0x1234, modifiers, VK_F24) != FALSE;
    check(!window.RegisterShortcut(modifiers, VK_F24), "occupied shortcut rejected");
    if (fixture_reserved) {
      UnregisterHotKey(created, 0x1234);
      check(window.RegisterShortcut(modifiers, VK_F24), "released shortcut can register");
      window.UnregisterShortcut();
      check(RegisterHotKey(created, 0x1234, modifiers, VK_F24) != FALSE,
          "unregister releases shortcut");
      UnregisterHotKey(created, 0x1234);
    }
    check(window.Begin(created) == 0, "changed foreground rejects opening");
    window.Begin();
    SendMessageW(created, WM_ACTIVATE, WA_INACTIVE, 0);
    check(!window.session().wanted(), "deactivation cancels pending opening");
    window.Begin();
    SendMessageW(created, WM_TIMER, 0x534d, 0);
    check(!window.session().wanted(), "first-frame timeout cancels opening");
    window.Begin();
    SendMessageW(created, WM_CLOSE, 0, 0);
    check(IsWindow(created) && !window.session().wanted(), "close hides for reuse");
  }
  check(!IsWindow(created), "destructor destroys window");
  check(GetForegroundWindow() == foreground, "fixture never changes foreground");
  return failed == 0 ? 0 : 1;
}
