#pragma once
#include <windows.h>
#include <winternl.h>
#include <cstddef>
#include <filesystem>
#include <functional>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace hangar_data {
enum class ClearResult { success, unsafe_path, busy, failed };

inline ClearResult Failure(DWORD error) {
  return error == ERROR_SHARING_VIOLATION || error == ERROR_LOCK_VIOLATION ||
         error == ERROR_ACCESS_DENIED || error == ERROR_DIR_NOT_EMPTY ||
         error == ERROR_DELETE_PENDING
      ? ClearResult::busy : ClearResult::failed;
}
inline bool Missing(DWORD error) {
  return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
}
inline bool SingleName(const std::wstring& name) {
  return !name.empty() && name != L"." && name != L".." &&
      name.find_first_of(L"\\/:") == std::wstring::npos &&
      name.find(L'\0') == std::wstring::npos && name.size() <= 32767;
}

// Choice (a): one-component relative opens never resolve an ancestor path.
// No delete sharing pins every opened entry against rename/replacement. No
// write sharing also excludes handles capable of changing reparse data.
class DirectoryGuard {
 public:
  explicit DirectoryGuard(const std::filesystem::path& path)
      : handle_(CreateFileW(path.c_str(), Access(), FILE_SHARE_READ, nullptr,
            OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
            nullptr)) {}
  DirectoryGuard(HANDLE parent, const std::wstring& name) {
    if (!SingleName(name)) { SetLastError(ERROR_INVALID_NAME); return; }
    const auto module = GetModuleHandleW(L"ntdll.dll");
    const auto create = reinterpret_cast<decltype(&NtCreateFile)>(
        GetProcAddress(module, "NtCreateFile"));
    using Translate = ULONG (WINAPI*)(NTSTATUS);
    const auto translate = reinterpret_cast<Translate>(
        GetProcAddress(module, "RtlNtStatusToDosError"));
    if (!create || !translate) { SetLastError(ERROR_NOT_SUPPORTED); return; }
    UNICODE_STRING text{};
    text.Buffer = const_cast<PWSTR>(name.data());
    text.Length = text.MaximumLength = static_cast<USHORT>(name.size() * sizeof(wchar_t));
    OBJECT_ATTRIBUTES attributes{};
    attributes.Length = sizeof(attributes);
    attributes.RootDirectory = parent;
    attributes.ObjectName = &text;
    IO_STATUS_BLOCK status{};
    HANDLE opened = INVALID_HANDLE_VALUE;
    // FILE_OPEN, FILE_OPEN_REPARSE_POINT, FILE_SYNCHRONOUS_IO_NONALERT,
    // FILE_OPEN_FOR_BACKUP_INTENT. winternl.h does not expose all SDK constants.
    const auto result = create(&opened, Access(), &attributes, &status, nullptr,
        0, FILE_SHARE_READ, 1, 0x00200000 | 0x00000020 | 0x00004000, nullptr, 0);
    if (result < 0) { SetLastError(translate(result)); return; }
    handle_ = opened;
  }
  ~DirectoryGuard() { Release(); }
  DirectoryGuard(const DirectoryGuard&) = delete;
  DirectoryGuard& operator=(const DirectoryGuard&) = delete;
  bool Valid() const { return handle_ != INVALID_HANDLE_VALUE; }
  HANDLE Get() const { return handle_; }
  bool Info(BY_HANDLE_FILE_INFORMATION& info) const {
    return GetFileInformationByHandle(handle_, &info) != FALSE;
  }
  void Release() {
    if (Valid()) { CloseHandle(handle_); handle_ = INVALID_HANDLE_VALUE; }
  }
 private:
  static DWORD Access() {
    // WRITE_ATTRIBUTES is needed only by the legacy read-only disposition fallback.
    return DELETE | FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES |
        FILE_WRITE_ATTRIBUTES | SYNCHRONIZE;
  }
  HANDLE handle_ = INVALID_HANDLE_VALUE;
};

inline bool FinalPath(HANDLE handle, std::filesystem::path& path) {
  const DWORD length = GetFinalPathNameByHandleW(handle, nullptr, 0, FILE_NAME_NORMALIZED);
  if (!length) return false;
  std::vector<wchar_t> text(static_cast<size_t>(length) + 1);
  const DWORD written = GetFinalPathNameByHandleW(handle, text.data(),
      static_cast<DWORD>(text.size()), FILE_NAME_NORMALIZED);
  if (!written || written >= text.size()) return false;
  path = std::wstring(text.data(), written);
  return true;
}
inline std::wstring ComparablePath(const std::filesystem::path& path) {
  auto text = path.wstring();
  if (text.rfind(L"\\\\?\\UNC\\", 0) == 0) text = L"\\\\" + text.substr(8);
  else if (text.rfind(L"\\\\?\\", 0) == 0) text.erase(0, 4);
  for (auto& c : text) if (c == L'/') c = L'\\';
  while (text.size() > 3 && text.back() == L'\\') text.pop_back();
  return text;
}
// Exact match: directories can be case-sensitive, so "starbridge" and a
// "StarBridge" junction may coexist. A spelling mismatch only refuses deletion.
inline bool SamePath(const std::filesystem::path& left, const std::filesystem::path& right) {
  const auto a = ComparablePath(left), b = ComparablePath(right);
  return CompareStringOrdinal(a.c_str(), static_cast<int>(a.size()),
      b.c_str(), static_cast<int>(b.size()), FALSE) == CSTR_EQUAL;
}

