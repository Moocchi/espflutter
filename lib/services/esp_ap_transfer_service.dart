import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EspApStatus {
  final double fsTotalMb;
  final double fsUsedMb;
  final double fsFreeMb;
  final double ramTotalKb;
  final double ramFreeKb;
  final double tempC;

  const EspApStatus({
    required this.fsTotalMb,
    required this.fsUsedMb,
    required this.fsFreeMb,
    required this.ramTotalKb,
    required this.ramFreeKb,
    required this.tempC,
  });

  factory EspApStatus.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return EspApStatus(
      fsTotalMb: toDouble(json['fs_total_mb']),
      fsUsedMb: toDouble(json['fs_used_mb']),
      fsFreeMb: toDouble(json['fs_free_mb']),
      ramTotalKb: toDouble(json['ram_total_kb']),
      ramFreeKb: toDouble(json['ram_free_kb']),
      tempC: toDouble(json['temp_c']),
    );
  }
}

class EspFsEntry {
  final String name;
  final bool isDir;
  final int size;

  const EspFsEntry({
    required this.name,
    required this.isDir,
    required this.size,
  });

  factory EspFsEntry.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return EspFsEntry(
      name: (json['name'] ?? '').toString(),
      isDir: json['is_dir'] == true,
      size: toInt(json['size']),
    );
  }
}

class EspApTransferService {
  final http.Client _client;

  EspApTransferService({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String baseUrl, String path) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalized$path');
  }

  Future<Map<String, dynamic>> _decodeJsonResponse(http.Response response) async {
    final body = response.body;
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Invalid JSON response');
  }

  Future<EspApStatus> getStatus(String baseUrl) async {
    final response = await _client.get(_uri(baseUrl, '/status'));
    if (response.statusCode != 200) {
      throw Exception('Status request failed (${response.statusCode})');
    }
    final json = await _decodeJsonResponse(response);
    return EspApStatus.fromJson(json);
  }

  Future<List<EspFsEntry>> listFiles(String baseUrl) async {
    final response = await _client.get(_uri(baseUrl, '/list'));
    if (response.statusCode != 200) {
      throw Exception('List request failed (${response.statusCode})');
    }
    final json = await _decodeJsonResponse(response);
    final rawFiles = json['files'];
    if (rawFiles is! List) return const [];

    return rawFiles
        .whereType<Map<String, dynamic>>()
        .map(EspFsEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> deletePath(String baseUrl, String path) async {
    final normalized = path.startsWith('/') ? path : '/$path';
    final response = await _client.post(
      _uri(baseUrl, '/delete'),
      body: {'path': normalized},
    );

    if (response.statusCode != 200) {
      String err = 'Delete failed (${response.statusCode})';
      try {
        final json = await _decodeJsonResponse(response);
        if (json['error'] != null) {
          err = 'Delete failed: ${json['error']}';
        }
      } catch (_) {}
      throw Exception(err);
    }
  }

  Future<void> uploadFiles(
    String baseUrl,
    List<PlatformFile> files, {
    String targetDirectory = '/',
  }) async {
    if (files.isEmpty) return;

    final normalizedDir = _normalizeTargetDirectory(targetDirectory);
    final request = http.MultipartRequest('POST', _uri(baseUrl, '/upload'));

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final bytes = await _readBytes(file);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Cannot read file: ${file.name}');
      }

      final remotePath = _buildRemotePath(normalizedDir, file.name);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file$i',
          bytes,
          filename: remotePath,
        ),
      );
    }

    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      throw Exception('Bulk upload failed (${streamed.statusCode})');
    }
  }

  String _normalizeTargetDirectory(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '/') return '/';
    var result = trimmed;
    if (!result.startsWith('/')) result = '/$result';
    if (result.endsWith('/')) result = result.substring(0, result.length - 1);
    return result;
  }

  String _buildRemotePath(String targetDirectory, String filename) {
    final cleanName = filename.trim();
    if (targetDirectory == '/') return '/$cleanName';
    return '$targetDirectory/$cleanName';
  }

  Future<Uint8List?> _readBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return file.bytes;
    }
    if (kIsWeb || file.path == null || file.path!.isEmpty) {
      return null;
    }
    return File(file.path!).readAsBytes();
  }
}
