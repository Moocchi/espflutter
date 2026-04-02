import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'media_controller_compat.dart';
import 'ble_service.dart';
import 'lyrics_service.dart';

class SystemMediaBridgeService {
  static final SystemMediaBridgeService _instance =
      SystemMediaBridgeService._internal();

  factory SystemMediaBridgeService() => _instance;

  SystemMediaBridgeService._internal();

  final BleService _bleService = BleService();
  final LyricsService _lyricsService = LyricsService();
  Timer? _metadataTimer; // cek title/artist/status tiap 2 detik
  Timer? _priorityTimer; // kirim posisi+lirik tiap 250ms (PRIORITAS)
  bool _priorityBusy = false;
  bool _metadataBusy = false;
  bool _scannerModeActive = false;
  bool _uiBusy = false;
  DateTime _uiBusyHoldUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScannerPriorityPoll = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScannerMetadataPoll = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUiEmitAt = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<BleStatus>? _bleStatusSub;
  String _lastLyricsKey = '';
  int _lyricsCooldownUntilMs = 0;
  int _lastLyricsDurationMs = 0;

  // State terkini
  String _currentTitle = '';
  String _currentArtist = '';
  int _currentDuration = 0;
  int _currentPosition = 0;
  bool _isPlaying = false;

  final _mediaUpdateController = StreamController<MediaInfo>.broadcast();
  Stream<MediaInfo> get mediaStream => _mediaUpdateController.stream;
  MediaInfo? _lastEmittedInfo;

  bool _hasPermission = false;
  bool get hasPermission => _hasPermission;
  bool _bridgeActive = false;

  Future<void> init() async {
    // 1) Cek izin, jika belum ada baru minta (tapi jangan paksa buka setting di init)
    _hasPermission = await FlutterMediaController.isPermissionGranted();

    // 2) Dengarkan perintah dari tombol ESP32 via BLE
    _bleService.controlStream.listen((command) {
      _handleEspCommand(command);
    });

    _bleStatusSub = _bleService.statusStream.listen((status) {
      if (status == BleStatus.connected) {
        unawaited(syncState());
        if (_lyricsService.hasLyrics) {
          unawaited(_bleService.sendLyrics(
            _lyricsService.prevLine,
            _lyricsService.activeLine,
            _lyricsService.nextLine,
          ));
        }
      }
    });

    // Polling dimulai hanya saat halaman ESP Bridge aktif.
    if (_hasPermission && _bridgeActive) {
      _startPolling();
    }
  }

  Future<void> setBridgeActive(bool active) async {
    _bridgeActive = active;
    if (!active) {
      _stopPolling();
      _scannerModeActive = false;
      return;
    }
    await checkPermissionStatus();
    if (_hasPermission) {
      _startPolling();
    }
  }

  void _stopPolling() {
    _metadataTimer?.cancel();
    _priorityTimer?.cancel();
    _metadataTimer = null;
    _priorityTimer = null;
    _priorityBusy = false;
    _metadataBusy = false;
  }

  Future<void> requestPermission() async {
    await FlutterMediaController.requestPermissions();
    _hasPermission = await FlutterMediaController.isPermissionGranted();
    if (_hasPermission && _bridgeActive) {
      _startPolling();
    }
  }

  Future<void> checkPermissionStatus() async {
    final wasGranted = _hasPermission;
    _hasPermission = await FlutterMediaController.isPermissionGranted();
    if (!wasGranted && _hasPermission && _bridgeActive) {
      _startPolling();
    } else if (wasGranted && !_hasPermission) {
      _stopPolling();
    }
  }

  int _permissionErrorCount = 0;

