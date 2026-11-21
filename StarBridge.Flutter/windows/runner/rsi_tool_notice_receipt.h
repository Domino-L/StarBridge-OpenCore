#ifndef RUNNER_RSI_TOOL_NOTICE_RECEIPT_H_
#define RUNNER_RSI_TOOL_NOTICE_RECEIPT_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <string>

#include "rsi_tool_notice_async.h"
#include "rsi_tool_notice_store.h"

// Primary engine only. The channel always uses the store's fixed path, never
// a path from a method argument. File work runs off the platform thread.
class RsiToolNoticeReceipt {
 public:
  explicit RsiToolNoticeReceipt(flutter::BinaryMessenger* messenger)
      : channel_(messenger, "starbridge/rsi-tool-notice",
                 &flutter::StandardMethodCodec::GetInstance()) {
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      const auto* key = call.arguments()
          ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (!key || *key != rsi_tool_notice::kKey) { result->Error("invalid_notice"); return; }
      const bool read = call.method_name() == "read";
      if (!read && call.method_name() != "markSeen") { result->NotImplemented(); return; }
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> reply(std::move(result));
      work_.Submit(
          [read] {
            const auto folder = rsi_tool_notice::NoticesFolder();
            return read ? rsi_tool_notice::Read(folder) : rsi_tool_notice::Write(folder);
          },
          [read, reply](bool outcome) {
            if (read) reply->Success(flutter::EncodableValue(outcome));
            else if (outcome) reply->Success();
            else reply->Error("notice_write_failed");
          });
    });
  }
  ~RsiToolNoticeReceipt() { channel_.SetMethodCallHandler(nullptr); }

 private:
  flutter::MethodChannel<flutter::EncodableValue> channel_;
  rsi_tool_notice::AsyncWork work_;
};

#endif  // RUNNER_RSI_TOOL_NOTICE_RECEIPT_H_