inline ClearResult DeleteOpened(HANDLE handle, bool legacy = false) {
  if (!legacy) {
    FILE_DISPOSITION_INFO_EX disposition{};
    disposition.Flags = FILE_DISPOSITION_FLAG_DELETE | FILE_DISPOSITION_FLAG_POSIX_SEMANTICS |
        FILE_DISPOSITION_FLAG_IGNORE_READONLY_ATTRIBUTE;
    if (SetFileInformationByHandle(handle, FileDispositionInfoEx, &disposition,
          sizeof(disposition))) return ClearResult::success;
    const auto error = GetLastError();
    if (error != ERROR_INVALID_PARAMETER && error != ERROR_NOT_SUPPORTED &&
        error != ERROR_INVALID_FUNCTION && error != ERROR_CALL_NOT_IMPLEMENTED)
      return Failure(error);
  }
  FILE_BASIC_INFO basic{};
  if (!GetFileInformationByHandleEx(handle, FileBasicInfo, &basic, sizeof(basic)))
    return Failure(GetLastError());
  const auto original = basic.FileAttributes;
  const bool readonly = (original & FILE_ATTRIBUTE_READONLY) != 0;
  if (readonly) {
    // Attributes belong to the file, not the name: clearing read-only would
    // also change a hard link outside this folder. Refuse instead.
    BY_HANDLE_FILE_INFORMATION links{};
    if (!GetFileInformationByHandle(handle, &links)) return Failure(GetLastError());
    if (links.nNumberOfLinks > 1) return ClearResult::failed;
    basic.FileAttributes &= ~FILE_ATTRIBUTE_READONLY;
    if (!basic.FileAttributes) basic.FileAttributes = FILE_ATTRIBUTE_NORMAL;
    if (!SetFileInformationByHandle(handle, FileBasicInfo, &basic, sizeof(basic)))
      return Failure(GetLastError());
  }
  FILE_DISPOSITION_INFO disposition{TRUE};
  if (SetFileInformationByHandle(handle, FileDispositionInfo, &disposition,
        sizeof(disposition))) return ClearResult::success;
  const auto error = GetLastError();
  if (readonly) {
    basic.FileAttributes = original;
    SetFileInformationByHandle(handle, FileBasicInfo, &basic, sizeof(basic));
  }
  return Failure(error);
}

inline ClearResult RemoveTree(DirectoryGuard& entry) {
  BY_HANDLE_FILE_INFORMATION info{};
  if (!entry.Info(info)) return Failure(GetLastError());
  // This includes directory junctions and file symlinks: dispose the opened
  // link itself, without enumeration or any attempt to resolve its target.
  if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
      !(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) return DeleteOpened(entry.Get());
  // 64 KiB aligned storage; enumeration and recursion use held handles only.
  std::vector<ULONGLONG> buffer(8192);
  bool restart = true;
  for (;;) {
    if (!GetFileInformationByHandleEx(entry.Get(), restart ? FileIdBothDirectoryRestartInfo :
          FileIdBothDirectoryInfo, buffer.data(), static_cast<DWORD>(buffer.size() * sizeof(ULONGLONG)))) {
      const auto error = GetLastError();
      if (error == ERROR_NO_MORE_FILES) break;
      return Failure(error);
    }
    restart = false;
    size_t offset = 0;
    for (;;) {
      const size_t available = buffer.size() * sizeof(ULONGLONG) - offset;
      if (available < offsetof(FILE_ID_BOTH_DIR_INFO, FileName)) return ClearResult::unsafe_path;
      const auto* child = reinterpret_cast<const FILE_ID_BOTH_DIR_INFO*>(
          reinterpret_cast<const BYTE*>(buffer.data()) + offset);
      if (child->FileNameLength % sizeof(wchar_t) ||
          child->FileNameLength > available - offsetof(FILE_ID_BOTH_DIR_INFO, FileName))
        return ClearResult::unsafe_path;
      const std::wstring name(child->FileName, child->FileNameLength / sizeof(wchar_t));
      if (name != L"." && name != L"..") {
        if (!SingleName(name)) return ClearResult::unsafe_path;
        DirectoryGuard opened(entry.Get(), name);
        if (!opened.Valid()) return Failure(GetLastError());
        BY_HANDLE_FILE_INFORMATION identity{};
        if (!opened.Info(identity)) return Failure(GetLastError());
        const auto id = (static_cast<ULONGLONG>(identity.nFileIndexHigh) << 32) | identity.nFileIndexLow;
        if (id != static_cast<ULONGLONG>(child->FileId.QuadPart) ||
            identity.dwVolumeSerialNumber != info.dwVolumeSerialNumber)
          return ClearResult::unsafe_path;
        const auto result = RemoveTree(opened);
        if (result != ClearResult::success) return result;
      }
      if (!child->NextEntryOffset) break;
      if (child->NextEntryOffset < offsetof(FILE_ID_BOTH_DIR_INFO, FileName) ||
          child->NextEntryOffset >= available) return ClearResult::unsafe_path;
      offset += child->NextEntryOffset;
    }
  }
  return DeleteOpened(entry.Get());
}

