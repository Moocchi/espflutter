import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A single timed lyric line.
class LyricLine {
  final int timeMs; // timestamp in milliseconds
  final String text;
  LyricLine(this.timeMs, this.text);
}

class LyricsService {
  static const String _cacheStorageKey = 'lyrics_cache_v1';
  static const int _maxCacheItems = 100;
  static const int _cacheTtlMs = 7 * 24 * 60 * 60 * 1000;

  static final LyricsService _instance = LyricsService._internal();
  factory LyricsService() => _instance;
  LyricsService._internal();

  http.Client _httpClient = http.Client();
  final Future<void> _storageInit = Future<void>.value();
  List<LyricLine> _lines = [];
  int _activeIndex = -1;
  final Map<String, List<LyricLine>> _lyricsCache = {};
  final Map<String, int> _cacheUpdatedAt = {};
  bool _storageReady = false;
  bool _storageInitStarted = false;
  Timer? _persistDebounce;

  /// Current prev / active / next strings (empty if not available)
  String get prevLine => _activeIndex > 0 ? _lines[_activeIndex - 1].text : '';
  String get activeLine => _activeIndex >= 0 && _activeIndex < _lines.length
      ? _lines[_activeIndex].text
      : '';
  String get nextLine => _activeIndex >= 0 && _activeIndex < _lines.length - 1
      ? _lines[_activeIndex + 1].text
      : '';

  bool get hasLyrics => _lines.isNotEmpty;

  // ── Fetch & Parse ──────────────────────────────────────────────────────────
  /// Fetch synced lyrics from LRCLIB for the given [track] and [artist].
  /// Returns true if lyrics were found, false otherwise.
  Future<bool> fetchLyrics(String track, String artist, {int? durationMs}) async {
    await _ensureStorageReady();

    _lines = [];
    _activeIndex = -1;

    if (track.isEmpty || artist.isEmpty) return false;

    // Bersihkan judul dan nama artis dari "sampah" metadata Apple Music
    final normalizedTrack = _normalizeTrackTitle(track);
    final normalizedArtist = _normalizeArtist(artist);
    final primaryKey = _makeCacheKey(track, artist);
    final normalizedKey = _makeCacheKey(normalizedTrack, normalizedArtist);

    final cachedPrimary = _lyricsCache[primaryKey];
    if (cachedPrimary != null && cachedPrimary.isNotEmpty) {
      _lines = List<LyricLine>.from(cachedPrimary);
      return true;
    }

    final cachedNormalized = _lyricsCache[normalizedKey];
    if (cachedNormalized != null && cachedNormalized.isNotEmpty) {
      _lines = List<LyricLine>.from(cachedNormalized);
      _lyricsCache[primaryKey] = List<LyricLine>.from(cachedNormalized);
      return true;
    }

    int? durationSec;
    if (durationMs != null && durationMs > 0) {
      // Android mediaSession reports duration inconsistently:
      // Some apps report milliseconds (e.g. 240000), others seconds (e.g. 240).
      // Heuristic: if value > 10000, it's almost certainly milliseconds.
      if (durationMs > 10000) {
        durationSec = (durationMs / 1000).round();
      } else {
        // Could be seconds already (e.g. 240) or very short audio in ms.
        // Treat as seconds if > 10 (unlikely to have >10s audio reported as ms).
        durationSec = durationMs > 10 ? durationMs : null;
      }
    }

    // ══════════════════════════════════════════════════════════════════
    // STRATEGI PENCARIAN (dioptimalkan berdasarkan perilaku LRCLIB):
    //
    // LRCLIB /api/search SANGAT ketat soal durasi — selisih 1 detik = 0 hasil.
    // Oleh karena itu, pencarian search/q dilakukan TANPA durasi dulu.
    // Durasi hanya dipakai untuk /api/get (direct lookup) sebagai filter presisi.
    // ══════════════════════════════════════════════════════════════════
    int maxRetries = 4;
    
    while (maxRetries > 0) {
      try {
        // ── Langkah 1: Direct GET (dengan durasi jika ada, paling presisi) ──
        final primary = await _fetchByGet(track: track, artist: artist, durationSec: durationSec);
        if (primary) {
          _saveCache(primaryKey);
          _saveCache(normalizedKey);
          return true;
        }

        // ── Langkah 2: Direct GET tanpa durasi (jika langkah 1 gagal karena durasi) ──
        if (durationSec != null) {
          final noDurGet = await _fetchByGet(track: track, artist: artist);
          if (noDurGet) {
            _saveCache(primaryKey);
            _saveCache(normalizedKey);
            return true;
          }
        }

        // ── Langkah 3: Direct GET dengan nama yang di-normalize ──
        if (normalizedTrack != track || normalizedArtist != artist) {
          final normalized = await _fetchByGet(track: normalizedTrack, artist: normalizedArtist);
          if (normalized) {
            _saveCache(normalizedKey);
            _saveCache(primaryKey);
            return true;
          }
        }

        // ── Langkah 4: Search TANPA durasi (search endpoint + durasi = bencana) ──
        final searchResult = await _fetchBySearch(
          track: normalizedTrack,
          artist: normalizedArtist,
        );
        if (searchResult) {
          _saveCache(normalizedKey);
          _saveCache(primaryKey);
          return true;
        }

        // ── Langkah 5: Q search TANPA durasi (paling fleksibel) ──
        final qResult = await _fetchByQ(query: '$normalizedTrack $normalizedArtist');
        if (qResult) {
          _saveCache(normalizedKey);
          _saveCache(primaryKey);
          return true;
        }

        // ── Langkah 6: Q search hanya judul (artis bisa bikin rancu) ──
        final qTrackOnly = await _fetchByQ(query: normalizedTrack);
        if (qTrackOnly) {
          _saveCache(normalizedKey);
          _saveCache(primaryKey);
          return true;
        }

        // Jika sampai sini, berarti API jalan tapi lirik memang tidak ada di database.
        break;
      } catch (e) {
        maxRetries--;
        if (kDebugMode) print('[Lyrics] Network error, retry left: $maxRetries — $e');
        // Buat HTTP client baru agar DNS cache & koneksi basi di-flush
        _resetHttpClient();
        if (maxRetries > 0) {
          await Future.delayed(const Duration(seconds: 4));
        }
      }
    }

    return false;
  }

