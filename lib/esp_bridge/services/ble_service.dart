import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ganci/services/esp_ap_transfer_service.dart' show EspFsEntry;

const String _serviceUuid = '12345678-1234-1234-1234-1234567890ab';
const String _mediaServiceUuid = '12345678-1234-1234-1234-1234567890f0';

const String _titleUuid = '12345678-1234-1234-1234-1234567890a1';
const String _artistUuid = '12345678-1234-1234-1234-1234567890a2';
const String _durationUuid = '12345678-1234-1234-1234-1234567890a3';
const String _positionUuid = '12345678-1234-1234-1234-1234567890a4';
const String _controlUuid = '12345678-1234-1234-1234-1234567890a5';
const String _statusUuid = '12345678-1234-1234-1234-1234567890a6';
const String _lyricPrevUuid = '12345678-1234-1234-1234-1234567890b1';
const String _lyricActiveUuid = '12345678-1234-1234-1234-1234567890b2';
const String _lyricNextUuid = '12345678-1234-1234-1234-1234567890b3';

const String _devNameUuid = '12345678-1234-1234-1234-1234567890c1';
const String _sysInfoUuid = '12345678-1234-1234-1234-1234567890c2';
const String _fileCmdUuid = '12345678-1234-1234-1234-1234567890c3';
const String _mediaStartUuid = '12345678-1234-1234-1234-1234567890f1';
const String _mediaDataUuid = '12345678-1234-1234-1234-1234567890f2';
const String _mediaEndUuid = '12345678-1234-1234-1234-1234567890f3';

const bool _sendPrevLineEachUpdate = false;