// expected_root comes from the final, handle-resolved LocalAppData path in the
// runner. Tests supply a final isolated fixture path. Ancestor links are allowed;
// the root itself must be an ordinary directory at exactly the expected location.
inline ClearResult ClearBrowserData(const std::filesystem::path& directory,
    const std::filesystem::path& expected_root) {
  if (!directory.is_absolute() || !expected_root.is_absolute() ||
      !SingleName(directory.filename().wstring()) ||
      directory.parent_path() == directory.root_path()) return ClearResult::unsafe_path;
  DirectoryGuard root(directory);
  if (!root.Valid()) {
    const auto error = GetLastError();
    return Missing(error) ? ClearResult::success : Failure(error);
  }
  BY_HANDLE_FILE_INFORMATION info{};
  if (!root.Info(info)) return Failure(GetLastError());
  if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
      !(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) return ClearResult::unsafe_path;
  std::filesystem::path final_root;
  if (!FinalPath(root.Get(), final_root)) return Failure(GetLastError());
  if (!SamePath(final_root, expected_root)) return ClearResult::unsafe_path;
  // Pin the final parent as well, so the final absence check is relative to the
  // same directory, even if an ancestor junction is retargeted during deletion.
  DirectoryGuard parent(final_root.parent_path());
  if (!parent.Valid()) return Failure(GetLastError());
  std::filesystem::path final_parent;
  BY_HANDLE_FILE_INFORMATION parent_info{};
  if (!parent.Info(parent_info) || !FinalPath(parent.Get(), final_parent)) return Failure(GetLastError());
  if ((parent_info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
      !SamePath(final_parent, expected_root.parent_path())) return ClearResult::unsafe_path;
  const auto result = RemoveTree(root);
  if (result != ClearResult::success) return result;
  root.Release();
  DirectoryGuard remaining(parent.Get(), final_root.filename().wstring());
  if (remaining.Valid()) return ClearResult::busy;
  const auto error = GetLastError();
  return Missing(error) ? ClearResult::success : Failure(error);
}

// UI-thread-only, one-shot arbitration for exit event, timeout and destruction.
// The registry and deadline make queued callbacks harmless even if Windows
// reuses a cancelled timer ID for a subsequent operation.
class ClearWait {
 public:
  ~ClearWait() { Finish(); }
  ClearWait() = default;
  ClearWait(const ClearWait&) = delete;
  ClearWait& operator=(const ClearWait&) = delete;
  bool Start(std::function<void()> timeout, UINT milliseconds = 15000) {
    if (timer_ || finished_) return false;
    timeout_ = std::move(timeout);
    deadline_ = GetTickCount64() + milliseconds;
    timer_ = SetTimer(nullptr, 0, milliseconds, OnTimer);
    if (!timer_) { timeout_ = {}; return false; }
    Timers().emplace(timer_, this);
    return true;
  }
  bool Finish() {
    if (finished_) return false;
    finished_ = true;
    if (timer_) {
      Timers().erase(timer_);
      KillTimer(nullptr, timer_);
      timer_ = 0;
    }
    timeout_ = {};
    return true;
  }
  bool Finished() const { return finished_; }
  UINT_PTR TimerId() const { return timer_; }
  static void CALLBACK OnTimer(HWND, UINT, UINT_PTR id, DWORD) {
    const auto found = Timers().find(id);
    if (found == Timers().end() || GetTickCount64() < found->second->deadline_) return;
    // The callback may Finish() and release its owner; don't access it afterward.
    const auto callback = found->second->timeout_;
    if (callback) callback();
  }
 private:
  static std::map<UINT_PTR, ClearWait*>& Timers() {
    static std::map<UINT_PTR, ClearWait*> timers;
    return timers;
  }
  UINT_PTR timer_ = 0;
  ULONGLONG deadline_ = 0;
  bool finished_ = false;
  std::function<void()> timeout_;
};
}  // namespace hangar_data