  void _resetHttpClient() {
    try {
      _httpClient.close();
    } catch (_) {}
    _httpClient = http.Client();
  }

  Future<bool> _fetchByGet({required String track, required String artist, int? durationSec}) async {
    try {
      final Map<String, dynamic> query = {
        'track_name': track,
        'artist_name': artist,
      };
      if (durationSec != null && durationSec > 0) {
        query['duration'] = durationSec.toString();
      }

      final uri = Uri.https('lrclib.net', '/api/get', query);
      if (kDebugMode) print('[Lyrics] Fetching GET: $uri');

      final response = await _httpClient
          .get(
            uri,
            headers: {
              'User-Agent': 'SpotfyESP/1.0 (https://github.com/user/esp-test)',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final syncedLrc = json['syncedLyrics'] as String?;
        if (syncedLrc != null && syncedLrc.isNotEmpty) {
          _lines = _parseLrc(syncedLrc);
          if (kDebugMode) {
            print('[Lyrics] Loaded ${_lines.length} lines for "$track"');
          }
          return _lines.isNotEmpty;
        }
      }
    } catch (e) {
      if (kDebugMode) print('[Lyrics] Fetch error: $e');
      // Rethrow network errors so outer retry loop can handle them
      if (_isNetworkError(e)) rethrow;
    }
    return false;
  }

  Future<bool> _fetchBySearch({required String track, String? artist, int? durationSec}) async {
    try {
      final query = <String, String>{'track_name': track};
      if (artist != null && artist.isNotEmpty) {
        query['artist_name'] = artist;
      }
      if (durationSec != null && durationSec > 0) {
        query['duration'] = durationSec.toString();
      }

      final uri = Uri.https('lrclib.net', '/api/search', query);
      if (kDebugMode) print('[Lyrics] Search: $uri');

      final response = await _httpClient
          .get(
            uri,
            headers: {
              'User-Agent': 'SpotfyESP/1.0 (https://github.com/user/esp-test)',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(response.body);
      if (data is! List) {
        return false;
      }

      for (final item in data) {
        if (item is! Map) continue;
        final syncedLrc = item['syncedLyrics'] as String?;
        if (syncedLrc == null || syncedLrc.isEmpty) continue;
        final parsed = _parseLrc(syncedLrc);
        if (parsed.isNotEmpty) {
          _lines = parsed;
          if (kDebugMode) {
            print('[Lyrics] Loaded ${_lines.length} lines from search for "$track"');
          }
          return true;
        }
      }
    } catch (e) {
      if (kDebugMode) print('[Lyrics] Search error: $e');
      if (_isNetworkError(e)) rethrow;
    }

    return false;
  }

  Future<bool> _fetchByQ({required String query, int? durationSec}) async {
    try {
      final q = <String, String>{'q': query};
      if (durationSec != null && durationSec > 0) {
        q['duration'] = durationSec.toString();
      }
      final uri = Uri.https('lrclib.net', '/api/search', q);
      if (kDebugMode) print('[Lyrics] Search by Q: $uri');

      final response = await _httpClient
          .get(
            uri,
            headers: {
              'User-Agent': 'SpotfyESP/1.0 (https://github.com/user/esp-test)',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(response.body);
      if (data is! List) return false;

      for (final item in data) {
        if (item is! Map) continue;
        final syncedLrc = item['syncedLyrics'] as String?;
        if (syncedLrc == null || syncedLrc.isEmpty) continue;
        final parsed = _parseLrc(syncedLrc);
        if (parsed.isNotEmpty) {
          _lines = parsed;
          if (kDebugMode) {
            print('[Lyrics] Loaded ${_lines.length} lines from "Q" search for "$query"');
          }
          return true;
        }
      }
    } catch (e) {
      if (kDebugMode) print('[Lyrics] Q Search error: $e');
      if (_isNetworkError(e)) rethrow;
    }
    return false;
  }

  /// Deteksi apakah error adalah masalah jaringan (DNS, timeout, socket).
  /// Error jenis ini layak di-retry, bukan langsung menyerah.
  static bool _isNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('network is unreachable') ||
        msg.contains('timeout') ||
        msg.contains('clientexception');
  }

  String _makeCacheKey(String track, String artist) {
    return '${track.trim().toLowerCase()}|${artist.trim().toLowerCase()}';
  }

  void _saveCache(String key) {
    if (_lines.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lyricsCache[key] = List<LyricLine>.from(_lines);
    _cacheUpdatedAt[key] = nowMs;
    _trimCache();
    _schedulePersistCache();
  }

  Future<void> _ensureStorageReady() async {
    if (_storageReady) return;
    if (_storageInitStarted) {
      while (!_storageReady) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      return;
    }

    _storageInitStarted = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheStorageKey);
      if (raw == null || raw.isEmpty) {
        _storageReady = true;
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _storageReady = true;
        return;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final item in decoded) {
        if (item is! Map) continue;
        final key = item['k']?.toString();
        final updatedAt = item['u'];
        final linesRaw = item['l'];
        if (key == null || updatedAt is! int || linesRaw is! List) continue;
        if (nowMs - updatedAt > _cacheTtlMs) continue;

        final lines = <LyricLine>[];
        for (final row in linesRaw) {
          if (row is! List || row.length != 2) continue;
          final ms = row[0];
          final text = row[1];
          if (ms is int && text is String && text.isNotEmpty) {
            lines.add(LyricLine(ms, text));
          }
        }

        if (lines.isNotEmpty) {
          _lyricsCache[key] = lines;
          _cacheUpdatedAt[key] = updatedAt;
        }
      }

      _trimCache();
    } catch (e) {
      if (kDebugMode) {
        print('[Lyrics] cache load failed: $e');
      }
    } finally {
      _storageReady = true;
    }
  }

  void _trimCache() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final expiredKeys = <String>[];
    for (final entry in _cacheUpdatedAt.entries) {
      if (nowMs - entry.value > _cacheTtlMs) {
        expiredKeys.add(entry.key);
      }
    }
    for (final key in expiredKeys) {
      _cacheUpdatedAt.remove(key);
      _lyricsCache.remove(key);
    }

    if (_lyricsCache.length <= _maxCacheItems) return;

    final sorted = _cacheUpdatedAt.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    while (_lyricsCache.length > _maxCacheItems && sorted.isNotEmpty) {
      final removeKey = sorted.removeAt(0).key;
      _cacheUpdatedAt.remove(removeKey);
      _lyricsCache.remove(removeKey);
    }
  }

  void _schedulePersistCache() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistCache());
    });
  }

  Future<void> _persistCache() async {
    if (!_storageReady) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <Map<String, dynamic>>[];

      final entries = _cacheUpdatedAt.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in entries.take(_maxCacheItems)) {
        final key = entry.key;
        final lines = _lyricsCache[key];
        if (lines == null || lines.isEmpty) continue;

        payload.add({
          'k': key,
          'u': entry.value,
          'l': lines.map((e) => [e.timeMs, e.text]).toList(),
        });
      }

      await prefs.setString(_cacheStorageKey, jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) {
        print('[Lyrics] cache persist failed: $e');
      }
    }
  }

  String _normalizeTrackTitle(String track) {
    var t = track.trim();
    t = t.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    t = t.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '');
    t = t.replaceAll(RegExp(r'\s+-\s+(Remaster(ed)?|Live|Version.*)$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+feat\.?\s+.*$', caseSensitive: false), '');
    // Apple Music sering menambahkan - Single atau - EP
    t = t.replaceAll(RegExp(r'\s+-\s+Single$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+-\s+EP$', caseSensitive: false), '');
    return t.trim();
  }

  String _normalizeArtist(String artist) {
    var a = artist.trim();
    // Apple Music & beberapa layanan sering menggabung artis dengan Koma atau & atau x
    // Lrclib biasanya mewajibkan tepat artis utama atau dibuang sama sekali
    a = a.split(',').first;
    a = a.split('&').first;
    a = a.split(RegExp(r'\s+feat\.?\s+', caseSensitive: false)).first;
    a = a.split(RegExp(r'\s+ft\.?\s+', caseSensitive: false)).first;
    a = a.split(' x ').first;
    return a.trim();
  }

  /// Parse LRC format: `[mm:ss.xx] Lyric text`
  List<LyricLine> _parseLrc(String lrc) {
    final lines = <LyricLine>[];
    // Matches: [01:23.45] or [01:23.456] or [01:23]
    final regex = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\](.*)');

    for (final line in lrc.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final centis = match.group(3);
        int ms = (minutes * 60 + seconds) * 1000;
        if (centis != null) {
          // centis might be 2 or 3 digits
          final centiVal = int.parse(centis.padRight(3, '0').substring(0, 3));
          ms += centiVal;
        }
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          lines.add(LyricLine(ms, text));
        }
      }
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  // ── Seeking ────────────────────────────────────────────────────────────────
  /// Call on every position update (positionMs = current playback position in ms).
  /// Returns [true] if the active line changed (caller should push to ESP32).
  bool updatePosition(int positionMs) {
    if (_lines.isEmpty) return false;

    // Find the last line whose timestamp <= positionMs
    int newIndex = -1;
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].timeMs <= positionMs) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _activeIndex) {
      _activeIndex = newIndex;
      return true; // active line changed
    }
    return false;
  }

  /// Reset lyrics state (call when song changes)
  void clear() {
    _lines = [];
    _activeIndex = -1;
  }
}
