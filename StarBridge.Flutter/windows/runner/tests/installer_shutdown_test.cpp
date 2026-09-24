#include "win32_window.h"
#include <cstdio>

UINT FlutterDesktopGetDpiForMonitor(HMONITOR) { return 96; }
UINT FlutterDesktopGetDpiForHWND(HWND) { return 96; }

// Real Runner window dispatch, no Flutter engine, account, tray icon or Host.
// Model the product's configured close-to-tray interception.
class TrayWindow : public Win32Window {
 public:
  int close_requests = 0;
  int destructions = 0;
 protected:
  LRESULT MessageHandler(HWND window, UINT message, WPARAM wp, LPARAM lp) noexcept override {
    if (message == WM_CLOSE) { ++close_requests; return 0; }
    return Win32Window::MessageHandler(window, message, wp, lp);
  }
  void OnDestroy() override { ++destructions; }
};

int main() {
  int failures = 0;
  const auto check = [&](bool ok, const char* name) {
    std::printf("%s|%s\n", ok ? "PASS" : "FAIL", name);
    if (!ok) ++failures;
  };
  TrayWindow window;
  if (!window.Create(L"StarBridge hidden shutdown regression", {0, 0}, {900, 620})) return 2;
  const auto hwnd = window.GetHandle();
  const auto initial_destructions = window.destructions;
  window.SetQuitOnClose(true);
  check(!IsWindowVisible(hwnd), "fixture stays hidden");
  SendMessageW(hwnd, WM_CLOSE, 0, 0);
  check(IsWindow(hwnd) && window.close_requests == 1, "normal close retains tray behavior");
  check(SendMessageW(hwnd, WM_QUERYENDSESSION, 0, ENDSESSION_CLOSEAPP) == TRUE,
        "installer query is acknowledged");
  check(IsWindow(hwnd), "query alone does not close client");
  SendMessageW(hwnd, WM_ENDSESSION, FALSE, ENDSESSION_CLOSEAPP);
  check(IsWindow(hwnd) && window.destructions == initial_destructions, "cancelled installer shutdown preserves client");
  SendMessageW(hwnd, WM_ENDSESSION, TRUE, ENDSESSION_CLOSEAPP);
  check(!IsWindow(hwnd) && window.destructions == initial_destructions + 1,
        "confirmed installer shutdown destroys window and runs cleanup");
  check(window.close_requests == 1, "installer shutdown bypasses close-to-tray interception");
  MSG quit{};
  check(PeekMessageW(&quit, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE) != FALSE,
        "confirmed shutdown terminates the Runner message loop");
  return failures ? 1 : 0;
}
