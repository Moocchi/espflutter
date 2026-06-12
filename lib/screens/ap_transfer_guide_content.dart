import 'dart:io';

import 'package:flutter/material.dart';
import '../main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/esp_ap_transfer_service.dart';
import '../widgets/app_toast.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

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
  bool _obscurePassword = true;

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

  Future<void> _refreshAll({bool showToast = true}) async {
    final statusOk = await _refreshStatus(showToast: false);
    final listOk = await _refreshList(showToast: false);
    if (statusOk && listOk) {
      if (mounted) setState(() => _isConnected = true);
      if (showToast) _toast('Terhubung ($_lastConnectedBase)');
    } else {
      if (mounted) setState(() => _isConnected = false);
      if (showToast) _toast('Gagal koneksi ESP32', isError: true);
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
      Provider.of<AppState>(context, listen: false).incrementFilesSynced(_selectedFiles.length);
      setState(() {
        _selectedFiles = const [];
        _selectedFromFolder = false;
        _selectedFolderName = null;
      });
      await _refreshAll(showToast: false);
    } catch (e) {
      try {
        await _withBaseFallback((base) => _service.uploadFiles(
              base,
              _selectedFiles,
            targetDirectory: effectiveTargetDir,
            ));
        if (!mounted) return;
        _toast('Upload berhasil (${_selectedFiles.length})');
        Provider.of<AppState>(context, listen: false).incrementFilesSynced(_selectedFiles.length);
        setState(() {
          _selectedFiles = const [];
          _selectedFromFolder = false;
          _selectedFolderName = null;
        });
        await _refreshAll(showToast: false);
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
    bool isFolder = entry.isDir;
    if (isFolder) {
      _toast('Menghapus folder dan isinya...');
    }
    try {
      if (isFolder) {
        final prefix = '${entry.name}/';
        final children = _entries.where((e) => e.name.startsWith(prefix) && e.name != entry.name).toList();
        children.sort((a, b) => b.name.length.compareTo(a.name.length));
        
        for (var child in children) {
          await _withBaseFallback((base) => _service.deletePath(base, child.name));
        }
      }
      
      await _withBaseFallback((base) => _service.deletePath(base, entry.name));
      _toast('Delete berhasil');
      await _refreshAll(showToast: false);
    } catch (e) {
      _toast('Delete gagal', isError: true);
    }
  }

  Future<void> _deleteAll() async {
    if (_entries.isEmpty) return;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Files?'),
        content: const Text('Are you sure you want to delete all files from ESP32 SPIFFS?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFBA1A1A)),
            onPressed: () => Navigator.of(ctx).pop(true), 
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _toast('Menghapus semua file...');
    try {
      for (var entry in _entries) {
        if (!entry.isDir) {
          await _withBaseFallback((base) => _service.deletePath(base, entry.name));
        }
      }
      for (var entry in _entries.where((e) => e.isDir).toList().reversed) {
         await _withBaseFallback((base) => _service.deletePath(base, entry.name));
      }
      _toast('Semua file berhasil dihapus');
      await _refreshAll(showToast: false);
    } catch(e) {
      _toast('Gagal menghapus beberapa file', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          showMenuButton: widget.showMenuButton,
          onMenuTap: widget.onMenuTap,
          title: 'AP Transfer & Status',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AP Connection Card
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
                    child: const Icon(Icons.wifi_tethering, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text('AP Connection', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 16),
              Text('Connect your device to the ESP32 Access Point to begin transfer.', style: TextStyle(color: t.textSecondary, fontSize: 14, fontFamily: 'Inter')),
              const SizedBox(height: 12),
              Container(
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
                        Text('SSID', style: TextStyle(color: t.outline, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('ESP32-Media-App', style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
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
                        Text('PASSWORD', style: TextStyle(color: t.outline, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.1)),
                        InkWell(
                          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                          child: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: t.primary, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_obscurePassword ? '********' : '12345678', style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono')),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Endpoint Status Card
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.router_outlined, color: t.outline, size: 20),
                      const SizedBox(width: 8),
                      Text('Endpoint Status', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isConnected ? GanciColors.success.withOpacity(0.15) : GanciColors.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: _isConnected ? GanciColors.success : GanciColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(_isConnected ? 'Connected' : 'Disconnected', style: TextStyle(color: _isConnected ? GanciColors.success : GanciColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.glassBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_lastConnectedBase, style: TextStyle(color: t.textSecondary, fontSize: 13, fontFamily: 'JetBrains Mono')),
                    Icon(_isConnected ? Icons.check_circle : Icons.error_outline, color: _isConnected ? GanciColors.success : GanciColors.error, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadingStatus || _loadingList ? null : _refreshAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.surfaceContainerHigh,
                  foregroundColor: t.primary,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: _loadingStatus || _loadingList 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.refresh),
                label: Text(_loadingStatus || _loadingList ? 'Checking...' : 'Refresh / Test', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Device Stats Bento
        if (_status != null)
          Row(
            children: [
              Expanded(
                child: _GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.memory, color: t.outline, size: 24),
                      const SizedBox(height: 4),
                      Text('Free Heap', style: TextStyle(color: t.outline, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${_status!.ramFreeKb.toStringAsFixed(0)} KB', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.thermostat, color: t.outline, size: 24),
                      const SizedBox(height: 4),
                      Text('Core Temp', style: TextStyle(color: t.outline, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${_status!.tempC.toStringAsFixed(1)}°C', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (_status != null) const SizedBox(height: 16),
        if (_status != null)
          _GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sd_storage_outlined, color: t.outline, size: 16),
                        const SizedBox(width: 4),
                        Text('SPIFFS Storage', style: TextStyle(color: t.outline, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Text('${((_status!.fsUsedMb / _status!.fsTotalMb) * 100).toStringAsFixed(0)}% Used', style: TextStyle(color: t.textSecondary, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _status!.fsTotalMb > 0 ? (_status!.fsUsedMb / _status!.fsTotalMb) : 0,
                    backgroundColor: t.surfaceBright,
                    color: t.primary,
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Free: ${_status!.fsFreeMb.toStringAsFixed(2)} MB', style: TextStyle(color: t.textSecondary, fontSize: 13, fontFamily: 'JetBrains Mono')),
                    Text('Total: ${_status!.fsTotalMb.toStringAsFixed(2)} MB', style: TextStyle(color: t.textSecondary, fontSize: 13, fontFamily: 'JetBrains Mono')),
                  ],
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
                child: _loadingList 
                  ? const Center(child: CircularProgressIndicator())
                  : _entries.isEmpty 
                    ? Center(
                        child: Text(
                          _hasFetchedListOnce ? 'Storage ESP32 kosong.' : 'Belum ambil list. Tekan Test Connection dulu.',
                          style: TextStyle(color: t.outline, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
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
                                Row(
                                  children: [
                                    Icon(iconData, color: iconColor, size: 24),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(entry.name, style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                                        Text(entry.isDir ? 'Directory' : _formatBytes(entry.size), style: TextStyle(color: t.outline, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                                      ],
                                    ),
                                  ],
                                ),
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

class _HeaderSection extends StatelessWidget {
  final bool showMenuButton;
  final VoidCallback? onMenuTap;
  final String title;

  const _HeaderSection({required this.showMenuButton, this.onMenuTap, required this.title});

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
          child: Text(title, style: TextStyle(color: t.primary, fontSize: 26, fontWeight: FontWeight.w700, fontFamily: 'Inter', letterSpacing: -0.3)),
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

