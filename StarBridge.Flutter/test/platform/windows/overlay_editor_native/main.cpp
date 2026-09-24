#include <windows.h>
#include <iostream>
#include <string>
#include "overlay_editor_window.h"

namespace {
OverlayEditorWindow* active_editor = nullptr;
bool observe_restore = false;
bool active_during_restore = false;
bool expect_maximized_restore = false;
bool saw_restored_during_restore = false;
bool saw_maximized_after_restore = false;
bool wrote_maximized_style_before_restore = false;
}

// Real Win32 calls on a private, non-input desktop. Never SwitchDesktop.
// No user window, input, account or game process is accessed.
LRESULT CALLBACK TestProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  if (observe_restore && message == WM_SIZE) {
    if (wp == SIZE_RESTORED) saw_restored_during_restore = true;
    if (wp == SIZE_MAXIMIZED && saw_restored_during_restore) {
      saw_maximized_after_restore = true;
    }
  }
  if (observe_restore && expect_maximized_restore &&
      message == WM_STYLECHANGED) {
    const auto* changed = reinterpret_cast<const STYLESTRUCT*>(lp);
    if (changed && (changed->styleNew & WS_MAXIMIZE) != 0 &&
        !saw_restored_during_restore) {
      wrote_maximized_style_before_restore = true;
    }
  }
  if (observe_restore && active_editor && active_editor->active() &&
      (message == WM_STYLECHANGED || message == WM_WINDOWPOSCHANGING ||
       message == WM_ACTIVATE)) {
    active_during_restore = true;
  }
  const auto result = DefWindowProc(hwnd, message, wp, lp);
  // A nested, successful window message may leave a last-error value behind.
  if (message == WM_STYLECHANGED) SetLastError(ERROR_INVALID_WINDOW_HANDLE);
  return result;
}

int main() {
  const auto original = GetThreadDesktop(GetCurrentThreadId());
  const auto name = L"StarBridgeOverlayTest_" + std::to_wstring(GetCurrentProcessId());
  const auto desktop = CreateDesktop(name.c_str(), nullptr, nullptr, 0,
    DESKTOP_CREATEWINDOW | DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS, nullptr);
  if (!desktop || !SetThreadDesktop(desktop)) {
    std::cerr << "FAIL|isolated-desktop|" << GetLastError() << std::endl;
    return 2;
  }
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  WNDCLASS wc{};
  wc.lpfnWndProc = TestProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = L"StarBridgeOverlayWindowTest";
  RegisterClass(&wc);
  int failures = 0;
  // Eight alternating normal/maximized cycles catch state leakage while
  // keeping the COM taskbar integration test well inside CI time limits.
  for (int i = 0; i < 8; ++i) {
    const auto hwnd = CreateWindow(wc.lpszClassName, L"Isolated editor regression",
      WS_OVERLAPPEDWINDOW, 70, 80, 800, 600, nullptr, nullptr, wc.hInstance, nullptr);
    if (!hwnd) { ++failures; continue; }
    if (i % 2) ShowWindow(hwnd, SW_SHOWMAXIMIZED);
    WINDOWPLACEMENT before{sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(hwnd, &before);
    {
      OverlayEditorWindow editor(hwnd);
      active_editor = &editor;
      const auto entered = editor.Enter();
      std::cout << (entered ? "PASS" : "FAIL") << "|enter|" << i << std::endl;
      if (!entered || !editor.active()) ++failures;
      RECT actual{};
      GetWindowRect(hwnd, &actual);
      MONITORINFO monitor{sizeof(MONITORINFO)};
      GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor);
      if (entered && !EqualRect(&actual, &monitor.rcMonitor)) {
        ++failures; std::cout << "FAIL|monitor-bounds|" << i << std::endl;
      }
      active_during_restore = false;
      expect_maximized_restore = before.showCmd == SW_SHOWMAXIMIZED;
      saw_restored_during_restore = false;
      saw_maximized_after_restore = false;
      wrote_maximized_style_before_restore = false;
      observe_restore = true;
      const auto exited = editor.Exit();
      observe_restore = false;
      if (!exited || editor.active()) {
        ++failures; std::cout << "FAIL|exit|" << i << std::endl;
      }
      if (active_during_restore) {
        ++failures;
        std::cout << "FAIL|active-during-restore|" << i << std::endl;
      }
      if (expect_maximized_restore &&
          (wrote_maximized_style_before_restore ||
           !saw_restored_during_restore || !saw_maximized_after_restore)) {
        ++failures;
        std::cout << "FAIL|maximized-restore-transition|" << i
                  << "|max-style-before-restore="
                  << wrote_maximized_style_before_restore
                  << "|saw-restored=" << saw_restored_during_restore
                  << "|saw-maximized-after=" << saw_maximized_after_restore
                  << std::endl;
      }
      WINDOWPLACEMENT after{sizeof(WINDOWPLACEMENT)};
      GetWindowPlacement(hwnd, &after);
      if (!EqualRect(&before.rcNormalPosition, &after.rcNormalPosition) || before.showCmd != after.showCmd) {
        ++failures; std::cout << "FAIL|restore|" << i << std::endl;
      }
      active_editor = nullptr;
    }
    DestroyWindow(hwnd);
  }
  UnregisterClass(wc.lpszClassName, wc.hInstance);
  CoUninitialize();
  SetThreadDesktop(original);
  CloseDesktop(desktop);
  std::cout << "RESULT|failures=" << failures << std::endl;
  return failures ? 1 : 0;
}
