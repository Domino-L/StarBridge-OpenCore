#pragma once
#include <windows.h>
#include <winternl.h>
#include <cstring>
#include <filesystem>
#include <string>
#include "hangar_browser_data.h"

// Whether the hangar reader remembers the RSI sign-in on this computer. The
// choice lives in one small file beside (not inside) the reader's browser
// folder, so clearing that folder never clears the choice. No file means
// "don't remember", which is the default for new and upgraded installs.
//
// The folder holding the file is pinned and must be an ordinary directory at
// exactly the expected, handle-resolved location; the file is then opened
// relative to that held handle, never through a path. A link, a folder or a
// file with more than one name in its place is refused and left alone.
namespace hangar_choice {
inline constexpr char kRemember[] = "remember";
inline constexpr DWORD kRememberSize = sizeof(kRemember) - 1;

// One-component open relative to a held directory; the final entry itself is
// opened as a reparse point, never followed.
inline HANDLE OpenEntry(HANDLE folder, const std::wstring& name, ACCESS_MASK access,
    ULONG disposition, ULONG share = 0) {
  if (!hangar_data::SingleName(name)) { SetLastError(ERROR_INVALID_NAME); return INVALID_HANDLE_VALUE; }
  const auto module = GetModuleHandleW(L"ntdll.dll");
  const auto create = reinterpret_cast<decltype(&NtCreateFile)>(GetProcAddress(module, "NtCreateFile"));
  using Translate = ULONG (WINAPI*)(NTSTATUS);
  const auto translate = reinterpret_cast<Translate>(GetProcAddress(module, "RtlNtStatusToDosError"));
  if (!create || !translate) { SetLastError(ERROR_NOT_SUPPORTED); return INVALID_HANDLE_VALUE; }
  UNICODE_STRING text{};
  text.Buffer = const_cast<PWSTR>(name.data());
  text.Length = text.MaximumLength = static_cast<USHORT>(name.size() * sizeof(wchar_t));
  OBJECT_ATTRIBUTES attributes{};
  attributes.Length = sizeof(attributes);
  attributes.RootDirectory = folder;
  attributes.ObjectName = &text;
  IO_STATUS_BLOCK status{};
  HANDLE opened = INVALID_HANDLE_VALUE;
  // FILE_NON_DIRECTORY_FILE, FILE_OPEN_REPARSE_POINT, FILE_SYNCHRONOUS_IO_NONALERT.
  const auto result = create(&opened, access | SYNCHRONIZE | FILE_READ_ATTRIBUTES, &attributes,
      &status, nullptr, FILE_ATTRIBUTE_NORMAL, share, disposition, 0x00000040 | 0x00200000 | 0x00000020,
      nullptr, 0);
  if (result < 0) { SetLastError(translate(result)); return INVALID_HANDLE_VALUE; }
  return opened;
}

// refused: confirmed not acceptable. error: could not be checked right now.
enum class Check { ok, refused, error };

// The file must be a plain file with this single name.
inline Check FileCheck(HANDLE file) {
  BY_HANDLE_FILE_INFORMATION info{};
  if (!GetFileInformationByHandle(file, &info)) return Check::error;
  return (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) ||
      info.nNumberOfLinks != 1 ? Check::refused : Check::ok;
}
inline bool PlainSingleFile(HANDLE file) { return FileCheck(file) == Check::ok; }

// The held folder must be an ordinary directory exactly where expected.
inline Check FolderCheck(HANDLE folder, const std::filesystem::path& expected) {
  BY_HANDLE_FILE_INFORMATION info{};
  if (!GetFileInformationByHandle(folder, &info)) return Check::error;
  if ((info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
      !(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) return Check::refused;
  std::filesystem::path final_path;
  if (!hangar_data::FinalPath(folder, final_path)) return Check::error;
  return hangar_data::SamePath(final_path, expected) ? Check::ok : Check::refused;
}
inline bool ExpectedFolder(HANDLE folder, const std::filesystem::path& expected) {
  return FolderCheck(folder, expected) == Check::ok;
}

inline bool Missing(DWORD error) {
  return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
}

// unreadable: the choice exists but could not be read right now (for example
// another program holds it). Callers must not treat that as "don't remember".
enum class Choice { forget, remember, unreadable };

// expected_folder is the handle-resolved final path of the folder holding the
// file. Missing, refused (a link, a folder elsewhere, a file with another
// name) or other content reads as "don't remember".
inline Choice ReadChoice(const std::filesystem::path& file, const std::filesystem::path& expected_folder) {
  // Where the choice should be could not be worked out: never "don't remember".
  if (file.empty() || expected_folder.empty()) return Choice::unreadable;
  // Reading shares the folder and the file freely, so another program holding
  // either open never turns a remembered choice into "don't remember".
  const auto folder = CreateFileW(file.parent_path().c_str(), FILE_LIST_DIRECTORY |
      FILE_READ_ATTRIBUTES | SYNCHRONIZE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      nullptr, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (folder == INVALID_HANDLE_VALUE) return Missing(GetLastError()) ? Choice::forget : Choice::unreadable;
  const auto where = FolderCheck(folder, expected_folder);
  if (where != Check::ok) {
    CloseHandle(folder);
    return where == Check::refused ? Choice::forget : Choice::unreadable;
  }
  const auto handle = OpenEntry(folder, file.filename().wstring(), FILE_READ_DATA, 1 /* FILE_OPEN */,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE);
  const auto error = GetLastError();
  CloseHandle(folder);
  if (handle == INVALID_HANDLE_VALUE) return Missing(error) ? Choice::forget : Choice::unreadable;
  char text[16]{};
  DWORD read = 0;
  auto result = Choice::forget;
  const auto kind = FileCheck(handle);
  if (kind == Check::error) result = Choice::unreadable;
  else if (kind == Check::ok) {
    if (!ReadFile(handle, text, sizeof(text), &read, nullptr)) result = Choice::unreadable;
    else if (read == kRememberSize && std::memcmp(text, kRemember, kRememberSize) == 0) result = Choice::remember;
  }
  CloseHandle(handle);
  return result;
}

inline bool ReadRemember(const std::filesystem::path& file, const std::filesystem::path& expected_folder) {
  return ReadChoice(file, expected_folder) == Choice::remember;
}

// Remembering writes the file; not remembering removes it.
inline bool WriteRemember(const std::filesystem::path& file, const std::filesystem::path& expected_folder,
    bool remember) {
  if (remember) {
    std::error_code error;
    std::filesystem::create_directories(file.parent_path(), error);
    if (error) return false;
  }
  hangar_data::DirectoryGuard folder(file.parent_path());
  if (!folder.Valid()) {
    const auto code = GetLastError();
    return !remember && (code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND);
  }
  // Writing pins the folder against rename until the file is closed.
  if (!ExpectedFolder(folder.Get(), expected_folder)) return false;
  const auto handle = OpenEntry(folder.Get(), file.filename().wstring(),
      remember ? (FILE_WRITE_DATA | FILE_WRITE_ATTRIBUTES) : DELETE,
      remember ? 3 /* FILE_OPEN_IF */ : 1 /* FILE_OPEN */);
  if (handle == INVALID_HANDLE_VALUE) {
    const auto code = GetLastError();
    return !remember && (code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND);
  }
  bool ok = PlainSingleFile(handle);
  if (ok && remember) {
    DWORD written = 0;
    ok = SetFilePointer(handle, 0, nullptr, FILE_BEGIN) != INVALID_SET_FILE_POINTER &&
        WriteFile(handle, kRemember, kRememberSize, &written, nullptr) &&
        written == kRememberSize && SetEndOfFile(handle);
  } else if (ok) {
    FILE_DISPOSITION_INFO disposition{TRUE};
    ok = SetFileInformationByHandle(handle, FileDispositionInfo, &disposition,
        sizeof(disposition)) != FALSE;
  }
  CloseHandle(handle);
  return ok;
}
}  // namespace hangar_choice
