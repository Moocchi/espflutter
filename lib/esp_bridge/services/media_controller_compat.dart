
import 'package:flutter/services.dart';

class MediaInfo {
  final String track;
  final String artist;
  final String thumbnailUrl;
  final bool isPlaying;
  final int position;
  final int duration;

  const MediaInfo({
    required this.track,
    required this.artist,
    required this.thumbnailUrl,
    required this.isPlaying,
    required this.position,
    required this.duration,
  });
}

class FlutterMediaController {
  static const MethodChannel _channel = MethodChannel('flutter_media_controller');
  static const MethodChannel _permissionChannel = MethodChannel('media_permission_check');

  static int _estimatedPosition = 0;
  static int _estimatedDuration = 0;
  static DateTime? _lastPollAt;

  /// Expose estimasi milidetik untuk sinkronisasi lirik yang presisi
  static int getEstimatedPositionMs() => _estimatedPosition;

  static Future<void> requestPermissions() async {
    await _channel.invokeMethod('requestPermissions');
  }

  static Future<bool> isPermissionGranted() async {
    try {
      final granted = await _permissionChannel.invokeMethod<bool>(
        'isNotificationListenerEnabled',
      );
      if (granted != null) return granted;
    } catch (_) {
      // Fall through
    }
    return false;
  }

  static Future<MediaInfo> getCurrentMediaInfo() async {
    final hasPermission = await isPermissionGranted();
    if (!hasPermission) {
      return const MediaInfo(
        track: 'No track playing',
        artist: 'Unknown artist',
        thumbnailUrl: '',
        isPlaying: false,
        position: 0,
        duration: 0,
      );
    }

    Map<dynamic, dynamic>? raw;
    try {
      raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getMediaInfo');
    } catch (_) {
      raw = null;
    }

    final isPlaying = raw?['isPlaying'] == true;
    final track = raw?['track']?.toString() ?? 'No track playing';
    final artist = raw?['artist']?.toString() ?? 'Unknown artist';
    final thumbnailUrl = raw?['thumbnailUrl']?.toString() ?? '';

    final now = DateTime.now();
    if (_lastPollAt != null && isPlaying) {
      final elapsedMs = now.difference(_lastPollAt!).inMilliseconds;
      // Tingkatkan akurasi estimasi per-milidetik, bukan dibulatkan ke lantai (floor) detik.
      if (elapsedMs > 0) {
        _estimatedPosition += elapsedMs; 
      }
    }
    _lastPollAt = now;

    final parsedPositionMs = raw?['positionMs'] as int? ?? 
                             raw?['position_millis'] as int?;
    
    final parsedPositionSec = _parseSeconds(raw?['position']);

    // Utamakan milidetik jika ada untuk mendapatkan hasil presisi slider/lirik
    if (parsedPositionMs != null && parsedPositionMs > 0) {
      // Sinkronkan selalu dengan kalkulasi real-time dari native (Kotlin)
      // toleransi kecil (250ms) agar timer lokal tidak berkelahi dengan timer Kotlin
      if ((_estimatedPosition - parsedPositionMs).abs() > 250) {
        _estimatedPosition = parsedPositionMs;
      }
    } else if (parsedPositionSec != null) {
      final secToMs = parsedPositionSec * 1000;
      if ((_estimatedPosition - secToMs).abs() > 1500) {
        _estimatedPosition = secToMs;
      }
    }
    final parsedDuration = _parseSeconds(raw?['duration']) ??
        _parseMsToSeconds(raw?['durationMs']) ??
        _parseMsToSeconds(raw?['duration_millis']);

    if (parsedDuration != null && parsedDuration > 0) {
      _estimatedDuration = parsedDuration;
    }

    if (!isPlaying && _estimatedPosition < 0) {
      _estimatedPosition = 0;
    }

    return MediaInfo(
      track: track,
      artist: artist,
      thumbnailUrl: thumbnailUrl,
      isPlaying: isPlaying,
      position: _estimatedPosition < 0 ? 0 : (_estimatedPosition / 1000).round(),
      duration: _estimatedDuration < 0 ? 0 : _estimatedDuration,
    );
  }

  static Future<void> togglePlayPause() async {
    await _channel.invokeMethod('mediaAction', {'action': 'playPause'});
  }

  static Future<void> nextTrack() async {
    await _channel.invokeMethod('mediaAction', {'action': 'next'});
  }

  static Future<void> previousTrack() async {
    await _channel.invokeMethod('mediaAction', {'action': 'previous'});
  }

  static int? _parseSeconds(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static int? _parseMsToSeconds(dynamic value) {
    final ms = _parseSeconds(value);
    if (ms == null) return null;
    return (ms / 1000).round();
  }
}

