#ifndef FLUTTER_PLUGIN_ICB_YMODEM_UTIL_PLUGIN_H_
#define FLUTTER_PLUGIN_ICB_YMODEM_UTIL_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_ymodem {

class FlutterYmodemPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterYmodemPlugin();

  virtual ~FlutterYmodemPlugin();

  // Disallow copy and assign.
  FlutterYmodemPlugin(const FlutterYmodemPlugin&) = delete;
  FlutterYmodemPlugin& operator=(const FlutterYmodemPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_ymodem

#endif  // FLUTTER_PLUGIN_ICB_YMODEM_UTIL_PLUGIN_H_
