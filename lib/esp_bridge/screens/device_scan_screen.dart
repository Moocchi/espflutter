import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../services/system_media_service.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final BleService _ble = BleService();
  final SystemMediaBridgeService _mediaBridge = SystemMediaBridgeService();
  List<ScanResult> _results = [];
  bool _scanning = false;
  Timer? _uiUpdateTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanStateSub;
  bool _hasPendingResultChanges = false;
  static const int _maxVisibleDevices = 25;
  static const int _minRssi = -92;
  final Map<String, ScanResult> _resultMap =
      {}; // Changed from _bufferedResults to _resultMap

  @override
  void initState() {
    super.initState();
    _mediaBridge.setBridgeActive(false);
    _mediaBridge.setScannerMode(true);
    _startScan();

    // Update UI in shorter intervals for smoother list motion without overloading.
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 220), (timer) {
      if (_scanning &&
          mounted &&
          _resultMap.isNotEmpty &&
          _hasPendingResultChanges) {
        // Changed _bufferedResults to _resultMap
        setState(() {
          _hasPendingResultChanges = false;
          _results =
              _resultMap.values
                  .where((e) => e.rssi >= _minRssi)
                  .toList() // Updated to use _resultMap
                ..sort((a, b) => b.rssi.compareTo(a.rssi)); // Added sorting
          if (_results.length > _maxVisibleDevices) {
            _results = _results.sublist(0, _maxVisibleDevices);
          }
        });
      }
    });
  }

  Future<void> _startScan() async {
    setState(() {
      _resultMap.clear(); // Changed _bufferedResults to _resultMap
      _results.clear();
      _scanning = true;
    });

    try {
      // IMPORTANT: Set up listeners BEFORE starting scan
      await _scanSub?.cancel();
      await _scanStateSub?.cancel();

      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        if (!mounted) return;
        for (final r in results) {
          if (r.rssi < _minRssi) continue;
          final id = r.device.remoteId.toString();
          final prev = _resultMap[id];
          if (prev == null || prev.rssi != r.rssi) {
            _resultMap[id] = r;
            _hasPendingResultChanges = true;
          }
        }
      });

      _scanStateSub = FlutterBluePlus.isScanning.listen((isScanning) {
        if (!mounted) return;
        if (_scanning != isScanning) {
          setState(() {
            _scanning = isScanning;
            if (!isScanning) {
              _results = _resultMap.values.toList()
                ..sort((a, b) => b.rssi.compareTo(a.rssi));
              if (_results.length > _maxVisibleDevices) {
                _results = _results.sublist(0, _maxVisibleDevices);
              }
            }
          });
        }
      });

      // Now start scan AFTER listeners are ready
      // Mengubah mode ke 'balanced' untuk mengurangi ngadat (stuttering) akibat terlalu banyak sinyal
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 30),
        androidUsesFineLocation: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );
    } catch (e) {
      if (kDebugMode) print('Scan error: $e');
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    if (!mounted) return;
    Navigator.pop(context);
    await _ble.connectToDevice(device);
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _scanSub?.cancel();
    _scanStateSub?.cancel();
    _mediaBridge.setScannerMode(false);
    _mediaBridge.setBridgeActive(true);
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F2FF),
        elevation: 0,
        title: const Text(
          'Cari Perangkat',
          style: TextStyle(
            color: Color(0xFF2F3445),
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF5B6274)),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF6252E7),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _startScan,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: LinearProgressIndicator(
                backgroundColor: const Color(0xFFD8D4FF),
                color: const Color(0xFF6252E7),
                minHeight: 2,
              ),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.bluetooth_searching_rounded,
                          size: 64,
                          color: Color(0xFFD2CFFF),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Mencari perangkat ESP32...',
                          style: TextStyle(color: Color(0xFF6D7385)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final r = _results[i];
                      final name = r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : r.advertisementData.advName.isNotEmpty
                          ? r.advertisementData.advName
                          : 'Unknown Device';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: const Color(0xFFFDFDFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: const Color(0xFF6252E7).withOpacity(0.45),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          onTap: () => _connect(r.device),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF6252E7),
                            child: Icon(
                              Icons.bluetooth_rounded,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              color: Color(0xFF2F3445),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            r.device.remoteId.toString(),
                            style: const TextStyle(
                              color: Color(0xFF6D7385),
                              fontSize: 12,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: Color(0xFF6252E7),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
