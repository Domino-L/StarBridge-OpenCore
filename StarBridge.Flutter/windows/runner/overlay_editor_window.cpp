#include "overlay_editor_window.h"

namespace {

// Windows treats a window that covers a whole monitor, or one marked through
// ITaskbarList2::MarkFullscreenWindow, as a full-screen app, and Windows 11
// then turns on Do Not Disturb. The editor stops one row short of the monitor
// and stays above the taskbar by being topmost while it is the active window.
RECT EditorRect(const RECT& monitor) {
  RECT rect = monitor;
  rect.bottom -= 1;
  return rect;
}

}  // namespace

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
  saved.topmost = (GetWindowLongPtr(window_, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
  snapshot_ = saved;
  ShowWindow(window_, SW_RESTORE);
  SetLastError(ERROR_SUCCESS);
  const auto previousStyle = SetWindowLongPtr(window_, GWL_STYLE,
                   saved.style & ~(WS_OVERLAPPEDWINDOW | WS_MAXIMIZE | WS_MINIMIZE));
  if (previousStyle == 0 && GetLastError() != ERROR_SUCCESS) {
    Exit();
    return false;
  }
  const RECT rect = EditorRect(monitor.rcMonitor);
  if (!SetWindowPos(window_, nullptr, rect.left, rect.top,
                    rect.right - rect.left, rect.bottom - rect.top,
                    SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)) {
    Exit();
    return false;
  }
  KeepAboveTaskbar(GetForegroundWindow() == window_);
  return true;
}

bool OverlayEditorWindow::Exit() {
  if (!active()) return true;
  if (!IsWindow(window_)) {
    snapshot_.reset();
    return true;
  }
  const auto saved = snapshot_.value();
  // Stop WM_ACTIVATE/WM_DISPLAYCHANGE from raising the editor above the
  // taskbar again while the restored style and maximized placement dispatch
  // messages after Flutter has already popped the editor route.
  snapshot_.reset();
  RestoreZOrder(saved.topmost);
  const auto restoredStyle = saved.style & ~(WS_MAXIMIZE | WS_MINIMIZE);
  SetLastError(ERROR_SUCCESS);
  const auto previousStyle =
      SetWindowLongPtr(window_, GWL_STYLE, restoredStyle);
  if (previousStyle == 0 && GetLastError() != ERROR_SUCCESS) {
    snapshot_ = saved;
    KeepAboveTaskbar(GetForegroundWindow() == window_);
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
    KeepAboveTaskbar(GetForegroundWindow() == window_);
    return false;
  }
  if (!SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                    SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOMOVE |
                    SWP_NOSIZE | SWP_FRAMECHANGED)) {
    snapshot_ = saved;
    KeepAboveTaskbar(GetForegroundWindow() == window_);
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
  return true;
}

void OverlayEditorWindow::FitMonitor() {
  if (!active() || IsIconic(window_)) return;
  MONITORINFO monitor{sizeof(MONITORINFO)};
  if (!GetMonitorInfo(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
                      &monitor)) return;
  const RECT rect = EditorRect(monitor.rcMonitor);
  SetWindowPos(window_, nullptr, rect.left, rect.top,
               rect.right - rect.left, rect.bottom - rect.top,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void OverlayEditorWindow::OnActivate(bool active) {
  if (!this->active()) return;
  KeepAboveTaskbar(active);
}

// Topmost only while the editor is the active window: it covers the taskbar
// like a full-screen surface, and switching to another app lets that app on top.
void OverlayEditorWindow::KeepAboveTaskbar(bool enabled) {
  const bool keep = enabled || (snapshot_.has_value() && snapshot_->topmost);
  SetWindowPos(window_, keep ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void OverlayEditorWindow::RestoreZOrder(bool topmost) {
  SetWindowPos(window_, topmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}
