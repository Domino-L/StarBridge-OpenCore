#pragma once
#include <windows.h>
#include <cstdint>
#include <atomic>

// Native-only primary owner registration. The PID comes from the connected
// OS pipe, never Dart arguments. Failure affects preview availability only.
class PrimaryWindowBridgeLease {
 public:
  explicit PrimaryWindowBridgeLease(HWND window) noexcept : window_(window) {}
  ~PrimaryWindowBridgeLease() { Clear(); }
  PrimaryWindowBridgeLease(const PrimaryWindowBridgeLease&) = delete;
  PrimaryWindowBridgeLease& operator=(const PrimaryWindowBridgeLease&) = delete;
  bool Publish(HANDLE pipe) noexcept {
    Clear();
    DWORD client = 0;
    ULONG server = 0;
    if (!IsWindow(window_) || GetAncestor(window_, GA_ROOT) != window_ ||
        !GetWindowThreadProcessId(window_, &client) ||
        client != GetCurrentProcessId() ||
        !GetNamedPipeServerProcessId(pipe, &server) || server == 0 ||
        GetPropW(window_, kLease) != nullptr) return false;
    if (!SetPropW(window_, kLease, reinterpret_cast<HANDLE>(this))) return false;
    if (!SetPropW(window_, kServerPid,
        reinterpret_cast<HANDLE>(static_cast<uintptr_t>(server)))) {
      RemovePropW(window_, kLease);
      return false;
    }
    const uintptr_t epoch = next_epoch_.fetch_add(1) + 1;
    if (epoch == 0 || !SetPropW(window_, kEpoch, reinterpret_cast<HANDLE>(epoch))) {
      Clear();
      return false;
    }
    return true;
  }
  void Clear() noexcept {
    if (IsWindow(window_) && GetPropW(window_, kLease) == reinterpret_cast<HANDLE>(this)) {
      RemovePropW(window_, kServerPid);
      RemovePropW(window_, kEpoch);
      RemovePropW(window_, kLease);
    }
  }
  static constexpr const wchar_t* kLease = L"StarBridge.NativeHostBridge.PrimaryLease";
  static constexpr const wchar_t* kServerPid = L"StarBridge.NativeHostBridge.ServerPid";
  static constexpr const wchar_t* kEpoch = L"StarBridge.NativeHostBridge.ConnectionEpoch";
 private:
  HWND window_;
  inline static std::atomic<uintptr_t> next_epoch_{0};
};
