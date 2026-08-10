import 'dart:io';

import 'package:flutter/material.dart';
import '../main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';
import '../services/esp_ap_transfer_service.dart';
import '../esp_bridge/services/ble_service.dart';
import '../widgets/app_toast.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class ApTransferGuideContent extends StatefulWidget {
  final bool showMenuButton;
  final VoidCallback? onMenuTap;
  final VoidCallback? onNavigateToSettings;

  const ApTransferGuideContent({
    super.key,
    required this.showMenuButton,
    this.onMenuTap,
    this.onNavigateToSettings,
  });

  @override
  State<ApTransferGuideContent> createState() => _ApTransferGuideContentState();
}

class _ApTransferGuideContentState extends State<ApTransferGuideContent> {
  final TextEditingController _targetDirCtrl = TextEditingController(text: '/');
  String? _preferredInitialDirectory;
  StreamSubscription<BleStatus>? _bleSub;

  EspApStatus? _status;
  List<EspFsEntry> _entries = const [];
  List<PlatformFile> _selectedFiles = const [];
  bool _selectedFromFolder = false;
  String? _selectedFolderName;
  bool _loadingStatus = false;
  bool _loadingList = false;
  bool _uploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';
  bool _isConnected = false;
  bool _hasFetchedListOnce = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _prepareInitialDirectory();
    _bleSub = BleService().statusStream.listen((status) {
      if (mounted) {
        final wasConnected = _isConnected;
        setState(() {
          _isConnected = (status == BleStatus.connected);
        });
        if (status == BleStatus.connected && !wasConnected) {
          _refreshAll(showToast: false);
        }
      }
    });
    _isConnected = (BleService().currentStatus == BleStatus.connected);
    if (_isConnected) {
      _refreshAll(showToast: false);
    } else {
      BleService().scanAndConnect();
    }
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _targetDirCtrl.dispose();
    super.dispose();
  }

  void _toast(String message, {bool isError = false}) {
    AppToast.show(context, message, isError: isError);
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
      final ble = BleService();
      // Only check current status - do NOT call ensureConnectedAndReady here
      if (ble.currentStatus == BleStatus.connected) {
        // Try to get sysInfo but don't fail if it's unavailable
        final sysJson = await ble.fetchSysInfo();
        if (sysJson != null && mounted) {
          setState(() {
            _status = EspApStatus.fromJson(sysJson);
            _isConnected = true;
          });
          if (showToast) _toast('Status BLE OK');
          return true;
        }
        // SysInfo unavailable but BLE IS connected - still mark as connected
        if (mounted) {
          setState(() => _isConnected = true);
        }
        if (showToast) _toast('BLE Terhubung (stats tidak tersedia)');
        return true;
      }
      if (mounted) setState(() => _isConnected = false);
      if (showToast) _toast('BLE tidak terhubung', isError: true);
      return false;
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
      final ble = BleService();
      if (ble.currentStatus == BleStatus.connected) {
        if (mounted) {
          final bleList = await ble.listFiles();
          setState(() {
            _entries = bleList;
            _hasFetchedListOnce = true;
            _isConnected = true;
          });
        }
        if (showToast) _toast('Daftar file diperbarui');
        return true;
      }
      if (mounted) setState(() => _isConnected = false);
      if (showToast) _toast('BLE tidak terhubung', isError: true);
      return false;
    } catch (e) {
      if (showToast) {
        _toast('List gagal', isError: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _refreshAll({bool showToast = true}) async {
    final ble = BleService();
    // If not connected, try to connect once
    if (ble.currentStatus != BleStatus.connected) {
      await ble.scanAndConnect();
    }
    final statusOk = await _refreshStatus(showToast: false);
    if (statusOk) {
      if (mounted) setState(() => _isConnected = true);
      if (showToast) {
        _toast('Terhubung via BLE');
      }
    } else {
      if (mounted) setState(() => _isConnected = false);
      if (showToast) _toast('Gagal koneksi BLE ESP32', isError: true);
    }
  }

  Future<void> _pickFiles() async {
    List<PlatformFile>? pickedFiles;

    if (!kIsWeb && Platform.isAndroid) {
      final granted = await _ensureAndroidFileAccessPermission();
      if (!granted) {
        _toast('Izin akses file dibutuhkan', isError: true);
        return;
      }
      pickedFiles = await _pickFilesCustomAndroid();
    } else {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['bin', 'qoi', 'gif'],
        initialDirectory: _preferredInitialDirectory,
      );
      pickedFiles = result?.files;
    }

    if (pickedFiles == null || pickedFiles.isEmpty) return;
    
    setState(() {
      _selectedFiles = pickedFiles!;
      _selectedFromFolder = false;
      _selectedFolderName = null;
    });
  }

  Future<List<PlatformFile>?> _pickFilesCustomAndroid() async {
    final root = Directory('/storage/emulated/0');
    final fallback = _preferredInitialDirectory ?? root.path;
    Directory currentDir = Directory(fallback);
    if (!await currentDir.exists()) {
      currentDir = root;
    }

    if (!mounted) return null;

    Set<String> selectedPaths = {};

    return showDialog<List<PlatformFile>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            List<FileSystemEntity> entities = [];
            try {
              entities = currentDir
                  .listSync(followLinks: false)
                  .where((e) {
                    if (e is Directory) return true;
                    if (e is File) {
                      final path = e.path.toLowerCase();
                      if (path.endsWith('.qoi') || path.endsWith('.bin') || path.endsWith('.gif')) return true;
                    }
                    return false;
                  })
                  .toList()
                ..sort((a, b) {
                  if (a is Directory && b is File) return -1;
                  if (a is File && b is Directory) return 1;
                  return a.path.toLowerCase().compareTo(b.path.toLowerCase());
                });
            } catch (_) {
              entities = [];
            }

            final canGoUp = currentDir.path != root.path;

            return Theme(
              data: Theme.of(context).copyWith(
                checkboxTheme: CheckboxThemeData(
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return Theme.of(context).colorScheme.primary;
                    return Colors.transparent;
                  }),
                ),
              ),
              child: AlertDialog(
                backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
                surfaceTintColor: Colors.transparent,
                title: const Text('Pilih File/Folder (.qoi/.bin/.gif)', style: TextStyle(color: Color(0xFF3F4670), fontSize: 18, fontWeight: FontWeight.bold)),
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
                      child: entities.isEmpty
                          ? const Center(
                              child: Text(
                                'Kosong atau tidak ada file QOI/BIN/GIF.',
                                style: TextStyle(color: Color(0xFF5F6680)),
                              ),
                            )
                          : ListView.builder(
                              itemCount: entities.length,
                              itemBuilder: (context, index) {
                                final entity = entities[index];
                                final name = entity.path.split('/').last;
                                final isDir = entity is Directory;
                                
                                if (isDir) {
                                  final isSelected = selectedPaths.contains(entity.path);
                                  final folderSize = _getFolderSizeSync(entity as Directory);
                                  final folderSizeStr = _formatBytes(folderSize);
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.folder_rounded, color: Color(0xFF6252E7)),
                                    title: Text(name),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(folderSizeStr, style: const TextStyle(color: Color(0xFF5F6680), fontSize: 12)),
                                        const SizedBox(width: 8),
                                        Checkbox(
                                          value: isSelected,
                                          onChanged: (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                selectedPaths.add(entity.path);
                                              } else {
                                                selectedPaths.remove(entity.path);
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      setDialogState(() => currentDir = entity as Directory);
                                    },
                                  );
                                } else {
                                  final isSelected = selectedPaths.contains(entity.path);
                                  final sizeStr = _formatBytes((entity as File).lengthSync());
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF5F6680)),
                                    title: Text(name),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(sizeStr, style: const TextStyle(color: Color(0xFF5F6680), fontSize: 12)),
                                        const SizedBox(width: 8),
                                        Checkbox(
                                          value: isSelected,
                                          onChanged: (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                selectedPaths.add(entity.path);
                                              } else {
                                                selectedPaths.remove(entity.path);
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      setDialogState(() {
                                        if (!isSelected) {
                                          selectedPaths.add(entity.path);
                                        } else {
                                          selectedPaths.remove(entity.path);
                                        }
                                      });
                                    },
                                  );
                                }
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
                  onPressed: selectedPaths.isEmpty 
                    ? null 
                    : () async {
                        List<PlatformFile> result = [];
                        for (String path in selectedPaths) {
                          if (FileSystemEntity.isDirectorySync(path)) {
                             final dir = Directory(path);
                             final folderName = dir.path.split('/').last;
                             try {
                               final files = dir.listSync();
                               for (final f in files) {
                                 if (f is File) {
                                   final fName = f.path.split('/').last;
                                   final ext = fName.split('.').last.toLowerCase();
                                   if (ext == 'qoi' || ext == 'bin' || ext == 'gif') {
                                     result.add(PlatformFile(
                                       name: '$folderName/$fName',
                                       size: f.lengthSync(),
                                       path: f.path,
                                     ));
                                   }
                                 }
                               }
                             } catch (_) {}
                          } else if (FileSystemEntity.isFileSync(path)) {
                             final f = File(path);
                             final fName = f.path.split('/').last;
                             result.add(PlatformFile(
                               name: fName,
                               size: f.lengthSync(),
                               path: f.path,
                             ));
                          }
                        }
                        Navigator.of(dialogContext).pop(result);
                      },
                  child: Text('Pilih (${selectedPaths.length})'),
                ),
              ],
            ));
          },
        );
      },
    );
  }

  Future<void> _pickFolderFiles() async {
    final folderPath = await _pickFolderPath();

    if (folderPath == null || folderPath.isEmpty) return;

    final files = await _collectUploadableFilesFromFolder(folderPath);
    if (!mounted) return;

    if (files.isEmpty) {
      _toast('Folder tidak berisi .qoi/.bin/.gif', isError: true);
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
      dialogTitle: 'Pilih folder berisi .qoi/.bin/.gif',
    );
  }

  Future<bool> _ensureAndroidFileAccessPermission() async {
    final manageStatus = await Permission.manageExternalStorage.status;
    if (manageStatus.isGranted) return true;

    final manageRequest = await Permission.manageExternalStorage.request();
    if (manageRequest.isGranted) return true;

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;

    final storageRequest = await Permission.storage.request();
    if (storageRequest.isGranted) return true;

    if (mounted) {
      final bool? openSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Perlu Akses File'),
          content: const Text(
            'Aplikasi membutuhkan izin untuk membaca dan mengupload media (.qoi/.bin/.gif) dari penyimpanan Anda.\n\n'
            'Silakan izinkan akses file di pengaturan aplikasi (Perizinan -> File dan media).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Tutup'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Buka Settings'),
            ),
          ],
        ),
      );

      if (openSettings == true) {
        await openAppSettings();
      }
    }
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

    const allowedExt = {'qoi', 'bin', 'gif'};
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

    if (_status != null) {
      int totalBytes = 0;
      for (final f in _selectedFiles) {
        totalBytes += f.size;
      }
      double totalMb = totalBytes / (1024 * 1024);
      if (totalMb > _status!.fsFreeMb) {
        _toast('Gagal: Butuh ${totalMb.toStringAsFixed(1)}MB, sisa memori ESP32 hanya ${_status!.fsFreeMb.toStringAsFixed(1)}MB', isError: true);
        return;
      }
    }

    setState(() {
      _uploading = true;
      _uploadProgress = 0.0;
      _uploadStatus = 'Mempersiapkan...';
    });
    final effectiveTargetDir = _buildEffectiveTargetDirectory();
    try {
      final ble = BleService();
      if (ble.currentStatus == BleStatus.connected) {
        _toast('Mengirim file via BLE...');
        await ble.uploadFilesBle(
          _selectedFiles,
          targetDirectory: effectiveTargetDir,
          onProgress: (current, total, progress) {
            if (mounted) {
              setState(() {
                _uploadProgress = progress;
                _uploadStatus = 'File $current dari $total (${(progress * 100).toStringAsFixed(0)}%)';
              });
            }
          },
        );
        if (!mounted) return;
        _toast('Upload BLE berhasil (${_selectedFiles.length})');
        Provider.of<AppState>(context, listen: false).incrementFilesSynced(_selectedFiles.length);
        setState(() {
          _selectedFiles = const [];
          _selectedFromFolder = false;
          _selectedFolderName = null;
        });
        await _refreshAll(showToast: false);
      } else {
        _toast('Gagal: Bluetooth BLE tidak terhubung', isError: true);
      }
    } catch (e) {
      if (e.toString().contains('Dibatalkan')) {
        _toast('Upload dibatalkan');
      } else {
        _toast('Upload gagal: $e', isError: true);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus File?'),
        content: Text('Yakin ingin menghapus ${entry.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Hapus', style: TextStyle(color: GanciColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    
    setState(() => _loadingList = true);
    final success = await BleService().deleteFile(entry.name);
    if (success) {
      _toast('File dihapus');
      await _refreshList(showToast: false);
      await _refreshStatus(showToast: false);
    } else {
      _toast('Gagal menghapus file', isError: true);
      setState(() => _loadingList = false);
    }
  }

  Future<void> _deleteAll() async {
    _toast('Hapus semua file sekaligus belum didukung via BLE.');
  }

  Color _tempColor(double tempC) {
    if (tempC < 50) return GanciColors.success;
    if (tempC < 70) return GanciColors.warning;
    return GanciColors.error;
  }

  Widget _buildUsageBar(
    GanciTheme t, {
    required IconData icon,
    required String label,
    required double used,
    required double total,
    required String unit,
    required Color color,
  }) {
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final pct = (ratio * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 15),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(color: t.outline, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                ],
              ),
              Text('$pct% Used', style: TextStyle(color: t.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: t.surfaceBright,
              color: color,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Used: ${used.toStringAsFixed(unit == "MB" ? 2 : 0)} $unit', style: TextStyle(color: t.textSecondary, fontSize: 11, fontFamily: 'JetBrains Mono')),
              Text('Total: ${total.toStringAsFixed(unit == "MB" ? 2 : 0)} $unit', style: TextStyle(color: t.textSecondary, fontSize: 11, fontFamily: 'JetBrains Mono')),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ApHeaderSection(
          showMenuButton: widget.showMenuButton,
          onMenuTap: widget.onMenuTap,
          title: 'Transfer File BLE',
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 768;
            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: _buildLeftColumn(t),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: _buildRightColumn(t),
                  ),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLeftColumn(t),
                  const SizedBox(height: 24),
                  _buildRightColumn(t),
                ],
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildLeftColumn(GanciTheme t) {
    final bleConnected = BleService().currentStatus == BleStatus.connected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connection Card (Only show when disconnected)
        if (!bleConnected) ...[
          _GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: t.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bluetooth_disabled_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text('BLE Belum Terhubung', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Hubungkan perangkat ESP32 Anda lewat Bluetooth Low Energy (BLE) untuk mulai mentransfer file dan melihat statistik memori.', style: TextStyle(color: t.textSecondary, fontSize: 14, fontFamily: 'Inter')),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    if (widget.onNavigateToSettings != null) {
                      widget.onNavigateToSettings!();
                    }
                  },
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('Buka Pengaturan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Inter')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // ── ESP32 Status Dashboard ──────────────────────────────────────
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with title + connection badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.developer_board_rounded, color: t.primary, size: 22),
                      const SizedBox(width: 8),
                      Text('ESP32 Status', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (_isConnected ? GanciColors.success : GanciColors.error).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (_isConnected ? GanciColors.success : GanciColors.error).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                            color: _isConnected ? GanciColors.success : GanciColors.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isConnected ? GanciColors.success : GanciColors.error).withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isConnected ? 'Connected' : 'Disconnected',
                          style: TextStyle(
                            color: _isConnected ? GanciColors.success : GanciColors.error,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // BLE status row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: t.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.glassBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bluetooth_rounded, color: _isConnected ? GanciColors.success : t.outline, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        BleService().currentStatus == BleStatus.connected ? 'Bluetooth Low Energy Connected' : 'BLE Disconnected',
                        style: TextStyle(color: t.textSecondary, fontSize: 13, fontFamily: 'JetBrains Mono'),
                      ),
                    ),
                    Icon(
                      _isConnected ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: _isConnected ? GanciColors.success : GanciColors.error,
                      size: 18,
                    ),
                  ],
                ),
              ),

              // Stats section - only if connected + data available
              if (_status != null) ...[
                const SizedBox(height: 16),
                // Temperature + RAM Heap row
                Row(
                  children: [
                    // Temperature card
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: t.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.glassBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.thermostat_rounded, color: _tempColor(_status!.tempC), size: 16),
                                const SizedBox(width: 6),
                                Text('Suhu', style: TextStyle(color: t.outline, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_status!.tempC.toStringAsFixed(1)}°C',
                              style: TextStyle(color: t.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'JetBrains Mono'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _status!.tempC < 50 ? 'Normal' : _status!.tempC < 70 ? 'Warm' : 'Hot!',
                              style: TextStyle(color: _tempColor(_status!.tempC), fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Free Heap card
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: t.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.glassBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.memory_rounded, color: t.primary, size: 16),
                                const SizedBox(width: 6),
                                Text('Free Heap', style: TextStyle(color: t.outline, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_status!.ramFreeKb.toStringAsFixed(0)} KB',
                              style: TextStyle(color: t.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'JetBrains Mono'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'of ${_status!.ramTotalKb.toStringAsFixed(0)} KB total',
                              style: TextStyle(color: t.outline, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // RAM Usage Bar
                const SizedBox(height: 12),
                _buildUsageBar(
                  t,
                  icon: Icons.memory_rounded,
                  label: 'RAM',
                  used: _status!.ramTotalKb - _status!.ramFreeKb,
                  total: _status!.ramTotalKb,
                  unit: 'KB',
                  color: t.primary,
                ),

                // SD Card Storage Bar
                const SizedBox(height: 10),
                _buildUsageBar(
                  t,
                  icon: Icons.sd_storage_rounded,
                  label: 'SD Card',
                  used: _status!.fsUsedMb,
                  total: _status!.fsTotalMb,
                  unit: 'MB',
                  color: const Color(0xFF7C6DD8),
                ),
              ],

              // No stats available message
              if (_isConnected && _status == null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: GanciColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: GanciColors.warning.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: GanciColors.warning, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Statistik tidak tersedia di mode ini',
                          style: TextStyle(color: t.textSecondary, fontSize: 12, fontFamily: 'Inter'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              // Refresh button
              ElevatedButton.icon(
                onPressed: _loadingStatus || _loadingList ? null : _refreshAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.surfaceContainerHigh,
                  foregroundColor: t.primary,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: _loadingStatus || _loadingList
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
                label: Text(_loadingStatus || _loadingList ? 'Checking...' : 'Refresh / Test', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightColumn(GanciTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Upload Section
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.outlineVariant, style: BorderStyle.solid, width: 2), // dashed not natively supported without package, using solid
            boxShadow: [
              BoxShadow(
                color: t.primary.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: t.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.cloud_upload_outlined, color: t.primary, size: 32),
              ),
              const SizedBox(height: 16),
              Text('Upload Files to ESP32', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
              const SizedBox(height: 8),
              Text('Select pre-processed .h, .bin, or raw image files to transfer directly to SPIFFS storage.', textAlign: TextAlign.center, style: TextStyle(color: t.textSecondary, fontSize: 14)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickFiles,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: t.outlineVariant),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Pick File', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _uploading ? null : _uploadSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 2,
                      ),
                      icon: _uploading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                      label: Text(_uploading ? 'Uploading...' : 'Upload Now', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              if (_uploading) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _uploadStatus,
                      style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    TextButton(
                      onPressed: () {
                        BleService().cancelUpload();
                        setState(() {
                          _selectedFiles = const [];
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Batal', style: TextStyle(color: GanciColors.error, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    minHeight: 12,
                    backgroundColor: t.outlineVariant.withOpacity(0.5),
                    color: t.primary,
                  ),
                ),
              ],
              if (_selectedFiles.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildPreviewExpandedUI(t),
              ]
            ],
          ),
        ),
        const SizedBox(height: 24),
        // File List Section
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: t.primary.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.surfaceContainerLow,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border(bottom: BorderSide(color: t.outlineVariant.withOpacity(0.3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_open_outlined, color: t.outline, size: 20),
                        const SizedBox(width: 8),
                        Text('Remote SPIFFS Files', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _entries.isEmpty || _loadingList ? null : _deleteAll,
                          icon: Icon(Icons.delete_sweep, color: t.outline, size: 20),
                          tooltip: 'Delete All',
                        ),
                        IconButton(
                          onPressed: _loadingList ? null : _refreshList,
                          icon: Icon(Icons.refresh, color: t.outline, size: 20),
                          tooltip: 'Refresh List',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                constraints: const BoxConstraints(minHeight: 300),
                child: Stack(
                  children: [
                    if (_entries.isEmpty && !_loadingList)
                      Center(
                        child: Text(
                          _hasFetchedListOnce ? 'Storage ESP32 kosong.' : 'Belum ambil list. Tekan Refresh dulu.',
                          style: TextStyle(color: t.outline, fontSize: 14),
                        ),
                      )
                    else if (_entries.isNotEmpty)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final isImage = entry.name.endsWith('.bin') || entry.name.endsWith('.gif') || entry.name.endsWith('.qoi');
                          final isCode = entry.name.endsWith('.h') || entry.name.endsWith('.json');
                          
                          IconData iconData = Icons.insert_drive_file_outlined;
                          Color iconColor = t.outline;
                          if (entry.isDir) {
                            iconData = Icons.folder;
                            iconColor = t.primary;
                          } else if (isImage) {
                            iconData = Icons.image_outlined;
                            iconColor = t.primary;
                          } else if (isCode) {
                            iconData = Icons.code;
                            iconColor = GanciColors.warning;
                          }
                          
                          final extIdx = entry.name.lastIndexOf('.');
                          final nameNoExt = extIdx != -1 ? entry.name.substring(0, extIdx) : entry.name;
                          final ext = extIdx != -1 ? entry.name.substring(extIdx) : '';
                          final displayExt = nameNoExt.length > 20 ? ' $ext' : ext;
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.transparent),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(iconData, color: iconColor, size: 24),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    nameNoExt,
                                                    style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Text(
                                                  displayExt,
                                                  style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                                                ),
                                              ],
                                            ),
                                            Text(entry.isDir ? 'Directory' : _formatBytes(entry.size), style: TextStyle(color: t.outline, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: t.outline, size: 20),
                                  hoverColor: GanciColors.error.withOpacity(0.1),
                                  color: GanciColors.error,
                                  onPressed: () => _deleteEntry(entry),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (_loadingList)
                      Positioned.fill(
                        child: Container(
                          color: Colors.white.withOpacity(0.6),
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewExpandedUI(GanciTheme t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Antrean Upload (${_selectedFiles.length} file)', style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary, fontSize: 13, fontFamily: 'Inter')),
              InkWell(
                onTap: () => setState(() => _selectedFiles = []),
                child: Text('Clear All', style: TextStyle(color: GanciColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._selectedFiles.map((f) {
             return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: t.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_rounded, color: t.outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${f.name} (${_formatBytes(f.size)})', style: TextStyle(fontSize: 12, color: t.textSecondary, fontFamily: 'Inter')),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedFiles.remove(f);
                        });
                      },
                      child: Icon(Icons.close_rounded, size: 16, color: GanciColors.error),
                    ),
                  ],
                ),
              );
          }),
        ],
      ),
    );
  }

  int _getFolderSizeSync(Directory dir) {
    int total = 0;
    try {
      for (var e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) {
          final ext = e.path.split('.').last.toLowerCase();
          if (ext == 'qoi' || ext == 'bin' || ext == 'gif') {
            total += e.lengthSync();
          }
        }
      }
    } catch (_) {}
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class _ApHeaderSection extends StatelessWidget {
  final bool showMenuButton;
  final VoidCallback? onMenuTap;
  final String title;
  final String? subtitle;

  const _ApHeaderSection({required this.showMenuButton, this.onMenuTap, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Row(
      children: [
        if (showMenuButton)
          Container(
            decoration: BoxDecoration(
              color: t.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.outlineVariant.withOpacity(0.5)),
            ),
            child: IconButton(
              onPressed: onMenuTap ?? () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
              color: t.textSecondary,
            ),
          )
        else
          Icon(Icons.menu_rounded, color: t.outline),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: t.textPrimary, fontSize: 26, fontWeight: FontWeight.w700, fontFamily: 'Inter', letterSpacing: -0.3)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: TextStyle(color: t.textSecondary, fontSize: 14, fontFamily: 'Inter')),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _GlassCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: t.primary.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

