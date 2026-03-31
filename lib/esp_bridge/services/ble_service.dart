import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String _serviceUuid = '12345678-1234-1234-1234-1234567890ab';
const String _titleUuid = '12345678-1234-1234-1234-1234567890a1';
const String _artistUuid = '12345678-1234-1234-1234-1234567890a2';
const String _durationUuid = '12345678-1234-1234-1234-1234567890a3';
const String _positionUuid = '12345678-1234-1234-1234-1234567890a4';
const String _controlUuid = '12345678-1234-1234-1234-1234567890a5';
const String _statusUuid = '12345678-1234-1234-1234-1234567890a6';
const String _lyricPrevUuid = '12345678-1234-1234-1234-1234567890b1';
const String _lyricActiveUuid = '12345678-1234-1234-1234-1234567890b2';
const String _lyricNextUuid = '12345678-1234-1234-1234-1234567890b3';
const String _targetDevName = 'Spotfy-ESP32';
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

  Future<void> scanAndConnect() async {
    if (_currentStatus != BleStatus.disconnected) return;
    _setStatus(BleStatus.scanning);

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          if (r.device.platformName == _targetDevName ||
              r.advertisementData.advName == _targetDevName) {
            await FlutterBluePlus.stopScan();
            await _connect(r.device);
            return;
          }
        }
      }
      _setStatus(BleStatus.disconnected);
    } catch (e) {
      _setStatus(BleStatus.disconnected);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    _setStatus(BleStatus.connecting);
    _device = device;
    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

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
    final services = await device.discoverServices();
    if (kDebugMode) {
      print('BLE: Discovering services for ${device.remoteId}...');
    }
    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase() == _serviceUuid) {
        if (kDebugMode) {
          print('BLE: Found Target Service: $_serviceUuid');
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
        }
        break;
      }
    }

    // Subscribe CONTROL notify
    if (_controlChar != null) {
      await _controlChar!.setNotifyValue(true);
      _controlChar!.lastValueStream.listen((data) {
        if (data.isNotEmpty) _controlCtrl.add(data[0]);
      });
    }
  }

  void _clearChars() {
    _titleChar = _artistChar = _durationChar = _positionChar = _controlChar =
        _statusChar = null;
    _lyricPrevChar = _lyricActiveChar = _lyricNextChar = null;
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

  void dispose() {
    _statusCtrl.close();
    _controlCtrl.close();
  }
}