enum BleStatus { disconnected, scanning, connecting, connected }

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _titleChar;
  BluetoothCharacteristic? _artistChar;
  BluetoothCharacteristic? _durationChar;
  BluetoothCharacteristic? _positionChar;
  BluetoothCharacteristic? _controlChar;
  BluetoothCharacteristic? _statusChar;

  // Lyrics Characteristics
  BluetoothCharacteristic? _lyricPrevChar;
  BluetoothCharacteristic? _lyricActiveChar;
  BluetoothCharacteristic? _lyricNextChar;

  // New Characteristics
  BluetoothCharacteristic? _devNameChar;
  BluetoothCharacteristic? _sysInfoChar;
  BluetoothCharacteristic? _fileCmdChar;
  BluetoothCharacteristic? _mediaStartChar;
  BluetoothCharacteristic? _mediaDataChar;
  BluetoothCharacteristic? _mediaEndChar;

  bool _cancelUpload = false;

  StreamSubscription? _controlSub;
  StreamSubscription? _fileCmdSub;

  Future<void> _writeQueue = Future.value();
  Future<void> _lyricsWriteQueue = Future.value();
  bool _lyricsWriteBusy = false;
  int _lastSentPosition = -1;
  int _lastSentStatus = -1;
  DateTime _lastPositionSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLyricsSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastLyricPrev = '';
  String _lastLyricActive = '';
  String _lastLyricNext = '';

  final _statusCtrl = StreamController<BleStatus>.broadcast();
  final _controlCtrl = StreamController<int>.broadcast();
  final _fileCmdCtrl = StreamController<String>.broadcast();

  Stream<BleStatus> get statusStream => _statusCtrl.stream;
  Stream<int> get controlStream => _controlCtrl.stream;

  BleStatus _currentStatus = BleStatus.disconnected;
  BleStatus get currentStatus => _currentStatus;

  void _setStatus(BleStatus s) {
    _currentStatus = s;
    _statusCtrl.add(s);
  }

  // ── Scan & Connect ────────────────────────────────────────────────────────
  Future<void> connectToDevice(BluetoothDevice device) async {
    await _connect(device);
  }

  Future<String> getTargetDevName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('target_ble_name') ?? 'Moocchi esp';
  }

  Future<void> saveTargetDevName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('target_ble_name', name);
  }

  Future<bool> isBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  Future<bool> turnOnBluetooth() async {
    try {
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
        final state = await FlutterBluePlus.adapterState
            .firstWhere((s) => s == BluetoothAdapterState.on,
                orElse: () => BluetoothAdapterState.off)
            .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.off);
        return state == BluetoothAdapterState.on;
      }
    } catch (e) {
      debugPrint('Error turning on Bluetooth: $e');
    }
    return false;
  }

  Future<void> scanAndConnect() async {
    if (_currentStatus != BleStatus.disconnected) return;
    _setStatus(BleStatus.scanning);

    final targetDevName = await getTargetDevName();

    try {
      if (Platform.isAndroid) {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();
      }

      if (await FlutterBluePlus.isSupported == false) {
        _setStatus(BleStatus.disconnected);
        return;
      }

      final targetLower = targetDevName.trim().toLowerCase();
      bool isMatch(BluetoothDevice d) {
        final pName = d.platformName.trim().toLowerCase();
        final aName = d.advName.trim().toLowerCase();
        return pName == targetLower || aName == targetLower || pName.contains(targetLower) || aName.contains(targetLower);
      }

      // 1. Cek apakah device sudah terhubung di FlutterBluePlus
      for (final device in FlutterBluePlus.connectedDevices) {
        if (isMatch(device)) {
          await _connect(device);
          return;
        }
      }

      // 2. Cek apakah device sudah terhubung di sistem OS (systemDevices)
      try {
        final sysDevices = await FlutterBluePlus.systemDevices([Guid(_serviceUuid), Guid(_mediaServiceUuid)]);
        for (final device in sysDevices) {
          if (isMatch(device)) {
            await _connect(device);
            return;
          }
        }
      } catch (e) {
        debugPrint('systemDevices check error: $e');
      }

      // 3. Jika belum terhubung, lakukan scan dengan durasi maksimal 8 detik
      final completer = Completer<BluetoothDevice?>();
      
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (isMatch(r.device)) {
            if (!completer.isCompleted) {
              completer.complete(r.device);
            }
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        androidUsesFineLocation: true,
      );

      BluetoothDevice? foundDevice;
      try {
        foundDevice = await completer.future.timeout(
          const Duration(seconds: 9),
          onTimeout: () => null,
        );
      } catch (_) {}

      await sub.cancel();
      await FlutterBluePlus.stopScan();

      if (foundDevice != null) {
        await _connect(foundDevice);
      } else {
        _setStatus(BleStatus.disconnected);
      }
    } catch (e) {
      _setStatus(BleStatus.disconnected);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    _setStatus(BleStatus.connecting);
    _device = device;
    try {
      if (!device.isConnected) {
        await device.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 15),
        );
      }

      // Optimation for connection speed
      if (device.platformName.toLowerCase().contains('android') || true) {
        try {
          await device.requestMtu(512);
          await device.requestConnectionPriority(
            connectionPriorityRequest: ConnectionPriority.high,
          );
        } catch (_) {}
      }

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _clearChars();
          _setStatus(BleStatus.disconnected);
        }
      });
      await _discoverServices(device);
      _setStatus(BleStatus.connected);
    } catch (e) {
      _setStatus(BleStatus.disconnected);
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    final services = await device.discoverServices().timeout(
      const Duration(seconds: 10),
      onTimeout: () => <BluetoothService>[],
    );
    if (kDebugMode) {
      print('BLE: Discovering services for ${device.remoteId}...');
    }
    for (final svc in services) {
      final suuid = svc.uuid.toString().toLowerCase();
      if (suuid == _serviceUuid || suuid == _mediaServiceUuid) {
        if (kDebugMode) {
          print('BLE: Found Target Service: $suuid');
        }
        for (final c in svc.characteristics) {
          final uuid = c.uuid.toString().toLowerCase();
          if (kDebugMode) {
            print('BLE: Found Char: $uuid');
          }
          if (uuid == _titleUuid) _titleChar = c;
          if (uuid == _artistUuid) _artistChar = c;
          if (uuid == _durationUuid) _durationChar = c;
          if (uuid == _positionUuid) _positionChar = c;
          if (uuid == _controlUuid) _controlChar = c;
          if (uuid == _statusUuid) _statusChar = c;

          if (uuid == _lyricPrevUuid) _lyricPrevChar = c;
          if (uuid == _lyricActiveUuid) _lyricActiveChar = c;
          if (uuid == _lyricNextUuid) _lyricNextChar = c;

          if (uuid == _devNameUuid) _devNameChar = c;
          if (uuid == _sysInfoUuid) _sysInfoChar = c;
          if (uuid == _fileCmdUuid) _fileCmdChar = c;
          if (uuid == _mediaStartUuid) _mediaStartChar = c;
          if (uuid == _mediaDataUuid) _mediaDataChar = c;
          if (uuid == _mediaEndUuid) _mediaEndChar = c;
        }
      }
    }

    // Subscribe CONTROL notify
    if (_controlChar != null) {
      await _controlChar!.setNotifyValue(true);
      await _controlSub?.cancel();
      _controlSub = _controlChar!.lastValueStream.listen((data) {
        if (data.isNotEmpty) _controlCtrl.add(data[0]);
      });
    }

    // Subscribe FILE CMD notify
    if (_fileCmdChar != null) {
      await _fileCmdChar!.setNotifyValue(true);
      await _fileCmdSub?.cancel();
      _fileCmdSub = _fileCmdChar!.lastValueStream.listen((data) {
        if (data.isNotEmpty) {
          var str = utf8.decode(data, allowMalformed: true);
          str = str.replaceAll('\x00', '').trim();
          _fileCmdCtrl.add(str);
        }
      });
    }
  }

  void cancelUpload() {
    _cancelUpload = true;
  }

  void _clearChars() {
    _controlSub?.cancel();
    _fileCmdSub?.cancel();
    _controlSub = null;
    _fileCmdSub = null;
    
    _titleChar = _artistChar = _durationChar = _positionChar = _controlChar =
        _statusChar = null;
    _lyricPrevChar = _lyricActiveChar = _lyricNextChar = null;
    _devNameChar = _sysInfoChar = _fileCmdChar = _mediaStartChar = _mediaDataChar =
        _mediaEndChar = null;
    _device = null;
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _clearChars();
    _setStatus(BleStatus.disconnected);
  }

  // ── Write helpers ─────────────────────────────────────────────────────────
  Future<void> _writeString(
    BluetoothCharacteristic? c,
    String val,
    String label,
  ) async {
    if (c == null) {
      if (kDebugMode) {
        print('BLE Error: $label Char is NULL');
      }
      return;
    }
    await _enqueueWrite(() async {
      try {
        final bytes = utf8.encode(val);
        await c.write(bytes, withoutResponse: true);
      } catch (e) {
        if (kDebugMode) {
          print('BLE Error: Failed to send $label: $e');
        }
      }
    });
  }

  Future<void> _writeUint32(
    BluetoothCharacteristic? c,
    int val,
    String label,
  ) async {
    if (c == null) {
      if (kDebugMode) {
        print('BLE Error: $label Char is NULL');
      }
      return;
    }
    await _enqueueWrite(() async {
      try {
        final buf = Uint8List(4)
          ..buffer.asByteData().setUint32(0, val, Endian.little);
        await c.write(buf, withoutResponse: true);
      } catch (e) {
        if (kDebugMode) {
          print('BLE Error: Failed to send $label: $e');
        }
      }
    });
  }

  Future<void> _writeUint8(
    BluetoothCharacteristic? c,
    int val,
    String label,
  ) async {
    if (c == null) {
      if (kDebugMode) {
        print('BLE Error: $label Char is NULL');
      }
      return;
    }
    await _enqueueWrite(() async {
      try {
        await c.write([val], withoutResponse: true);
      } catch (e) {
        if (kDebugMode) {
          print('BLE Error: Failed to send $label: $e');
        }
      }
    });
  }

  // ── Public API ────────────────────────────────────────────────────────────
  Future<void> sendTitle(String title) =>
      _writeString(_titleChar, title, 'Title');
  Future<void> sendArtist(String artist) =>
      _writeString(_artistChar, artist, 'Artist');
  Future<void> sendDuration(int secs) =>
      _writeUint32(_durationChar, secs, 'Duration');
  Future<void> sendPosition(int secs) async {
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastPositionSentAt).inMilliseconds;
    final sinceLyricsMs = now.difference(_lastLyricsSentAt).inMilliseconds;
    if (secs == _lastSentPosition) return;
    // Jangan biarkan posisi tertahan terlalu lama karena antrean lirik.
    if (_lyricsWriteBusy && elapsedMs < 700) return;
    // Prioritaskan jalur lirik: tunda kirim posisi sebentar setelah update lirik.
    if (sinceLyricsMs >= 0 && sinceLyricsMs < 220) return;
    if (elapsedMs < 260 && (secs - _lastSentPosition).abs() <= 1) return;
    _lastSentPosition = secs;
    _lastPositionSentAt = now;
    await _writeUint32(_positionChar, secs, 'Position');
  }

  Future<void> sendStatus(bool playing) async {
    final val = playing ? 1 : 0;
    if (val == _lastSentStatus) return;
    _lastSentStatus = val;
    await _writeUint8(_statusChar, val, 'Status');
  }

  Future<void> sendSongInfo(
    String title,
    String artist,
    int durationSecs,
  ) async {
    await sendTitle(title);
    await Future.delayed(const Duration(milliseconds: 6));
    await sendArtist(artist);
    await Future.delayed(const Duration(milliseconds: 6));
    await sendDuration(durationSecs);
  }

  Future<void> _enqueueWrite(Future<void> Function() op) {
    _writeQueue = _writeQueue
        .then((_) => op())
        .catchError((_) {});
    return _writeQueue;
  }

  // ── Lyrics Sending ─────────────────────────────────────────────────────────
  Future<void> sendLyrics(String prev, String active, String next) async {
    if (_lyricActiveChar == null || _lyricNextChar == null) {
      if (kDebugMode) {
        print('BLE Error: Active/Next Lyric characteristics missing');
      }
      return;
    }
    // Trim strings to max 63 chars (64-byte buffer on ESP).
    String trimLine(String s) => s.length > 63 ? s.substring(0, 63) : s;

    final p = trimLine(prev);
    final a = trimLine(active);
    final n = trimLine(next);

    // Hindari kirim payload lirik identik berulang.
    final samePayload = _sendPrevLineEachUpdate
        ? (p == _lastLyricPrev && a == _lastLyricActive && n == _lastLyricNext)
        : (a == _lastLyricActive && n == _lastLyricNext);
    if (samePayload) {
      return;
    }

    _lastLyricPrev = p;
    _lastLyricActive = a;
    _lastLyricNext = n;

    _lyricsWriteQueue = _lyricsWriteQueue.then((_) async {
      _lyricsWriteBusy = true;
      try {
        if (_sendPrevLineEachUpdate && _lyricPrevChar != null) {
          await _lyricPrevChar!.write(utf8.encode(p), withoutResponse: true);
        } else if (p.isEmpty && a.isEmpty && n.isEmpty && _lyricPrevChar != null) {
          // Tetap clear prev saat reset total agar layar bersih.
          await _lyricPrevChar!.write(utf8.encode(''), withoutResponse: true);
        }
        await _lyricActiveChar!.write(utf8.encode(a), withoutResponse: true);
        await _lyricNextChar!.write(utf8.encode(n), withoutResponse: true);
        _lastLyricsSentAt = DateTime.now();
      } catch (e) {
        if (kDebugMode) {
          print('BLE Error: Failed to send lyrics batch: $e');
        }
      } finally {
        _lyricsWriteBusy = false;
      }
    }).catchError((_) {
      _lyricsWriteBusy = false;
    });

    await _lyricsWriteQueue;
  }

  // ── Device Settings & Telemetry ───────────────────────────────────────────
  Future<bool> changeDeviceName(String newName) async {
    if (_devNameChar == null) {
      if (kDebugMode) print('BLE Error: DevName Char is NULL');
      return false;
    }
    try {
      await _devNameChar!.write(utf8.encode(newName), withoutResponse: false);
      await saveTargetDevName(newName);
      return true;
    } catch (e) {
      if (kDebugMode) print('BLE Error: Failed to change device name: $e');
      return false;
    }
  }

  Future<void> ensureConnectedAndReady() async {
    // If already connected with chars discovered, nothing to do
    if (_currentStatus == BleStatus.connected && _device != null && _device!.isConnected) {
      if (_sysInfoChar == null || _mediaStartChar == null) {
        // Connected but chars missing - try one discover
        try {
          await _discoverServices(_device!);
        } catch (e) {
          if (kDebugMode) print('ensureConnected: discover failed: $e');
        }
      }
      return;
    }
    // Not connected - try scan once
    if (_currentStatus != BleStatus.connected) {
      await scanAndConnect();
    }
  }

  /// Fetch system info from ESP. Retries up to 3 times with delay.
  /// Returns null if truly unavailable.
  Future<Map<String, dynamic>?> fetchSysInfo() async {
    if (_sysInfoChar == null) {
      if (kDebugMode) print('BLE: SysInfo Char is NULL, skipping read');
      return null;
    }
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        if (attempt > 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        final val = await _sysInfoChar!.read().timeout(
          const Duration(seconds: 5),
        );
        if (val.isEmpty) {
          if (kDebugMode) print('BLE: SysInfo read empty (attempt $attempt/3)');
          continue;
        }
        var str = utf8.decode(val, allowMalformed: true);
        
        // ESP32 sometimes sends uninitialized memory junk after the null terminator
        // if using a fixed buffer. We isolate the JSON by finding the last closing brace.
        final lastBrace = str.lastIndexOf('}');
        if (lastBrace != -1) {
          str = str.substring(0, lastBrace + 1);
        }
        
        str = str.replaceAll('\x00', '').trim(); // Clean up any remaining null bytes
        if (kDebugMode) print('BLE SysInfo received: $str');
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (e) {
        if (kDebugMode) print('BLE: SysInfo read attempt $attempt/3 failed: $e');
      }
    }
    if (kDebugMode) print('BLE: SysInfo all 3 attempts failed');
    return null;
  }

  // ── BLE Remote File Management ────────────────────────────────────────────
  Future<List<EspFsEntry>> listFiles() async {
    if (_fileCmdChar == null) return [];
    final completer = Completer<List<EspFsEntry>>();
    final list = <EspFsEntry>[];
    
    final sub = _fileCmdCtrl.stream.listen((str) {
      if (str == '[END]') {
        if (!completer.isCompleted) completer.complete(list);
      } else {
        final parts = str.split('|');
        if (parts.length >= 2) {
          final size = int.tryParse(parts[1]) ?? 0;
          final isDir = parts.length >= 3 ? parts[2] == '1' : false;
          list.add(EspFsEntry(name: parts[0], isDir: isDir, size: size));
        }
      }
    });

    try {
      await _fileCmdChar!.write(utf8.encode('LIST'));
      final result = await completer.future.timeout(const Duration(seconds: 15));
      await sub.cancel();
      return result;
    } catch (e) {
      await sub.cancel();
      return list;
    }
  }

  Future<bool> deleteFile(String filename) async {
    if (_fileCmdChar == null) return false;
    final completer = Completer<bool>();
    
    final sub = _fileCmdCtrl.stream.listen((str) {
      if (str == '[OK]') {
        if (!completer.isCompleted) completer.complete(true);
      } else if (str == '[ERR]') {
        if (!completer.isCompleted) completer.complete(false);
      }
    });

    try {
      await _fileCmdChar!.write(utf8.encode('DEL|$filename'));
      final result = await completer.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      return result;
    } catch (e) {
      await sub.cancel();
      return false;
    }
  }

  // ── BLE Media Upload ──────────────────────────────────────────────────────
  Future<bool> uploadFileBle(
    String targetPath,
    Uint8List fileBytes, {
    void Function(double progress)? onProgress,
  }) async {
    if (_mediaStartChar == null ||
        _mediaDataChar == null ||
        _mediaEndChar == null || _currentStatus != BleStatus.connected) {
      await ensureConnectedAndReady();
    }
    if (_mediaStartChar == null ||
        _mediaDataChar == null ||
        _mediaEndChar == null) {
      if (kDebugMode) print('BLE Error: Media characteristics are NULL');
      return false;
    }
    try {
      final startMsg = '$targetPath,${fileBytes.length}';
      await _mediaStartChar!
          .write(utf8.encode(startMsg), withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 100));

      const int chunkSize = 240;
      int offset = 0;
      _cancelUpload = false;
      while (offset < fileBytes.length) {
        if (_cancelUpload) {
          _cancelUpload = false;
          try {
            await _mediaEndChar!.write([1], withoutResponse: false);
          } catch (_) {}
          throw Exception('Dibatalkan');
        }
        int end = offset + chunkSize;
        if (end > fileBytes.length) end = fileBytes.length;
        final chunk = fileBytes.sublist(offset, end);
        await _mediaDataChar!.write(chunk, withoutResponse: true);
        offset = end;
        if (onProgress != null) {
          onProgress(offset / fileBytes.length);
        }
        await Future.delayed(const Duration(milliseconds: 12));
      }

      await _mediaEndChar!.write([0], withoutResponse: false);
      if (kDebugMode) print('BLE Upload finished: $targetPath');
      return true;
    } catch (e) {
      if (e.toString().contains('Dibatalkan')) rethrow;
      if (kDebugMode) print('BLE Error during file upload: $e');
      return false;
    }
  }

  Future<void> uploadFilesBle(
    List<PlatformFile> files, {
    String targetDirectory = '/',
    void Function(int current, int total, double progress)? onProgress,
  }) async {
    if (files.isEmpty) return;

    String normalizeDir(String val) {
      var res = val.trim();
      if (res.isEmpty || res == '/') return '/';
      if (!res.startsWith('/')) res = '/$res';
      if (res.endsWith('/')) res = res.substring(0, res.length - 1);
      return res;
    }

    final normDir = normalizeDir(targetDirectory);
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
          bytes = await File(file.path!).readAsBytes();
        }
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Cannot read file: ${file.name}');
      }
      final remotePath = (normDir == '/')
          ? '/${file.name.trim()}'
          : '$normDir/${file.name.trim()}';

      final success = await uploadFileBle(
        remotePath,
        bytes,
        onProgress: (prog) {
          if (onProgress != null) {
            onProgress(i + 1, files.length, prog);
          }
        },
      );
      if (!success) {
        throw Exception('Failed to upload ${file.name} over BLE');
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void dispose() {
    _statusCtrl.close();
    _controlCtrl.close();
  }
}
