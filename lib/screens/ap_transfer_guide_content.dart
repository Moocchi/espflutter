import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/esp_ap_transfer_service.dart';
import '../widgets/app_toast.dart';

class ApTransferGuideContent extends StatefulWidget {
  final bool showMenuButton;
  final VoidCallback? onMenuTap;

  const ApTransferGuideContent({
    super.key,
    required this.showMenuButton,
    this.onMenuTap,
  });

  @override
  State<ApTransferGuideContent> createState() => _ApTransferGuideContentState();
}

class _ApTransferGuideContentState extends State<ApTransferGuideContent> {
  final EspApTransferService _service = EspApTransferService();
  static const List<String> _baseCandidates = [
    'http://192.168.4.1',
    'http://ganci.local',
  ];

  String _lastConnectedBase = _baseCandidates.first;
  final TextEditingController _targetDirCtrl = TextEditingController(text: '/');
  String? _preferredInitialDirectory;

  EspApStatus? _status;
  List<EspFsEntry> _entries = const [];
  List<PlatformFile> _selectedFiles = const [];
  bool _selectedFromFolder = false;
  String? _selectedFolderName;
  bool _loadingStatus = false;
  bool _loadingList = false;
  bool _uploading = false;
  bool _isConnected = false;
  bool _hasFetchedListOnce = false;

  @override
  void initState() {
    super.initState();
    _prepareInitialDirectory();
  }

  @override
  void dispose() {
    _targetDirCtrl.dispose();
    super.dispose();
  }

  void _toast(String message, {bool isError = false}) {
    AppToast.show(context, message, isError: isError);
  }

  Future<T> _withBaseFallback<T>(Future<T> Function(String baseUrl) action) async {
    Object? lastError;
    for (final base in _baseCandidates) {
      try {
        final result = await action(base);
        if (mounted && _lastConnectedBase != base) {
          setState(() => _lastConnectedBase = base);
        }
        return result;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError?.toString() ?? 'Koneksi ke ESP32 gagal.');
  }

  Future<void> _prepareInitialDirectory() async {
    if (kIsWeb) return;

    String? candidate;
    if (Platform.isAndroid) {
      candidate = '/storage/emulated/0/Download/image2cpp';
      try {
        await Directory(candidate).create(recursive: true);
      } catch (_) {}
    } else {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        final image2cpp =
            Directory('${downloadsDir.path}${Platform.pathSeparator}image2cpp');
        candidate = image2cpp.path;
        try {
          await image2cpp.create(recursive: true);
        } catch (_) {}
      }
    }

    if (!mounted || candidate == null) return;
    setState(() => _preferredInitialDirectory = candidate);
  }

