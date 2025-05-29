import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_ymodem/flutter_ymodem.dart';
import 'package:get/get.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    FlutterYmodem().run(
      fileData: Uint8List.fromList([]),
      cmd: Uint8List.fromList([]),
      feedback: (successful, msg) {},
      progress: (progress) {},
      onSendData: (data) {
        // send data use serial port
      },
      onReceiveData: Uint8List.fromList([]).obs, // past data from serial port
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: const Center(),
      ),
    );
  }
}
