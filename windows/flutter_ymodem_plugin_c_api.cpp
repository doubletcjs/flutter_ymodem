#include "include/flutter_ymodem/flutter_ymodem_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_ymodem_plugin.h"

void FlutterYmodemPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_ymodem::FlutterYmodemPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