  Future<bool> _refreshStatus({bool showToast = true}) async {
    setState(() => _loadingStatus = true);
    try {
      final status = await _withBaseFallback(_service.getStatus);
      if (!mounted) return false;
      setState(() => _status = status);
      if (showToast) {
        _toast('Status OK');
      }
      return true;
    } catch (e) {
      if (showToast) {
        _toast('Status gagal', isError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<bool> _refreshList({bool showToast = true}) async {
    setState(() => _loadingList = true);
    try {
      final entries = await _withBaseFallback(_service.listFiles);
      if (!mounted) return false;
      entries.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _entries = entries;
        _hasFetchedListOnce = true;
      });
      if (showToast) {
        _toast('List OK');
      }
      return true;
    } catch (e) {
      if (showToast) {
        _toast('List gagal', isError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _refreshAll() async {
    final statusOk = await _refreshStatus(showToast: false);
    final listOk = await _refreshList(showToast: false);
    if (statusOk && listOk) {
      if (mounted) setState(() => _isConnected = true);
      _toast('Terhubung ($_lastConnectedBase)');
    } else {
      if (mounted) setState(() => _isConnected = false);
      _toast('Gagal koneksi ESP32', isError: true);
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['bin', 'qoi', 'gif'],
      initialDirectory: _preferredInitialDirectory,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _selectedFiles = result.files;
      _selectedFromFolder = false;
      _selectedFolderName = null;
    });
  }

  Future<void> _pickFolderFiles() async {
    final folderPath = await _pickFolderPath();

    if (folderPath == null || folderPath.isEmpty) return;

    final files = await _collectUploadableFilesFromFolder(folderPath);
    if (!mounted) return;

    if (files.isEmpty) {
      _toast('Folder tidak berisi .qoi/.gif/.bin', isError: true);
      return;
    }

    final normalized = folderPath.replaceAll('\\', '/');
    final parts = normalized.split('/');
    final folderName = parts.isNotEmpty ? parts.last : normalized;

    setState(() {
      _selectedFiles = files;
      _selectedFromFolder = true;
      _selectedFolderName = folderName;
    });
    _toast('Folder $folderName dipilih (${files.length} file)');
  }

  Future<String?> _pickFolderPath() async {
    if (!kIsWeb && Platform.isAndroid) {
      final granted = await _ensureAndroidFileAccessPermission();
      if (!granted) {
        _toast('Izin akses file dibutuhkan', isError: true);
        return null;
      }
      return _pickFolderPathCustomAndroid();
    }

    return FilePicker.platform.getDirectoryPath(
      initialDirectory: _preferredInitialDirectory,
      dialogTitle: 'Pilih folder berisi .qoi/.gif/.bin',
    );
  }

  Future<bool> _ensureAndroidFileAccessPermission() async {
    final manageStatus = await Permission.manageExternalStorage.status;
    if (manageStatus.isGranted) return true;

    final manageRequest = await Permission.manageExternalStorage.request();
    if (manageRequest.isGranted) return true;

    if (manageRequest.isPermanentlyDenied || manageRequest.isRestricted) {
      if (mounted) {
        _toast('Izin file ditolak. Buka pengaturan aplikasi');
      }
      await openAppSettings();
      return false;
    }

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;

    final storageRequest = await Permission.storage.request();
    if (storageRequest.isGranted) return true;

    if (mounted) {
      _toast('Akses file belum diizinkan, arahkan ke pengaturan');
    }
    await openAppSettings();
    return false;
  }

  Future<String?> _pickFolderPathCustomAndroid() async {
    final root = Directory('/storage/emulated/0');
    final fallback = _preferredInitialDirectory ?? root.path;
    Directory currentDir = Directory(fallback);
    if (!await currentDir.exists()) {
      currentDir = root;
    }

    if (!mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            List<Directory> dirs = [];
            try {
              dirs = currentDir
                  .listSync(followLinks: false)
                  .whereType<Directory>()
                  .toList()
                ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
            } catch (_) {
              dirs = [];
            }

            final canGoUp = currentDir.path != root.path;

            return AlertDialog(
              title: const Text('Pilih Folder Upload'),
              content: SizedBox(
                width: 460,
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F5FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC9C3FF)),
                      ),
                      child: Text(
                        currentDir.path,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4C42CF),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: canGoUp
                              ? () {
                                  final parent = currentDir.parent;
                                  setDialogState(() => currentDir = parent);
                                }
                              : null,
                          icon: const Icon(Icons.arrow_upward_rounded),
                          label: const Text('Naik'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            setDialogState(() => currentDir = Directory(root.path));
                          },
                          icon: const Icon(Icons.home_rounded),
                          label: const Text('Root'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: dirs.isEmpty
                          ? const Center(
                              child: Text(
                                'Folder kosong atau tidak bisa diakses.',
                                style: TextStyle(color: Color(0xFF5F6680)),
                              ),
                            )
                          : ListView.builder(
                              itemCount: dirs.length,
                              itemBuilder: (context, index) {
                                final dir = dirs[index];
                                final name = dir.path.split('/').last;
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.folder_rounded,
                                    color: Color(0xFF6252E7),
                                  ),
                                  title: Text(name),
                                  onTap: () {
                                    setDialogState(() => currentDir = dir);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(currentDir.path),
                  child: const Text('Gunakan Folder Ini'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<PlatformFile>> _collectUploadableFilesFromFolder(
    String folderPath,
  ) async {
    final directory = Directory(folderPath);
    if (!await directory.exists()) return const [];

    const allowedExt = {'qoi', 'gif', 'bin'};
    final List<PlatformFile> selected = [];

    await for (final entity in directory.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      final dot = path.lastIndexOf('.');
      if (dot < 0 || dot == path.length - 1) continue;

      final ext = path.substring(dot + 1).toLowerCase();
      if (!allowedExt.contains(ext)) continue;

      final fileName = path.split(RegExp(r'[\\/]')).last;
      final length = await entity.length();
      selected.add(
        PlatformFile(
          name: fileName,
          size: length,
          path: path,
        ),
      );
    }

    return selected;
  }

  Future<void> _uploadSelected() async {
    if (_selectedFiles.isEmpty) {
      _toast('Pilih file dulu', isError: true);
      return;
    }

    setState(() => _uploading = true);
    final effectiveTargetDir = _buildEffectiveTargetDirectory();
    try {
      await _service.uploadFiles(
        _lastConnectedBase,
        _selectedFiles,
        targetDirectory: effectiveTargetDir,
      );
      if (!mounted) return;
      _toast('Upload berhasil (${_selectedFiles.length})');
      setState(() {
        _selectedFiles = const [];
        _selectedFromFolder = false;
        _selectedFolderName = null;
      });
      await _refreshAll();
    } catch (e) {
      try {
        await _withBaseFallback((base) => _service.uploadFiles(
              base,
              _selectedFiles,
            targetDirectory: effectiveTargetDir,
            ));
        if (!mounted) return;
        _toast('Upload berhasil (${_selectedFiles.length})');
        setState(() {
          _selectedFiles = const [];
          _selectedFromFolder = false;
          _selectedFolderName = null;
        });
        await _refreshAll();
      } catch (fallbackError) {
        _toast('Upload gagal', isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _buildEffectiveTargetDirectory() {
    final rawTarget = _targetDirCtrl.text.trim();
    final base = rawTarget.isEmpty ? '/' : rawTarget;
    if (!_selectedFromFolder || _selectedFolderName == null || _selectedFolderName!.isEmpty) {
      return base;
    }

    final folder = _selectedFolderName!.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    String normalized = base;
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized.endsWith('/')) normalized = normalized.substring(0, normalized.length - 1);
    if (normalized.isEmpty) normalized = '/';

    if (normalized == '/') return '/$folder';
    return '$normalized/$folder';
  }

  Future<void> _deleteEntry(EspFsEntry entry) async {
    try {
      await _withBaseFallback((base) => _service.deletePath(base, entry.name));
      _toast('Delete berhasil');
      await _refreshAll();
    } catch (e) {
      _toast('Delete gagal', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GuideHeaderSection(
          showMenuButton: widget.showMenuButton,
          onMenuTap: widget.onMenuTap,
          title: 'Upload Media',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _GuideStepCard(
            title: 'Koneksi AP',
            outlined: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _GuideTextBlock(
                  lines: [
                    '1) Di device ESP32 pilih menu Up Media sampai mode AP aktif.',
                    '2) Di HP sambungkan Wi-Fi ke SSID ESP32-Media-App (password 12345678).',
                    '3) Base URL otomatis hardcoded: 192.168.4.1 lalu fallback ke ganci.local.',
                    '4) Upload bisa pilih file/folder berisi .qoi/.gif/.bin dari Download/image2cpp.',
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F5FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFC9C3FF)),
                  ),
                  child: Text(
                    'Endpoint aktif: $_lastConnectedBase',
                    style: const TextStyle(
                      color: Color(0xFF4C42CF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _loadingStatus || _loadingList ? null : _refreshAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6252E7),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFF6252E7).withValues(alpha: 0.75),
                        disabledForegroundColor: Colors.white,
                      ),
                      icon: _loadingStatus || _loadingList
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _isConnected
                                  ? Icons.refresh_rounded
                                  : Icons.wifi_find_rounded,
                            ),
                      label: Text(
                        _loadingStatus || _loadingList
                            ? 'Checking...'
                            : (_isConnected ? 'Refresh' : 'Test Connection'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _GuideStepCard(
            title: 'Status ESP32',
            outlined: true,
            child: _status == null
                ? const Text(
                    'Belum ambil status. Tekan Test Connection.',
                    style: TextStyle(color: Color(0xFF5F6680), fontSize: 13),
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetricChip(label: 'FS Total', value: '${_status!.fsTotalMb.toStringAsFixed(2)} MB'),
                      _MetricChip(label: 'FS Used', value: '${_status!.fsUsedMb.toStringAsFixed(2)} MB'),
                      _MetricChip(label: 'FS Free', value: '${_status!.fsFreeMb.toStringAsFixed(2)} MB'),
                      _MetricChip(label: 'RAM Total', value: '${_status!.ramTotalKb.toStringAsFixed(2)} KB'),
                      _MetricChip(label: 'RAM Free', value: '${_status!.ramFreeKb.toStringAsFixed(2)} KB'),
                      _MetricChip(label: 'Temp ESP32', value: '${_status!.tempC.toStringAsFixed(1)} C'),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _GuideStepCard(
            title: 'Upload File ke ESP32',
            outlined: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _targetDirCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target Directory (LittleFS path)',
                    hintText: '/media',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _uploading ? null : _pickFiles,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: const Text('Pilih File'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickFolderFiles,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Pilih Folder'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _uploading ? null : _uploadSelected,
                      icon: _uploading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_rounded),
                      label: Text(_uploading
                          ? 'Uploading...'
                          : 'Upload via POST /upload'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_selectedFiles.isEmpty)
                  const Text(
                    'Belum ada file dipilih (.qoi/.gif/.bin).',
                    style: TextStyle(color: Color(0xFF5F6680), fontSize: 13),
                  )
                else if (_selectedFromFolder)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F5FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFC9C3FF)),
                    ),
                    child: Text(
                      'Folder ${_selectedFolderName ?? '-'} dipilih (${_selectedFiles.length} file)',
                      style: const TextStyle(
                        color: Color(0xFF3F4670),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _selectedFiles
                        .map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '- ${f.name} (${_formatBytes(f.size)})',
                              style: const TextStyle(
                                color: Color(0xFF3F4670),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _GuideStepCard(
            title: 'File List dari ESP32',
            outlined: true,
            child: _loadingList
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _entries.isEmpty
                    ? Text(
                        _hasFetchedListOnce
                            ? 'Storage ESP32 kosong. Upload file .qoi/.bin terlebih dahulu.'
                            : 'Belum ambil list. Tekan Test Connection dulu.',
                        style: const TextStyle(color: Color(0xFF5F6680), fontSize: 13),
                      )
                    : Column(
                        children: _entries
                            .map(
                              (entry) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  entry.isDir
                                      ? Icons.folder_rounded
                                      : Icons.insert_drive_file_rounded,
                                  color: const Color(0xFF6252E7),
                                ),
                                title: Text(
                                  entry.name,
                                  style: const TextStyle(
                                    color: Color(0xFF3F4670),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  entry.isDir
                                      ? 'Directory'
                                      : _formatBytes(entry.size),
                                  style: const TextStyle(color: Color(0xFF5F6680)),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFB42318),
                                  ),
                                  onPressed: () => _deleteEntry(entry),
                                ),
                              ),
                            )
                            .toList(),
                      ),
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: double.infinity,
          child: _GuideStepCard(
            title: 'Kontrak Firmware yang Dipakai (hasil analisa ganci.ino)',
            outlined: true,
            child: _GuideLabeledList(
              items: [
                _GuideItem(title: 'GET /status', description: 'Balikkan fs_total_mb, fs_used_mb, fs_free_mb, ram_total_kb, ram_free_kb, temp_c.'),
                _GuideItem(title: 'GET /list', description: 'Balikkan array files: name, is_dir, size dari root LittleFS.'),
                _GuideItem(title: 'POST /delete', description: 'Wajib body arg path, akan remove file atau rmdir folder.'),
                _GuideItem(title: 'POST /upload', description: 'Multipart upload; nama file dipakai sebagai path target (contoh /media/a.bin).'),
                _GuideItem(title: 'AP Config', description: 'SSID ESP32-Media-App, password 12345678, host ganci.local, IP 192.168.4.1.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFC9C3FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6D7385),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF4C42CF),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideHeaderSection extends StatelessWidget {
  final bool showMenuButton;
  final VoidCallback? onMenuTap;
  final String title;

  const _GuideHeaderSection({
    required this.showMenuButton,
    this.onMenuTap,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showMenuButton)
          IconButton(
            onPressed: onMenuTap ?? () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
            color: const Color(0xFF5B6274),
          )
        else
          const Icon(Icons.menu_rounded, color: Color(0xFF5B6274)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF2F3445),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuideStepCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool outlined;

  const _GuideStepCard({
    required this.title,
    required this.child,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = outlined
      ? const Color(0xFF6252E7).withValues(alpha: 0.32)
        : const Color(0xFF1A3048);
    return Container(
      decoration: BoxDecoration(
        color: outlined ? const Color(0xFFFDFDFF) : const Color(0xFF0E1E2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: outlined
            ? [
                BoxShadow(
                  color: const Color(0xFF6252E7).withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: outlined ? const Color(0xFFF7F5FF) : Colors.transparent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: outlined ? const Color(0xFF4C42CF) : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _GuideTextBlock extends StatelessWidget {
  final List<String> lines;

  const _GuideTextBlock({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                line,
                style: const TextStyle(
                  color: Color(0xFF5F6680),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _GuideLabeledList extends StatelessWidget {
  final List<_GuideItem> items;

  const _GuideLabeledList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6252E7),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${item.title}: ',
                            style: const TextStyle(
                              color: Color(0xFF3F4670),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          TextSpan(
                            text: item.description,
                            style: const TextStyle(
                              color: Color(0xFF5F6680),
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _GuideItem {
  final String title;
  final String description;

  const _GuideItem({required this.title, required this.description});
}
