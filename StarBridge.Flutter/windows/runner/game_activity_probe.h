#pragma once
// Read once a minute while the opt-in frame pace diagnostics are on, and by
// the frame pressure channel (at most once a second, only while a surface is
// asking for frames). Reports presence only: no process names, titles or
// paths leave this file.
#include <windows.h>
#include <tlhelp32.h>
#include <wchar.h>

#include <vector>

namespace game_activity {

struct Activity {
  bool star_citizen = false;
  // Another program fills its monitor in the foreground: usually a game,
  // sometimes a full-screen video.
  bool other_fullscreen = false;
};

inline bool IsStarCitizenExe(const wchar_t* name) {
  if (!name) return false;
  static constexpr const wchar_t* kNames[] = {
      L"StarCitizen.exe", L"StarCitizen_LIVE.exe", L"StarCitizen_PTUR.exe",
      L"StarCitizen_EPTU.exe", L"StarCitizen_HOTFIX.exe",
      L"StarCitizen_TECH-PREVIEW.exe"};
  for (const auto* known : kNames) {
    if (_wcsicmp(name, known) == 0) return true;
  }
  return false;
}

inline bool CoversMonitor(const RECT& window, const RECT& monitor) {
  return monitor.right > monitor.left && monitor.bottom > monitor.top &&
         window.left <= monitor.left && window.top <= monitor.top &&
         window.right >= monitor.right && window.bottom >= monitor.bottom;
}

// Desktop and shell surfaces cover the monitor too; they are not programs.
// kUnknown: the class name could not be read, so the window is unclassified.
enum class SurfaceKind { kShell, kProgram, kUnknown };
inline SurfaceKind ClassifySurface(HWND window) {
  if (window == GetShellWindow() || window == GetDesktopWindow()) {
    return SurfaceKind::kShell;
  }
  wchar_t name[32]{};
  if (GetClassNameW(window, name, 32) == 0) return SurfaceKind::kUnknown;
  return _wcsicmp(name, L"Progman") == 0 || _wcsicmp(name, L"WorkerW") == 0 ||
                 _wcsicmp(name, L"Shell_TrayWnd") == 0
             ? SurfaceKind::kShell
             : SurfaceKind::kProgram;
}

// The diagnostics' presence read keeps its original meaning: an unreadable
// class counts as a shell surface (never reported as a fullscreen program).
inline bool IsShellSurface(HWND window) {
  return ClassifySurface(window) != SurfaceKind::kProgram;
}

// Process ids only; names never leave this file. Returns false when the
// process list could not be read, so callers can tell "unknown" from "none".
inline bool TryStarCitizenProcessIds(std::vector<DWORD>& star_citizen) {
  star_citizen.clear();
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return false;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  // The walk ends normally only with ERROR_NO_MORE_FILES (from First on an
  // empty list or from Next after the last entry); anything else is a partial
  // or failed read, which must count as unknown, not as "no game". The code is
  // captured right where the walk stops, before any other call can change it.
  BOOL more = Process32FirstW(snapshot, &entry);
  DWORD end = more ? ERROR_SUCCESS : GetLastError();
  while (more) {
    if (IsStarCitizenExe(entry.szExeFile)) {
      star_citizen.push_back(entry.th32ProcessID);
    }
    more = Process32NextW(snapshot, &entry);
    if (!more) end = GetLastError();
  }
  CloseHandle(snapshot);
  return end == ERROR_NO_MORE_FILES;
}

// The diagnostics' presence read: an unreadable list counts as no game.
inline std::vector<DWORD> StarCitizenProcessIds() {
  std::vector<DWORD> star_citizen;
  TryStarCitizenProcessIds(star_citizen);
  return star_citizen;
}

inline Activity Read() {
  Activity activity;
  const std::vector<DWORD> star_citizen = StarCitizenProcessIds();
  activity.star_citizen = !star_citizen.empty();
  const HWND foreground = GetForegroundWindow();
  if (!foreground || !IsWindowVisible(foreground) || IsIconic(foreground) ||
      IsShellSurface(foreground)) {
    return activity;
  }
  DWORD pid = 0;
  GetWindowThreadProcessId(foreground, &pid);
  if (pid == 0 || pid == GetCurrentProcessId()) return activity;
  for (const DWORD game : star_citizen) {
    if (game == pid) return activity;
  }
  RECT window{};
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  const HMONITOR handle = MonitorFromWindow(foreground, MONITOR_DEFAULTTONULL);
  if (handle && GetWindowRect(foreground, &window) &&
      GetMonitorInfoW(handle, &monitor)) {
    activity.other_fullscreen = CoversMonitor(window, monitor.rcMonitor);
  }
  return activity;
}

}  // namespace game_activity
