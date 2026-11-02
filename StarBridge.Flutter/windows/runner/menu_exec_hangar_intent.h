#ifndef RUNNER_MENU_EXEC_HANGAR_INTENT_H_
#define RUNNER_MENU_EXEC_HANGAR_INTENT_H_
#include <flutter/encodable_value.h>
#include <cstdint>
#include <string>

// Read-only summary and one fixed tool destination. No renderer-selected RPC,
// payload, account, process, path, or monitoring command is accepted.
inline bool ValidMenuExecHangarIntent(const flutter::EncodableMap& args,
    uint64_t opening, bool allowed, bool live, bool wanted, bool modal) {
  if (!allowed || !live || !wanted || modal || args.size() != 1) return false;
  const auto item = args.find(flutter::EncodableValue("opening"));
  if (item == args.end() || opening == 0) return false;
  if (const auto* wide = std::get_if<int64_t>(&item->second))
    return *wide > 0 && static_cast<uint64_t>(*wide) == opening;
  if (const auto* narrow = std::get_if<int32_t>(&item->second))
    return *narrow > 0 && static_cast<uint64_t>(*narrow) == opening;
  return false;
}
// Six fixed display anchors only. No game HWND, calibration or arbitrary Host payload.
inline bool ValidMenuExecHangarGameIntent(const flutter::EncodableMap& args,
    uint64_t opening, bool allowed, bool live, bool wanted, bool modal) {
  using Value = flutter::EncodableValue;
  const auto action_field = args.find(Value("action"));
  const auto* action = action_field == args.end() ? nullptr : std::get_if<std::string>(&action_field->second);
  if (!action || (*action != "read" && *action != "pin" && *action != "unpin")) return false;
  const bool pin = *action == "pin";
  if (args.size() != (pin ? 3u : 2u)) return false;
  flutter::EncodableMap base;
  const auto item = args.find(Value("opening"));
  if (item == args.end()) return false;
  base.emplace(item->first, item->second);
  if (!ValidMenuExecHangarIntent(base, opening, allowed, live, wanted, modal)) return false;
  if (!pin) return true;
  const auto field = args.find(Value("position"));
  const auto* position = field == args.end() ? nullptr : std::get_if<std::string>(&field->second);
  if (!position) return false;
  for (const char* candidate : {"topLeft", "topCenter", "topRight", "bottomRight", "bottomCenter", "bottomLeft"})
    if (*position == candidate) return true;
  return false;
}
#endif
