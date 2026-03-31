import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/media_controller_compat.dart';
import '../services/ble_service.dart';
import '../services/system_media_service.dart';
import 'device_scan_screen.dart';

class PlayerScreen extends StatefulWidget {
  final bool showMenuButton;
  final VoidCallback? onMenuTap;

  const PlayerScreen({
    super.key,
    this.showMenuButton = false,
    this.onMenuTap,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  final BleService _ble = BleService();
  final SystemMediaBridgeService _mediaBridge = SystemMediaBridgeService();
  BleStatus _bleStatus = BleStatus.disconnected;
  StreamSubscription? _bleSub;
  bool _hasPermission = true;
  String? _lastThumbnail;
  Uint8List? _cachedImage;

  // Drag/seek state
  bool _isDragging = false;
  double _dragProgress = 0.0;
  Timer? _dragSendTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenBle();
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bleSub?.cancel();
    _dragSendTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    await _mediaBridge.checkPermissionStatus();
    if (mounted) {
      setState(() => _hasPermission = _mediaBridge.hasPermission);
    }
  }

  void _listenBle() {
    _bleSub = _ble.statusStream.listen((s) {
      if (mounted) {
        setState(() => _bleStatus = s);
        if (s == BleStatus.connected) {
          _mediaBridge.syncState();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F2FF),
        elevation: 0,
        leading: widget.showMenuButton
            ? IconButton(
                onPressed: widget.onMenuTap,
                icon: const Icon(Icons.menu_rounded, color: Color(0xFF5B6274)),
              )
            : null,
        title: const Text(
          'Media Bridge',
          style: TextStyle(
            color: Color(0xFF2F3445),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [_buildConnectionBadge(), const SizedBox(width: 8)],
      ),
      body: StreamBuilder<MediaInfo>(
        stream: _mediaBridge.mediaStream,
        builder: (context, snapshot) {
          final info = snapshot.data;

          if (!_hasPermission) return _buildPermissionPrompt();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMetadataDisplay(info),
                const SizedBox(height: 40),
                _buildProgressDisplay(info),
                const SizedBox(height: 40),
                _buildControls(info),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionBadge() {
    Color statusColor = const Color(0xFF9AA0B3);
    String statusText = 'Disconnected';
    IconData icon = Icons.bluetooth_disabled_rounded;

    if (_bleStatus == BleStatus.connected) {
      statusColor = const Color(0xFF6252E7);
      statusText = 'Connected';
      icon = Icons.bluetooth_connected_rounded;
    } else if (_bleStatus == BleStatus.connecting ||
        _bleStatus == BleStatus.scanning) {
      statusColor = const Color(0xFF8E85ED);
      statusText = 'Syncing...';
      icon = Icons.bluetooth_searching_rounded;
    }

    return ActionChip(
      onPressed: () {
        if (_bleStatus == BleStatus.connected) {
          _ble.disconnect();
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
          );
        }
      },
      avatar: Icon(icon, color: statusColor, size: 16),
      label: Text(
        statusText,
        style: TextStyle(color: statusColor, fontSize: 12),
      ),
      backgroundColor: const Color(0xFFF7F5FF),
      side: BorderSide(color: statusColor.withOpacity(0.45)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildMetadataDisplay(MediaInfo? info) {
    Widget albumArt;
    if (info != null && info.thumbnailUrl.isNotEmpty) {
      if (info.thumbnailUrl != _lastThumbnail) {
        _lastThumbnail = info.thumbnailUrl;
        final rawThumb = info.thumbnailUrl.trim();
        try {
          final normalizedBase64 = rawThumb.replaceAll(RegExp(r'\s+'), '');
          _cachedImage = base64Decode(normalizedBase64);
        } catch (e) {
          _cachedImage = null;
        }
      }

      if (_cachedImage != null) {
        albumArt = ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Image.memory(
            _cachedImage!,
            width: 240,
            height: 240,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.music_note_rounded,
              size: 80,
              color: Color(0xFFD2CFFF),
            ),
          ),
        );
      } else if (Uri.tryParse(info.thumbnailUrl)?.hasScheme == true) {
        albumArt = ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Image.network(
            info.thumbnailUrl,
            width: 240,
            height: 240,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.music_note_rounded,
              size: 80,
              color: Color(0xFFD2CFFF),
            ),
          ),
        );
      } else {
        albumArt = const Icon(
          Icons.music_note_rounded,
          size: 80,
          color: Color(0xFFD2CFFF),
        );
      }
    } else {
      _lastThumbnail = null;
      _cachedImage = null;
      albumArt = const Icon(
        Icons.music_note_rounded,
        size: 80,
        color: Color(0xFFD2CFFF),
      );
    }

    return Column(
      children: [
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            color: const Color(0xFFFDFDFF),
            border: Border.all(color: const Color(0xFFC9C3FF)),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6252E7).withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: albumArt,
        ),
        const SizedBox(height: 32),
        Text(
          info?.track ?? 'No Media Detected',
          style: const TextStyle(
            color: Color(0xFF2F3445),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          info?.artist ?? 'Unknown Artist',
          style: const TextStyle(color: Color(0xFF6D7385), fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProgressDisplay(MediaInfo? info) {
    final int duration = info?.duration ?? 0;
    double progress;
    int displayPosition;

    if (_isDragging) {
      progress = _dragProgress;
      displayPosition = (duration * _dragProgress).round();
    } else {
      progress = (info != null && duration > 0)
          ? (info.position / duration).clamp(0.0, 1.0)
          : 0.0;
      displayPosition = info?.position ?? 0;
    }

    String formatTime(int seconds) {
      int m = seconds ~/ 60;
      int s = seconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: const Color(0xFF6252E7),
            inactiveTrackColor: const Color(0xFFD8D4FF),
            thumbColor: const Color(0xFF4C42CF),
          ),
          child: Slider(
            value: progress,
            onChangeStart: (v) {
              setState(() {
                _isDragging = true;
                _dragProgress = v;
              });
              // Start throttled BLE sending (every 50ms for smooth animation)
              _dragSendTimer?.cancel();
              _dragSendTimer = Timer.periodic(
                const Duration(milliseconds: 50),
                (_) {
                  final pos = (duration * _dragProgress).round();
                  _mediaBridge.sendPositionToEsp(pos);
                },
              );
            },
            onChanged: (v) {
              setState(() => _dragProgress = v);
            },
            onChangeEnd: (v) {
              _dragSendTimer?.cancel();
              _dragSendTimer = null;
              final seekPos = (duration * v).round();
              setState(() => _isDragging = false);
              // Seek the actual media player + send final position to ESP
              _mediaBridge.seekTo(seekPos);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatTime(displayPosition),
                style: const TextStyle(color: Color(0xFF6D7385), fontSize: 12),
              ),
              Text(
                formatTime(duration),
                style: const TextStyle(color: Color(0xFF6D7385), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls(MediaInfo? info) {
    bool isPlaying = info?.isPlaying ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 40),
          color: const Color(0xFF6252E7),
          onPressed: _mediaBridge.skipPrev,
        ),
        GestureDetector(
          onTap: _mediaBridge.togglePlayPause,
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color(0xFF6252E7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 40),
          color: const Color(0xFF6252E7),
          onPressed: _mediaBridge.skipNext,
        ),
      ],
    );
  }

  Widget _buildPermissionPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_person_rounded,
              color: Color(0xFF6252E7),
              size: 64,
            ),
            const SizedBox(height: 24),
            const Text(
              'Akses Diperlukan',
              style: TextStyle(
                color: Color(0xFF2F3445),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Aplikasi butuh izin "Notification Listener" untuk mengirim data lagu ke ESP32.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6D7385), fontSize: 14),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                await _mediaBridge.requestPermission();
                await Future.delayed(const Duration(milliseconds: 600));
                await _checkPermission();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6252E7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text('Buka Pengaturan'),
            ),
          ],
        ),
      ),
    );
  }
}