  void setScannerMode(bool active) {
    _scannerModeActive = active;
    _lastScannerPriorityPoll = DateTime.fromMillisecondsSinceEpoch(0);
    _lastScannerMetadataPoll = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void setUiBusy(bool busy, {int holdMsAfterRelease = 0}) {
    if (_uiBusy == busy) return;
    _uiBusy = busy;
    if (!busy && holdMsAfterRelease > 0) {
      _uiBusyHoldUntil = DateTime.now().add(
        Duration(milliseconds: holdMsAfterRelease),
      );
    } else if (busy) {
      _uiBusyHoldUntil = DateTime.fromMillisecondsSinceEpoch(0);
    }
    if (!busy && _lastEmittedInfo != null) {
      _mediaUpdateController.add(_lastEmittedInfo!);
      _lastUiEmitAt = DateTime.now();
    }
  }

  void _startPolling() {
    if (!_bridgeActive) return;
    _stopPolling();

    // ── Priority Timer: Posisi + Lirik + UI (250ms) ──────────────────
    _priorityTimer = Timer.periodic(const Duration(milliseconds: 160), (
      _,
    ) async {
      if (!_bridgeActive) return;

      final effectiveUiBusy = _uiBusy || DateTime.now().isBefore(_uiBusyHoldUntil);
      if (effectiveUiBusy) return;

      if (_scannerModeActive && _bleService.currentStatus != BleStatus.connected) {
        final now = DateTime.now();
        if (now.difference(_lastScannerPriorityPoll).inMilliseconds < 280) {
          return;
        }
        _lastScannerPriorityPoll = now;
      }

      if (_priorityBusy) return;
      _priorityBusy = true;
      try {
        final info = await FlutterMediaController.getCurrentMediaInfo();
        
        // Deteksi secara instan kalau status play/pause berubah 
        if (_isPlaying != info.isPlaying) {
          _isPlaying = info.isPlaying;
          if (_bleService.currentStatus == BleStatus.connected) {
            unawaited(_bleService.sendStatus(_isPlaying));
          }
        }

        final newPos = info.position < 0 ? 0 : info.position;

        // Selalu update State UI paling cepat disini jika ada perubahan detik/lagu
        final changed = _lastEmittedInfo == null ||
            _lastEmittedInfo!.track != info.track ||
            _lastEmittedInfo!.artist != info.artist ||
            _lastEmittedInfo!.isPlaying != info.isPlaying ||
            _lastEmittedInfo!.position != info.position ||
            _lastEmittedInfo!.duration != info.duration;
        if (changed) {
          final majorChanged = _lastEmittedInfo == null ||
              _lastEmittedInfo!.track != info.track ||
              _lastEmittedInfo!.artist != info.artist ||
              _lastEmittedInfo!.isPlaying != info.isPlaying ||
              _lastEmittedInfo!.duration != info.duration;

          final now = DateTime.now();
          final uiIntervalMs = now.difference(_lastUiEmitAt).inMilliseconds;
              final canEmit =
                !effectiveUiBusy && (majorChanged || uiIntervalMs >= 420);

          if (canEmit) {
            _mediaUpdateController.add(info);
            _lastUiEmitAt = now;
          }

          _lastEmittedInfo = info;
        }

        // Cepat tanggap jika lagu berganti: bersihkan lirik lama seketika!
        if (info.track != _currentTitle || info.artist != _currentArtist) {
          _lyricsService.clear();
          _lyricsCooldownUntilMs = 0;
          if (_bleService.currentStatus == BleStatus.connected) {
            unawaited(_bleService.sendLyrics("", "", ""));
          }
          // Panggil fungsi sinkronisasi info secara instan (tidak usah tunggu timer lambat)
          unawaited(_handleMetadataUpdate(info));
          return; // Hentikan iterasi ini agar tidak menimpa dengan lirik lama
        }

        // Hentikan fungsi jika ble tidak konek
        if (_bleService.currentStatus != BleStatus.connected) return;

        if (!_isPlaying && newPos == _currentPosition) {
          return; // tidak perlu update ke ESP saat pause jika posisi tidak berubah
        }

        var sentLyricsThisTick = false;

        // Sync lirik selalu jalan menggunakan perkiraan posisi yg sekarang di info.position
        if (_lyricsService.hasLyrics &&
            DateTime.now().millisecondsSinceEpoch >= _lyricsCooldownUntilMs) {
          // Cari perkiraan posisi milidetik aktualnya
          final msActualPosition = FlutterMediaController.getEstimatedPositionMs();
          final lineChanged = _lyricsService.updatePosition(msActualPosition);
          if (lineChanged) {
            sentLyricsThisTick = true;
            unawaited(_bleService.sendLyrics(
              _lyricsService.prevLine,
              _lyricsService.activeLine,
              _lyricsService.nextLine,
            ));
          }
        }

        // Posisi berubah (dalam hitungan detik bulat) -> kirim ESP
        if (!sentLyricsThisTick && newPos != _currentPosition) {
          _currentPosition = newPos;
          unawaited(_bleService.sendPosition(_currentPosition));
        }
      } catch (_) {
      } finally {
        _priorityBusy = false;
      }
    });

    // ── Metadata Timer: Title/Artist/Status (2000ms) ─────────────
    // Lebih jarang karena hanya butuh mengecek metadata/izin yang berat
    _metadataTimer = Timer.periodic(const Duration(milliseconds: 2000), (
      timer,
    ) async {
      if (!_bridgeActive) return;
      final effectiveUiBusy = _uiBusy || DateTime.now().isBefore(_uiBusyHoldUntil);
      if (effectiveUiBusy) return;
      if (_scannerModeActive && _bleService.currentStatus != BleStatus.connected) {
        final now = DateTime.now();
        if (now.difference(_lastScannerMetadataPoll).inMilliseconds < 3200) {
          return;
        }
        _lastScannerMetadataPoll = now;
      }

      if (_metadataBusy) return;
      _metadataBusy = true;
      try {
        final info = await FlutterMediaController.getCurrentMediaInfo();
        _permissionErrorCount = 0;
        if (!_hasPermission) _hasPermission = true;

        _currentPosition = info.position < 0 ? 0 : info.position;
        if (info.duration > 0) {
          _currentDuration = info.duration;
        }

        await _handleMetadataUpdate(info);
      } catch (e) {
        if (e.toString().contains('SecurityException') ||
            e.toString().contains('permission')) {
          _permissionErrorCount++;
          if (_permissionErrorCount >= 2) _hasPermission = false;
        }
      } finally {
        _metadataBusy = false;
      }
    });
  }

  Future<void> syncState() async {
    if (_bleService.currentStatus == BleStatus.connected) {
      await _bleService.sendSongInfo(
        _currentTitle,
        _currentArtist,
        _currentDuration,
      );
      await _bleService.sendPosition(_currentPosition);
      await _bleService.sendStatus(_isPlaying);
    }
  }

  /// Proses perubahan metadata (title, artist, status) — dipanggil tiap 2 detik
  Future<void> _handleMetadataUpdate(MediaInfo info) async {
    final songChanged =
        info.track != _currentTitle || info.artist != _currentArtist;
    final statusChanged = info.isPlaying != _isPlaying;
    final durationChanged = info.duration > 0 && info.duration != _currentDuration;

    if (songChanged || durationChanged) {
      _currentTitle = info.track;
      _currentArtist = info.artist;
      _currentDuration = info.duration > 0 ? info.duration : _currentDuration;
      _currentPosition = info.position < 0 ? 0 : info.position;
      if (kDebugMode) print('Song: ${info.track} | artist: ${info.artist}');

      if (_bleService.currentStatus == BleStatus.connected) {
        await _bleService.sendSongInfo(
          _currentTitle,
          _currentArtist,
          _currentDuration,
        );
      }

      // Fetch lirik baru di background (hanya jika lagu benar-benar ganti)
      if (songChanged) {
        final lyricsKey =
            '${_currentTitle.trim().toLowerCase()}|${_currentArtist.trim().toLowerCase()}';
        if (lyricsKey != _lastLyricsKey) {
          _lastLyricsKey = lyricsKey;
          _lyricsService.clear();
          _lastLyricsDurationMs = info.duration > 0 ? info.duration : 0;
          
          // Me-passing durasi asli dari Kotlin ke API Lrclib karena Lrclib butuh durasi untuk pencarian yang sangat 100% akurat
          final durasiMilliseconds = info.duration;

          _lyricsService.fetchLyrics(_currentTitle, _currentArtist, durationMs: durasiMilliseconds).then((found) {
            // CEGAH BALAPAN DATA (RACE CONDITION):
            // Jika saat request lirik ini selesai, ternyata lagu di HP sudah ganti lagi, abaikan hasilnya!
            final currentKeyCheck = '${_currentTitle.trim().toLowerCase()}|${_currentArtist.trim().toLowerCase()}';
            if (currentKeyCheck != lyricsKey) return; 

            if (kDebugMode) print('[Lyrics] found=$found for "$_currentTitle"');
            if (_bleService.currentStatus == BleStatus.connected) {
              if (found) {
                _lyricsCooldownUntilMs = 0;
                final msActualPosition = FlutterMediaController.getEstimatedPositionMs();
                _lyricsService.updatePosition(msActualPosition);
                _bleService.sendLyrics(
                  _lyricsService.prevLine,
                  _lyricsService.activeLine,
                  _lyricsService.nextLine,
                );
              } else {
                _lyricsCooldownUntilMs = 0;
                // Beritahu ESP jika lirik benar-benar tidak ditemukan / gagal diambil
                _bleService.sendLyrics("", "Lyric Not Found", "");
                
                // Hapus tulisan 'Lyrics not found' setelah tampil 10 detik
                Future.delayed(const Duration(seconds: 10), () {
                  // Pastikan lagu yang diputar di timer ini masih sama dengan lagu saat not found tadi
                  final currentKeyCheck = '${_currentTitle.trim().toLowerCase()}|${_currentArtist.trim().toLowerCase()}';
                  if (_bleService.currentStatus == BleStatus.connected && currentKeyCheck == lyricsKey) {
                    _bleService.sendLyrics("", "", "");
                  }
                });
              }
            }
          });
        }
      }
    } else if (info.duration != _currentDuration && info.duration > 0) {
      _currentDuration = info.duration;
      // Jika durasi baru tersedia dan lirik belum ketemu, coba sekali lagi dengan durasi valid.
      // Juga retry jika durasi sebelumnya berbeda signifikan (>2 detik) — bisa jadi search pertama gagal karena durasi salah.
      final durationDiffMs = (_lastLyricsDurationMs - info.duration).abs();
      final shouldRetryLyrics = !_lyricsService.hasLyrics && 
          (_lastLyricsDurationMs <= 0 || durationDiffMs > 2000);
      if (shouldRetryLyrics) {
        _lastLyricsDurationMs = info.duration;
        _lyricsService.fetchLyrics(
          _currentTitle,
          _currentArtist,
          durationMs: _lastLyricsDurationMs,
        ).then((found) {
          final currentKeyCheck =
              '${_currentTitle.trim().toLowerCase()}|${_currentArtist.trim().toLowerCase()}';
          if (currentKeyCheck != _lastLyricsKey) return;

          if (kDebugMode) {
            print('[Lyrics] retry-with-duration found=$found for "$_currentTitle"');
          }
          if (_bleService.currentStatus == BleStatus.connected) {
            if (found) {
              final msActualPosition =
                  FlutterMediaController.getEstimatedPositionMs();
              _lyricsService.updatePosition(msActualPosition);
              _bleService.sendLyrics(
                _lyricsService.prevLine,
                _lyricsService.activeLine,
                _lyricsService.nextLine,
              );
            }
          }
        });
      }
      if (_bleService.currentStatus == BleStatus.connected) {
        await _bleService.sendDuration(_currentDuration);
      }
    }

    if (statusChanged) {
      _isPlaying = info.isPlaying;
      if (_bleService.currentStatus == BleStatus.connected) {
        await _bleService.sendStatus(_isPlaying);
      }
    }
  }

  void _handleEspCommand(int command) {
    // 0 = Prev, 1 = Play/Pause, 2 = Next
    switch (command) {
      case 0:
        FlutterMediaController.previousTrack();
        break;
      case 1:
        FlutterMediaController.togglePlayPause();
        break;
      case 2:
        FlutterMediaController.nextTrack();
        break;
    }
  }

  void togglePlayPause() => FlutterMediaController.togglePlayPause();
  void skipNext() => FlutterMediaController.nextTrack();
  void skipPrev() => FlutterMediaController.previousTrack();

  Future<void> seekTo(int positionSeconds) async {
    // Panggil MethodChannel langsung ke MediaController native
    const channel = MethodChannel('flutter_media_controller');
    await channel.invokeMethod('seekTo', {'position': positionSeconds * 1000});
    
    // Perbarui state internal
    _currentPosition = positionSeconds;
    
    // Sinkronisasi secara manual ke Bluetooth setelah digeser
    if (_bleService.currentStatus == BleStatus.connected) {
      await _bleService.sendPosition(positionSeconds);
      
      // Update juga lirik biar langsung sinkron tanpa nunggu timer
      if (_lyricsService.hasLyrics) {
        final lineChanged = _lyricsService.updatePosition(positionSeconds * 1000);
        if (lineChanged) {
          unawaited(_bleService.sendLyrics(
            _lyricsService.prevLine,
            _lyricsService.activeLine,
            _lyricsService.nextLine,
          ));
        }
      }
    }
  }

  /// Send position to ESP32 only (no media seek) — used during drag
  Future<void> sendPositionToEsp(int positionSeconds) async {
    if (_bleService.currentStatus == BleStatus.connected) {
      await _bleService.sendPosition(positionSeconds);
    }
  }

  void dispose() {
    _stopPolling();
    _bleStatusSub?.cancel();
    _mediaUpdateController.close();
  }
}
