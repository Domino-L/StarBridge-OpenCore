#pragma once
// "starbridge/frame-pressure": tells each Flutter surface whether a game is
// running, whether it is in front, and whether this client owns the
// foreground, so the surface can lower its frame rate and leave the GPU to
// the game. Presence only; no names, titles or paths are reported.
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <vector>

#include "game_activity_probe.h"

namespace frame_pressure {

struct Pressure {
  // False when the state could not be determined (no foreground window, no
  // process id, process list unreadable). Dart then never limits.
  bool valid = false;
  bool game_running = false;
  // Star Citizen, or another program filling its monitor, is the foreground.
  bool game_in_front = false;
  // One of this process's windows (main, menu, tray, friends...) is in front.
  bool own_foreground = false;
};

inline Pressure ReadUncached() {
  Pressure pressure;
  std::vector<DWORD> games;
  if (!game_activity::TryStarCitizenProcessIds(games)) return pressure;
  pressure.game_running = !games.empty();
  const HWND foreground = GetForegroundWindow();
  if (!foreground) return pressure;
  DWORD pid = 0;
  if (GetWindowThreadProcessId(foreground, &pid) == 0 || pid == 0) {
    return pressure;
  }
  // valid is set only on a branch that fully classified the foreground; every
  // failed query below returns the default (invalid: Dart never limits).
  if (pid == GetCurrentProcessId()) {
    pressure.own_foreground = true;
    pressure.valid = true;
    return pressure;
  }
  // A window destroyed between queries also reads as not visible, so "not
  // visible" proves nothing: unknown. Minimized is reported only for a live
  // minimized window, so it may stand for background.
  if (!IsWindowVisible(foreground)) {
    return pressure;
  }
  if (IsIconic(foreground)) {
    pressure.valid = true;  // a minimized foreground: background
    return pressure;
  }
  const game_activity::SurfaceKind surface =
      game_activity::ClassifySurface(foreground);
  if (surface == game_activity::SurfaceKind::kUnknown) {
    return pressure;  // class unreadable: unknown, never a limit
  }
  if (surface == game_activity::SurfaceKind::kShell) {
    pressure.valid = true;  // the desktop or taskbar: background
    return pressure;
  }
  for (const DWORD game : games) {
    if (game == pid) {
      pressure.game_in_front = true;
      pressure.valid = true;
      return pressure;
    }
  }
  RECT window{};
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  const HMONITOR handle = MonitorFromWindow(foreground, MONITOR_DEFAULTTONULL);
  if (!handle || !GetWindowRect(foreground, &window) ||
      !GetMonitorInfoW(handle, &monitor)) {
    return pressure;  // cannot tell fullscreen from windowed: unknown
  }
  pressure.game_in_front =
      game_activity::CoversMonitor(window, monitor.rcMonitor);
  pressure.valid = true;
  return pressure;
}

// Every engine's platform thread is this process's main thread, so one cache
// serves all surfaces without locking. At most one process snapshot a second.
inline Pressure Read() {
  static Pressure cached;
  static ULONGLONG read_at = 0;
  static bool has_value = false;
  const ULONGLONG now = GetTickCount64();
  if (!has_value || now - read_at >= 1000) {
    cached = ReadUncached();
    read_at = now;
    has_value = true;
  }
  return cached;
}

// Owned by each surface next to its FlutterViewController; reset it before
// the controller so the handler never outlives the messenger.
class Channel {
 public:
  explicit Channel(flutter::BinaryMessenger* messenger)
      : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            messenger, "starbridge/frame-pressure",
            &flutter::StandardMethodCodec::GetInstance())) {
    channel_->SetMethodCallHandler([](const auto& call, auto result) {
      if (call.method_name() != "read") {
        result->NotImplemented();
        return;
      }
      const Pressure pressure = Read();
      if (!pressure.valid) {
        // Unknown: Dart reads null and never limits.
        result->Success(flutter::EncodableValue());
        return;
      }
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("gameRunning"),
           flutter::EncodableValue(pressure.game_running)},
          {flutter::EncodableValue("gameInFront"),
           flutter::EncodableValue(pressure.game_in_front)},
          {flutter::EncodableValue("ownForeground"),
           flutter::EncodableValue(pressure.own_foreground)},
      }));
    });
  }
  ~Channel() { channel_->SetMethodCallHandler(nullptr); }
  Channel(const Channel&) = delete;
  Channel& operator=(const Channel&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace frame_pressure
