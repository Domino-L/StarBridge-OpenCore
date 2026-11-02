#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <map>
#include <memory>

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
// Local synchronous caller for the real menu protocol, never a remote channel.
class FixtureMessenger : public flutter::BinaryMessenger {
 public:
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
  Value last_result;
  struct PendingCall {
    std::string outcome = "no_reply";
    Value result;
  };
  std::shared_ptr<PendingCall> CallAsync(const char* method, Value args) {
    auto pending = std::make_shared<PendingCall>();
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    auto encoded = codec.EncodeMethodCall(flutter::MethodCall<Value>(
        method, std::make_unique<Value>(std::move(args))));
    handlers.at("starbridge/menu-primary")(encoded->data(), encoded->size(),
        [pending](const uint8_t* bytes, size_t count) {
          flutter::MethodResultFunctions<Value> result(
              [pending](const Value* value) {
                pending->outcome = "success";
                pending->result = value ? *value : Value();
              },
              [pending](const std::string& code, const std::string&, const Value*) {
                pending->outcome = code;
              },
              [pending]() { pending->outcome = "not_implemented"; });
          if (!bytes || count == 0) pending->outcome = "not_implemented";
          else flutter::StandardMethodCodec::GetInstance()
              .DecodeAndProcessResponseEnvelope(bytes, count, &result);
        });
    return pending;
  }
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply reply) const override {
    if (reply) reply(nullptr, 0);
  }
  void SetMessageHandler(const std::string& name, flutter::BinaryMessageHandler handler) override {
    handlers[name] = std::move(handler);
  }
  std::string Call(const char* method, Value args = Value()) {
    std::string outcome = "no_reply";
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    auto encoded = codec.EncodeMethodCall(flutter::MethodCall<Value>(method, std::make_unique<Value>(args)));
    flutter::MethodResultFunctions<Value> result(
        [this, &outcome](const Value* value) {
          outcome = "success";
          last_result = value ? *value : Value();
        },
        [&outcome](const std::string& code, const std::string&, const Value*) { outcome = code; },
        [&outcome]() { outcome = "not_implemented"; });
    handlers.at("starbridge/menu-primary")(encoded->data(), encoded->size(),
        [&codec, &result, &outcome](const uint8_t* bytes, size_t count) {
          if (!bytes || count == 0) outcome = "not_implemented";
          else codec.DecodeAndProcessResponseEnvelope(bytes, count, &result);
        });
    return outcome;
  }
};
