#include "win32_window.h"
#include <cstdio>
#include <limits>

UINT FlutterDesktopGetDpiForMonitor(HMONITOR) { return 96; }
UINT FlutterDesktopGetDpiForHWND(HWND) { return 96; }

namespace {
int failures = 0;
void Check(bool ok, const char* name) {
  std::printf("%s|%s\n", ok ? "PASS" : "FAIL", name);
  if (!ok) ++failures;
}
int Pixels(HICON icon) {
  ICONINFO info{};
  if (!icon || !GetIconInfo(icon, &info)) return 0;
  BITMAP bitmap{};
  GetObjectW(info.hbmColor ? info.hbmColor : info.hbmMask, sizeof(bitmap), &bitmap);
  if (info.hbmColor) DeleteObject(info.hbmColor);
  if (info.hbmMask) DeleteObject(info.hbmMask);
  return bitmap.bmWidth;
}
HICON Query(HWND window, WPARAM kind, LPARAM dpi) {
  return reinterpret_cast<HICON>(SendMessageW(window, WM_GETICON, kind, dpi));
}
class TestWindow : public Win32Window {
 public:
  bool consume = false;
  int sets = 0, plugin_dpi = 0;
 protected:
  LRESULT MessageHandler(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept override {
    if (message == WM_SETICON) ++sets;
    if (consume && message == WM_GETICON && (wparam == ICON_SMALL || wparam == ICON_SMALL2)) return 0;
    if (consume && message == WM_DPICHANGED) { ++plugin_dpi; return 0; }
    return Win32Window::MessageHandler(window, message, wparam, lparam);
  }
};
}

int main() {
  SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  TestWindow window;
  Check(window.Create(L"StarBridge hidden icon regression", {0, 0}, {900, 620}), "create-hidden-window");
  const HWND hwnd = window.GetHandle();
  if (!hwnd) return 1;
  Check(!IsWindowVisible(hwnd), "no-visible-client");
  Check(ResolveSmallIconDpi(192, 96, 96, 96) == 192, "consumer-dpi-has-priority");
  Check(ResolveSmallIconDpi(0, 192, 144, 96) == 192, "fresh-shell-beats-stale-minimized-window");
  Check(ResolveSmallIconDpi(0, 0, 144, 96) == 144, "monitor-fallback-without-taskbar");
  Check(ResolveSmallIconDpi(-1, 0, 0, 120) == 120, "negative-request-falls-back");
  Check(ResolveSmallIconDpi((std::numeric_limits<LPARAM>::max)(), 0, 0, 0) == 96,
        "invalid-pointer-sized-request-is-bounded");
  const int sets = window.sets;
  const HICON big = Query(hwnd, ICON_BIG, 96);
  for (const int dpi : {96, 120, 144, 192, 240, 288, 384}) {
    const int expected = MulDiv(24, dpi, 96);
    for (const WPARAM kind : {ICON_SMALL, ICON_SMALL2}) {
      const HICON icon = Query(hwnd, kind, dpi);
      char label[96];
      std::snprintf(label, sizeof(label), "kind=%llu dpi=%d expected=%d actual=%d",
                    static_cast<unsigned long long>(kind), dpi, expected, Pixels(icon));
      Check(Pixels(icon) == expected, label);
      Check(Query(hwnd, kind, dpi) == icon, "repeat-query-stable-handle");
    }
  }
  Check(window.sets == sets, "queries-do-not-set-or-replace-window-icon");
  const HICON held = Query(hwnd, ICON_SMALL, 192);
  const DWORD handles_before = GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS);
  for (int i = 0; i < 1000; ++i) {
    Query(hwnd, ICON_SMALL, i % 2 ? 120 : 288);
  }
  Check(GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS) == handles_before,
        "repeated-mixed-dpi-queries-do-not-leak-handles");
  Check(Pixels(held) == 48, "older-borrowed-handle-remains-valid");
  Check(Pixels(Query(hwnd, ICON_SMALL, -1)) == Pixels(Query(hwnd, ICON_SMALL, 0)),
        "invalid-runtime-request-uses-current-fallback");
  Check(Query(hwnd, ICON_BIG, 192) == big, "large-icon-unchanged");
  window.consume = true;
  Check(Pixels(Query(hwnd, ICON_SMALL, 192)) == 48, "request-before-plugin-short-circuit");
  RECT rect{0, 0, 900, 620};
  SendMessageW(hwnd, WM_DPICHANGED, MAKELONG(192, 192), reinterpret_cast<LPARAM>(&rect));
  Check(window.plugin_dpi == 1, "plugin-still-receives-dpi-message");
  Check(Pixels(reinterpret_cast<HICON>(DefWindowProcW(hwnd, WM_GETICON, ICON_SMALL, 0))) == 48,
        "dpi-icon-refresh-before-plugin-short-circuit");
  window.Destroy();
  Check(!IsWindow(hwnd), "destroy-hidden-window");
  Check(Pixels(held) == 0, "window-destruction-releases-cached-icons");
  SmallApplicationIconCache cache;
  HICON dark = cache.Get(192, false), light = cache.Get(192, true);
  Check(dark && light && dark != light, "theme-caches-are-independent");
  Check(Pixels(dark) == 48 && Pixels(light) == 48, "both-themes-have-native-size");
  Check(cache.Get(192, false) == dark && cache.Get(192, true) == light,
        "theme-switch-reuses-live-cache");
  Check(Pixels(cache.Get(1024, false)) == 256, "largest-size-bounded-to-existing-frames");
  cache.Clear();
  Check(Pixels(dark) == 0 && Pixels(light) == 0, "both-theme-handles-released");
  cache.Clear();
  return failures == 0 ? 0 : 1;
}
