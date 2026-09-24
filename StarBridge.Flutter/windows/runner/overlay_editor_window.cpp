#include "overlay_editor_window.h"

#include <shobjidl.h>

OverlayEditorWindow::~OverlayEditorWindow() { Exit(); }

bool OverlayEditorWindow::Enter() {
  if (active()) return true;
  if (!IsWindow(window_)) return false;
  Snapshot saved;
  saved.placement.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(window_, &saved.placement)) return false;
  MONITORINFO monitor{sizeof(MONITORINFO)};
  if (!GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return false;
  saved.style = GetWindowLongPtr(window_, GWL_STYLE);
  snapshot_ = saved;
  ShowWindow(window_, SW_RESTORE);
  SetLastError(ERROR_SUCCESS);
  const auto previousStyle = SetWindowLongPtr(window_, GWL_STYLE,
                   saved.style & ~(WS_OVERLAPPEDWINDOW | WS_MAXIMIZE | WS_MINIMIZE));
  if (previousStyle == 0 && GetLastError() != ERROR_SUCCESS) {
    Exit();
    return false;
  }
  const RECT& rect = monitor.rcMonitor;
  if (!SetWindowPos(window_, nullptr, rect.left, rect.top,
                    rect.right - rect.left, rect.bottom - rect.top,
                    SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)) {
    Exit();
    return false;
  }
  MarkFullscreen(GetForegroundWindow() == window_);
  return true;
}

bool OverlayEditorWindow::Exit() {
  if (!active()) return true;
  if (!IsWindow(window_)) {
    snapshot_.reset();
    return true;
  }
  const auto saved = snapshot_.value();
  // Stop WM_ACTIVATE/WM_DISPLAYCHANGE from reasserting the fullscreen taskbar
  // hint while the restored style and maximized placement dispatch messages.
  // Otherwise Explorer can keep the taskbar hidden after Flutter has already
  // popped the editor route.
  snapshot_.reset();
  MarkFullscreen(false);
  const auto restoredStyle = saved.style & ~(WS_MAXIMIZE | WS_MINIMIZE);
  SetLastError(ERROR_SUCCESS);
  const auto previousStyle =
      SetWindowLongPtr(window_, GWL_STYLE, restoredStyle);
  if (previousStyle == 0 && GetLastError() != ERROR_SUCCESS) {
    snapshot_ = saved;
    MarkFullscreen(GetForegroundWindow() == window_);
    return false;
  }
  // A maximized Flutter window must make a real normal -> maximized
  // transition here. Writing WS_MAXIMIZE back before restoring the normal
  // placement leaves Explorer treating the old monitor-sized editor surface
  // as fullscreen, so the taskbar remains covered after the route is gone.
  WINDOWPLACEMENT normalPlacement = saved.placement;
  normalPlacement.flags = 0;
  normalPlacement.showCmd = SW_SHOWNORMAL;
  if (!SetWindowPlacement(window_, &normalPlacement)) {
    snapshot_ = saved;
    MarkFullscreen(GetForegroundWindow() == window_);
    return false;
  }
  if (!SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                    SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOMOVE |
                    SWP_NOSIZE | SWP_FRAMECHANGED)) {
    snapshot_ = saved;
    MarkFullscreen(GetForegroundWindow() == window_);
    return false;
  }
  switch (saved.placement.showCmd) {
    case SW_SHOWMAXIMIZED:
      ShowWindow(window_, SW_MAXIMIZE);
      break;
    case SW_SHOWMINIMIZED:
    case SW_MINIMIZE:
    case SW_SHOWMINNOACTIVE:
      ShowWindow(window_, saved.placement.showCmd);
      break;
    default:
      if ((saved.style & WS_VISIBLE) == 0) {
        ShowWindow(window_, SW_HIDE);
      }
      break;
  }
  // Clear again after the final frame/placement notifications. This is
  // idempotent and makes Explorer repaint the taskbar region reliably.
  MarkFullscreen(false);
  return true;
}

void OverlayEditorWindow::FitMonitor() {
  if (!active() || IsIconic(window_)) return;
  MONITORINFO monitor{sizeof(MONITORINFO)};
  if (!GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return;
  const RECT& rect = monitor.rcMonitor;
  SetWindowPos(window_, nullptr, rect.left, rect.top,
               rect.right - rect.left, rect.bottom - rect.top,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void OverlayEditorWindow::OnActivate(bool active) {
  MarkFullscreen(this->active() && active);
}

void OverlayEditorWindow::MarkFullscreen(bool enabled) {
  ITaskbarList2* taskbar = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&taskbar)))) {
    if (SUCCEEDED(taskbar->HrInit())) {
      taskbar->MarkFullscreenWindow(window_, enabled ? TRUE : FALSE);
    }
    taskbar->Release();
  }
}
