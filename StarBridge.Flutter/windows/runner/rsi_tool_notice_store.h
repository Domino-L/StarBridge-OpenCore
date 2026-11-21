#ifndef RUNNER_RSI_TOOL_NOTICE_STORE_H_
#define RUNNER_RSI_TOOL_NOTICE_STORE_H_

#include <windows.h>
#include <shlobj.h>
#include <filesystem>
#include <string>
#include <vector>

// Fixed, device-local teaching marker. Missing or invalid markers mean unread;
// any failure only shows the notice again next launch. No renderer paths.
// The marker is a "seen once" hint, not consent: it is not flushed, so a
// click stays a few small file operations on the platform thread.
namespace rsi_tool_notice {
inline constexpr char kKey[] = "rsiToolNotice.2026-11-03";

inline bool FinalPath(HANDLE handle, std::filesystem::path& path) {
  const DWORD length = GetFinalPathNameByHandleW(handle, nullptr, 0, FILE_NAME_NORMALIZED);
  if (!length) return false;
  std::vector<wchar_t> text(static_cast<size_t>(length) + 1);
  const DWORD written = GetFinalPathNameByHandleW(handle, text.data(),
      static_cast<DWORD>(text.size()), FILE_NAME_NORMALIZED);
  if (!written || written >= text.size()) return false;
  std::wstring value(text.data(), written);
  if (value.rfind(L"\\\\?\\UNC\\", 0) == 0) value = L"\\\\" + value.substr(8);
  else if (value.rfind(L"\\\\?\\", 0) == 0) value.erase(0, 4);
  path = value;
  return true;
}

// The spelled folder and the folder it must really be. LocalAppData itself
// may be redirected (AppData moved to another drive); StarBridge\Notices may not.
struct NoticeFolder {
  std::filesystem::path spelled, expected;
};

inline NoticeFolder NoticesFolder() {
  PWSTR local = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) return {};
  const std::filesystem::path base(local);
  CoTaskMemFree(local);
  const auto handle = CreateFileW(base.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return {};
  std::filesystem::path final_base;
  const bool resolved = FinalPath(handle, final_base);
  CloseHandle(handle);
  if (!resolved) return {};
  return {base / L"StarBridge" / L"Notices", final_base / L"StarBridge" / L"Notices"};
}

// Holds the folder open without delete sharing, so it cannot be renamed or
// swapped for a link until the marker work is done. The folder must not be a
// link and must resolve exactly (case-sensitive) to the expected location.
class PinnedFolder {
 public:
  explicit PinnedFolder(const NoticeFolder& folder) {
    if (folder.spelled.empty()) return;
    const auto handle = CreateFileW(folder.spelled.c_str(), FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return;
    BY_HANDLE_FILE_INFORMATION info{};
    std::filesystem::path final_path;
    const auto expected = folder.expected.wstring();
    if (GetFileInformationByHandle(handle, &info) &&
        !(info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
        (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) &&
        FinalPath(handle, final_path) &&
        CompareStringOrdinal(final_path.c_str(), -1, expected.c_str(), -1, FALSE) == CSTR_EQUAL) {
      handle_ = handle;
      path_ = final_path;
      return;
    }
    CloseHandle(handle);
  }
  ~PinnedFolder() { if (Valid()) CloseHandle(handle_); }
  PinnedFolder(const PinnedFolder&) = delete;
  PinnedFolder& operator=(const PinnedFolder&) = delete;
  bool Valid() const { return handle_ != INVALID_HANDLE_VALUE; }
  // Children are addressed through the verified final path while the folder,
  // and therefore every ancestor rename, stays blocked by the held handle.
  std::filesystem::path Child(const wchar_t* name) const { return path_ / name; }

 private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
  std::filesystem::path path_;
};

inline bool Read(const NoticeFolder& folder) {
  const PinnedFolder pinned(folder);
  if (!pinned.Valid()) return false;
  const auto file = CreateFileW(pinned.Child(L"rsiToolNotice.2026-11-03.seen").c_str(),
      GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  BY_HANDLE_FILE_INFORMATION info{};
  char bytes[sizeof(kKey)] = {};
  DWORD count = 0;
  const bool ok = GetFileInformationByHandle(file, &info) &&
      !(info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
      ReadFile(file, bytes, sizeof(bytes), &count, nullptr) &&
      count == sizeof(kKey) - 1 && std::string(bytes, count) == kKey;
  CloseHandle(file);
  return ok;
}

inline bool Write(const NoticeFolder& folder) {
  if (folder.spelled.empty()) return false;
  // Never create through an existing StarBridge or Notices link.
  for (const auto& entry : {folder.spelled.parent_path(), folder.spelled}) {
    const auto flags = GetFileAttributesW(entry.c_str());
    if (flags == INVALID_FILE_ATTRIBUTES) {
      if (!CreateDirectoryW(entry.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
    } else if (flags & FILE_ATTRIBUTE_REPARSE_POINT) {
      return false;
    }
  }
  const PinnedFolder pinned(folder);
  if (!pinned.Valid()) return false;
  const auto marker = pinned.Child(L"rsiToolNotice.2026-11-03.seen");
  const auto temporary = pinned.Child(L"rsiToolNotice.2026-11-03.seen.tmp");
  DeleteFileW(temporary.c_str());  // A stale temporary file or link; never followed.
  const auto file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
      CREATE_NEW, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD count = 0;
  const bool ok = WriteFile(file, kKey, sizeof(kKey) - 1, &count, nullptr) &&
      count == sizeof(kKey) - 1;
  CloseHandle(file);
  // Replacing a marker that is itself a link replaces the link, not its target.
  const bool committed = ok && MoveFileExW(temporary.c_str(), marker.c_str(), MOVEFILE_REPLACE_EXISTING);
  if (!committed) DeleteFileW(temporary.c_str());
  return committed;
}
}  // namespace rsi_tool_notice

#endif  // RUNNER_RSI_TOOL_NOTICE_STORE_H_
