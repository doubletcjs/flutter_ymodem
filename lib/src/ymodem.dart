import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crclib/catalog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class FlutterYmodemUtil {
  Duration _timeOutDuration = const Duration(seconds: 10);
  Duration _upgradeTimeOutDuration = const Duration(seconds: 10);
  Timer? _timer;
  Timer? _upgradeTimer;

  Rx<Uint8List>? _onReceiveData = Uint8List.fromList([]).obs;
  void Function(Uint8List data)? _onSendData;
  void Function(bool successful, String msg)? _onFeedback;
  void Function(double progress)? _onProgress;
  void Function(String logger)? _onLogger;

  final int ack = 0x06;
  final int nak = 0x15;
  final int c = 0x43;
  final int ca = 0x18;
  final int eot = 0x04;
  final int soh = 0x01;
  final int stx = 0x02;
  final int sohBuf = 128;
  final int stxBuf = 1024;

  int _sendFrameNumber = -1;
  int _fileReadPointer = -1;
  Uint8List? _fileReadBuff;
  Uint8List? _repeatBuff;
  String _fileName = "";
  bool _sendNull = false;
  int _transferSize = 1024;
  int _maxRepeat = 5;
  int _repeatCount = 0;
  int _numberOfC = 0;
  bool _sendingUpgrade = false;

  String _intToHex(int num, {bool upperCase = true}) {
    String cmd = num < 10 ? "0${num.toRadixString(16)}" : num.toRadixString(16);
    if (cmd.length == 1) {
      cmd = "0$cmd";
    }

    return "0x${upperCase ? cmd.toUpperCase() : cmd}";
  }

  List<String> _toRadixList(Uint8List input) => input.map((e) => "0x${(e > 9 ? e.toRadixString(16) : '0${e.toRadixString(16)}').toUpperCase()}").toList();

  /// execute logger
  void _logger(String msg) {
    String log = "ymodem ${DateTime.now()} >>>> $msg";
    debugPrint(log);
    if (_onLogger != null) {
      _onLogger!(log);
    }
  }

  /// stop running
  _stopAction() {
    if (_timer != null) {
      _timer?.cancel();
      _timer = null;
    }

    _onReceiveData = null;
    _repeatCount = 0;
    _numberOfC = 0;
    _sendNull = false;
  }

  /// failure feedback eixt
  _failureAction(dynamic error) {
    if (_onFeedback != null) {
      _logger("on failure error:$error");
      _onFeedback!(false, "$error");
    }

    _stopAction();
  }

  /// start time out
  _startTimer({bool headbeat = false}) {
    if (_timer != null) {
      _timer?.cancel();
      _timer = null;
    }

    _timer = Timer.periodic(_timeOutDuration, (timer) {
      if (headbeat) {
        if (_sendNull) {
          if (_onFeedback != null) {
            _onFeedback!(true, "");
          }

          _stopAction();
          _logger("headbeat time out, force compele");
        }
      } else {
        _failureAction("time out");
      }
    });
  }

  /// past data for serial port to send
  _writeData(Uint8List data) {
    if (_onSendData != null) {
      _onSendData!(data);
      _startTimer();
    } else {
      if (_timer != null) {
        _timer?.cancel();
        _timer = null;
      }

      _failureAction("serial port not available");
    }
  }

  /// ymodem protocol event
  _handleEvent(Uint8List event, List<String> skipHexEvents) {
    if (event.isNotEmpty && _sendingUpgrade == false) {
      List<String> hexEvents = [];
      for (var bytes in event) {
        hexEvents.add(_intToHex(bytes));
      }

      if (hexEvents.join(" ").startsWith(skipHexEvents.join(" ")) == false) {
        if (_timer != null) {
          _timer?.cancel();
          _timer = null;
        }

        debugPrint("ymodem ${DateTime.now()} >>>> receive ${_toRadixList(event)}");
        var byte = event.first;
        String hex = byte == 0x06
            ? "ACK"
            : byte == 0x15
                ? "NAK"
                : byte == 0x43
                    ? "C"
                    : byte == 0x18
                        ? "CA"
                        : byte == 0x04
                            ? "EOT"
                            : "";

        if (hex.isNotEmpty) {
          debugPrint("ymodem ${DateTime.now()} >>>> receive $hex");
          if (_upgradeTimer != null) {
            _upgradeTimer?.cancel();
            _upgradeTimer = null;
          }
        }

        if (byte == c) {
          if (_fileReadBuff == null) {
            // send null package
            _sendNullPackage();
            _sendNull = true;
            _repeatCount = 0;
          } else if (_sendFrameNumber < 1) {
            if (_numberOfC == 1) {
              _sendFrameNumber = 0;
              // send info package
              _sendInfoPackage();
              _sendFrameNumber = 1;
              _numberOfC = 0;
              _repeatCount = 0;
            } else {
              _numberOfC += 1;
            }
          } else {
            // repeat
            _repeat();
          }
        } else if (byte == ack) {
          if (_fileReadBuff != null) {
            if (_fileReadPointer < _fileReadBuff!.length) {
              if (_sendFrameNumber >= 1) {
                // send data package
                _sendDataPackage();
                // progress
                int percent = (_fileReadPointer * 100) ~/ _fileReadBuff!.length;
                if (_onProgress != null) {
                  _onProgress!(((_fileReadPointer * 100) / _fileReadBuff!.length) / 100);
                }
                _logger("send psackage data ${_fileReadBuff?.length} $_sendFrameNumber $percent%");
                _sendFrameNumber++;
                _repeatCount = 0;
              }
            } else {
              // send eot
              _sendEOT();
              // reset send buff
              _resetSendBuff();
              _repeatCount = 0;
            }
          } else {
            // compele
            if (_sendNull) {
              _logger("send null package compele waitting for headbeat");
              _startTimer(headbeat: true);
            }
          }
        } else if (byte == nak) {
          if (_fileReadBuff != null) {
            _repeat();
          } else {
            _sendEOT();
          }
        } else {
          _startTimer();
        }
      } else {
        if (_sendNull) {
          if (_onFeedback != null) {
            _onFeedback!(true, "");
          }

          _stopAction();
          _logger("send data compele");
        }
      }
    }
  }

  /// run with file data
  run({
    required Uint8List fileData,
    required Uint8List cmd,
    required Function(bool successful, String msg)? feedback,
    required void Function(double progress)? progress,
    required void Function(Uint8List data)? onSendData,
    void Function(String logger)? onLogger,
    Rx<Uint8List>? onReceiveData,
    String fileName = "ctl.bin",
    Uint8List? skipHeader,
    Duration timeOut = const Duration(seconds: 10),
    Duration upgradeTimeOut = const Duration(seconds: 5),
    int transferSize = 1024,
    int maxRepeat = 5,
  }) {
    // config
    _onFeedback = feedback;
    _onLogger = onLogger;
    if (fileData.isEmpty) {
      _failureAction("empty file data");
      return;
    }

    if (cmd.isEmpty) {
      _failureAction("empty upgrade data");
      return;
    }

    _resetSendBuff();
    if (onReceiveData != null) {
      _maxRepeat = maxRepeat;
      _timeOutDuration = timeOut;
      _upgradeTimeOutDuration = upgradeTimeOut;
      _transferSize = transferSize;
      _onSendData = onSendData;
      skipHeader ??= Uint8List.fromList([0xA5, 0x5A]);
      _onProgress = progress;
      List<String> skipHexEvents = [];
      for (var bytes in skipHeader) {
        skipHexEvents.add(_intToHex(bytes));
      }

      _prepareSendBuff(fileName, fileData);
      _onReceiveData = onReceiveData;

      void sendUpgrade() {
        if (_sendFrameNumber == -1 && _fileReadBuff != null && _fileReadBuff!.isNotEmpty) {
          _writeData(cmd);
          _sendingUpgrade = true;
          _logger("send upgrade");
          Future.delayed(const Duration(milliseconds: 500), () {
            _sendingUpgrade = false;
          });
        }

        if (_upgradeTimer != null) {
          _upgradeTimer?.cancel();
          _upgradeTimer = null;
        }
      }

      if (_upgradeTimeOutDuration.inSeconds == 0) {
        sendUpgrade();
      } else {
        _upgradeTimer = Timer.periodic(_upgradeTimeOutDuration, (timer) {
          sendUpgrade();
        });
      }

      ever(_onReceiveData!, (event) {
        if (_onReceiveData != null) {
          _handleEvent(event, skipHexEvents);
        }
      });
    } else {
      _failureAction("serial port subscription not available");
    }
  }

  /// run with file path
  runPath({
    required String filePath,
    required Uint8List cmd,
    required Function(bool successful, String msg)? feedback,
    required void Function(double progress)? progress,
    required void Function(Uint8List data)? onSendData,
    void Function(String logger)? onLogger,
    Rx<Uint8List>? onReceiveData,
    String fileName = "ctl.bin",
    Uint8List? skipHeader,
    Duration timeOut = const Duration(seconds: 10),
    Duration upgradeTimeOut = const Duration(seconds: 5),
    int transferSize = 1024,
    int maxRepeat = 5,
  }) {
    File(filePath).readAsBytes().then((value) {
      run(
        fileData: value,
        cmd: cmd,
        feedback: feedback,
        progress: progress,
        onSendData: onSendData,
        onLogger: onLogger,
        onReceiveData: onReceiveData,
        fileName: fileName,
        skipHeader: skipHeader,
        timeOut: timeOut,
        upgradeTimeOut: upgradeTimeOut,
        transferSize: transferSize,
        maxRepeat: maxRepeat,
      );
    }).catchError((error) {
      _onFeedback = feedback;
      _failureAction("$error");
    });
  }

  /// reset send buff
  _resetSendBuff() {
    _fileReadBuff = null;
    _sendFrameNumber = -1;
    _fileReadPointer = -1;
    _repeatBuff = null;
    _numberOfC = 0;

    debugPrint("reset send buff");
  }

  /// prepare file split file data
  _prepareSendBuff(String fn, Uint8List fileBuff) {
    _fileName = fn;
    _fileReadBuff = Uint8List(fileBuff.length);

    for (var i = 0; i < fileBuff.length; i++) {
      _fileReadBuff![i] = fileBuff[i];
    }
    _logger("fileBuff length ${_fileReadBuff!.length}");

    _sendFrameNumber = -1;
    _fileReadPointer = 0;
    _repeatBuff = null;
    _numberOfC = 0;
  }

  /// ymodem protocol eot
  _sendEOT() {
    _logger("sendEOT");
    _writeData(Uint8List.fromList([eot]));
  }

  /// repeat send file info package or file data package
  _repeat() {
    if (_repeatBuff != null) {
      if (_maxRepeat == _repeatCount) {
        _repeatCount = 0;
        _failureAction("max repeat");
      } else {
        _repeatCount += 1;
        _logger("repeat $_repeatCount");
        _writeData(_repeatBuff!);
      }
    }
  }

  /// file info package
  _sendInfoPackage() {
    Uint8List infoBuff = Uint8List(3 + 128 + 2);
    int iBuff = 0;
    infoBuff[iBuff++] = soh;
    infoBuff[iBuff++] = _sendFrameNumber;
    infoBuff[iBuff++] = ~(_sendFrameNumber);

    Uint8List nameBytes = Uint8List.fromList(_fileName.codeUnits);
    for (var i = 0; i < nameBytes.length; i++) {
      infoBuff[iBuff++] = nameBytes[i];
    }

    infoBuff[iBuff++] = 0x00;
    Uint8List sizeBytes = Uint8List.fromList("${_fileReadBuff?.length}".codeUnits);
    for (var i = 0; i < sizeBytes.length; i++) {
      infoBuff[iBuff++] = sizeBytes[i];
    }

    for (var i = iBuff; i < infoBuff.length; i++) {
      infoBuff[i] = 0x00;
    }

    int crc16 = _crc16CcittXmodem(infoBuff, 3, 2);
    infoBuff[infoBuff.length - 2] = crc16 >> 8;
    infoBuff[infoBuff.length - 1] = crc16 & 0xFF;
    _logger("send info package ${infoBuff.length}");

    _repeatBuff = Uint8List(infoBuff.length);
    for (var i = 0; i < _repeatBuff!.length; i++) {
      _repeatBuff![i] = infoBuff[i];
    }

    _writeData(infoBuff);
  }

  /// send null package
  _sendNullPackage() {
    Uint8List nullBuff = Uint8List(3 + 128 + 2);
    nullBuff[0] = soh;
    nullBuff[1] = 0x00;
    nullBuff[2] = 0xFF;
    for (var i = 3; i < nullBuff.length; i++) {
      nullBuff[i] = 0x00;
    }

    int crc16 = _crc16CcittXmodem(nullBuff, 3, 2);
    nullBuff[nullBuff.length - 2] = crc16 >> 8;
    nullBuff[nullBuff.length - 1] = crc16 & 0xFF;

    _logger("send null package ${nullBuff.length}");
    _writeData(nullBuff);
  }

  /// send file data buff
  _sendDataPackage() {
    Uint8List dataBuff = Uint8List(0);
    int remainder = _fileReadBuff!.length - _fileReadPointer;
    int iBuff = 0;
    int readSize = 0;

    if (_transferSize == sohBuf) {
      readSize = sohBuf;
      dataBuff = Uint8List(3 + readSize + 2);
      dataBuff[iBuff++] = soh;
    } else if (_transferSize == stxBuf) {
      if (remainder > sohBuf) {
        readSize = stxBuf;
        dataBuff = Uint8List(3 + readSize + 2);
        dataBuff[iBuff++] = stx;
      } else {
        readSize = sohBuf;
        dataBuff = Uint8List(3 + readSize + 2);
        dataBuff[iBuff++] = soh;
      }
    }

    dataBuff[iBuff++] = _sendFrameNumber;
    dataBuff[iBuff++] = ~(_sendFrameNumber);
    for (var i = 0; i < readSize; i++) {
      if (_fileReadPointer < _fileReadBuff!.length) {
        dataBuff[iBuff++] = _fileReadBuff![_fileReadPointer++];
      } else {
        dataBuff[iBuff++] = 0x00;
      }
    }

    int crc16 = _crc16CcittXmodem(dataBuff, 3, 2);
    dataBuff[dataBuff.length - 2] = crc16 >> 8;
    dataBuff[dataBuff.length - 1] = crc16 & 0xFF;

    _repeatBuff = Uint8List(dataBuff.length);
    for (var i = 0; i < _repeatBuff!.length; i++) {
      _repeatBuff![i] = dataBuff[i];
    }

    _writeData(dataBuff);
  }

  /// verify code Crc16Xmodem
  int _crc16CcittXmodem(Uint8List bytes, int offset, int end) {
    Uint8List sublist = bytes.sublist(offset, bytes.length - end);
    return int.parse(Crc16Xmodem().convert(sublist).toString());
  }
}
