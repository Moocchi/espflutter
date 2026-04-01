import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../models/app_settings.dart';
import '../services/image_processor.dart';
import '../services/qoi_encoder.dart';

class AppState extends ChangeNotifier {
  AppSettings settings = AppSettings();
  List<LoadedFile> loadedFiles = [];
  String cppOutput = '';
  bool isProcessing = false;
  String statusMessage = '';
  bool userModifiedCanvas = false;
  
  // Toast callback -- set by the UI layer
  void Function(String message, {bool isError})? onToast;
  
  void _showToast(String msg, {bool isError = false}) {
    onToast?.call(msg, isError: isError);
  }
  
  // Debounce timer for settings updates
  Timer? _debounceTimer;

  // ---- FILE LOADING ----

  Future<void> pickFiles() async {
    const allowedExt = {'jpg', 'jpeg', 'png', 'bmp', 'gif'};

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'bmp', 'gif'],
      withData: true,
    );
    if (result == null) return;

    final picked = result.files.where((f) {
      final ext = (f.extension ??
              (f.name.contains('.') ? f.name.split('.').last : ''))
          .toLowerCase();
      return allowedExt.contains(ext);
    }).toList(growable: false);

    if (picked.isEmpty) {
      _showToast('Pilih file gambar (jpg/png/bmp/gif)', isError: true);
      return;
    }

    isProcessing = true;
    statusMessage = 'Loading files...';
    notifyListeners();

    final List<LoadedFile> newFiles = [];
    for (final f in picked) {
      String? loadPath = f.path;
      final isGif = f.extension?.toLowerCase() == 'gif';

      if (loadPath == null && f.bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${f.name}');
        await tempFile.writeAsBytes(f.bytes!);
        loadPath = tempFile.path;
      }

      // Crop static images
      if (!isGif && loadPath != null) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: loadPath,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Image',
              toolbarColor: const Color(0xFF6252E7),
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: false,
            ),
          ],
        );

        if (croppedFile != null) {
          loadPath = croppedFile.path;
        } else {
          continue; // Skipped if user cancelled crop
        }
      }

      Uint8List? bytes;
      if (loadPath != null) {
        bytes = await File(loadPath).readAsBytes();
      } else if (f.bytes != null) {
        bytes = f.bytes;
      }
      if (bytes == null) continue;

      // Process file loading in isolate to prevent UI freeze
      statusMessage = 'Processing ${f.name}...';
      notifyListeners();

      try {
        final loaded = await compute(
          _loadFileIsolate,
          _LoadFileArgs(f.name, bytes),
        );
        if (loaded.frames.isEmpty) continue;
        newFiles.add(loaded);
      } catch (e) {
        debugPrint('Error loading file ${f.name}: $e');
        continue;
      }
    }

    loadedFiles = newFiles;
    if (!userModifiedCanvas &&
        newFiles.isNotEmpty &&
        newFiles.first.frames.isNotEmpty) {
      final firstFrame = newFiles.first.frames.first;
      settings = settings.copyWith(
        canvasWidth: firstFrame.sourceImage.width,
        canvasHeight: firstFrame.sourceImage.height,
      );
    }

    if (newFiles.isNotEmpty) {
      _showToast('Processing ${newFiles.length} file(s)...');
      notifyListeners();
      await _processAllFrames();
    }

    isProcessing = false;
    statusMessage = '';
    _showToast('Done OK');
    notifyListeners();
  }

  void removeFile(LoadedFile file) {
    loadedFiles.remove(file);
    cppOutput = '';
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings newSettings, {String? changeDescription}) async {
    if (newSettings.canvasWidth != settings.canvasWidth ||
        newSettings.canvasHeight != settings.canvasHeight) {
      userModifiedCanvas = true;
    }

    // Detect if this is a critical change that should process immediately
    final isCritical = newSettings.drawMode != settings.drawMode ||
        newSettings.antiAlias != settings.antiAlias ||
        newSettings.scale != settings.scale ||
        newSettings.ditheringMode != settings.ditheringMode ||
        newSettings.backgroundColor != settings.backgroundColor;

    settings = newSettings;
    cppOutput = ''; // Invalidate old output
    notifyListeners();
    
    if (changeDescription != null) {
      _showToast(changeDescription);
    }
    
    // Cancel any pending debounce
    _debounceTimer?.cancel();

    if (isCritical) {
      // Critical changes: process immediately, queue if busy
      _scheduleProcessing(immediate: true);
    } else {
      // Minor changes: debounce
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        _scheduleProcessing(immediate: false);
      });
    }
  }

  bool _pendingProcess = false;

  Future<void> _scheduleProcessing({required bool immediate}) async {
    if (isProcessing) {
      // Mark that we need to re-process after current run finishes
      _pendingProcess = true;
      return;
    }
    isProcessing = true;
    _showToast('Processing...');
    notifyListeners();

    await _processAllFrames();

    isProcessing = false;

    // If settings changed while we were processing, run again
    if (_pendingProcess) {
      _pendingProcess = false;
      isProcessing = true;
      _showToast('Processing...');
      notifyListeners();
      await _processAllFrames();
      isProcessing = false;
    }

    _showToast('Done OK');
    notifyListeners();
  }
  
  /// Update settings without processing (for rapid changes like typing)
  void updateSettingsQuick(AppSettings newSettings) {
    if (newSettings.canvasWidth != settings.canvasWidth ||
        newSettings.canvasHeight != settings.canvasHeight) {
      userModifiedCanvas = true;
    }
    settings = newSettings;
    notifyListeners();
  }
  
  /// Apply pending settings and process frames
  Future<void> applySettings() async {
    _debounceTimer?.cancel();
    cppOutput = '';
    _scheduleProcessing(immediate: true);
  }

  Future<void> _processAllFrames() async {
    for (final file in loadedFiles) {
      if (file.frames.isEmpty) continue;

      final sources = file.frames.map((f) => f.sourceImage).toList();
      final results = await compute(
        _processFramesBatchIsolate,
        _ProcessAllArgs(sources, settings),
      );

      for (int i = 0; i < file.frames.length; i++) {
        file.frames[i].processedImage = results[i];
      }
    }
  }

  // ---- OUTPUT GENERATION ----

  Future<void> generateOutput() async {
    final allFrames = loadedFiles.expand((f) => f.frames).toList();
    if (allFrames.isEmpty) return;

    isProcessing = true;
    _showToast('Generating C++ Code...');
    notifyListeners();

    cppOutput = await compute(
      _generateOutputIsolate,
      _GenerateArgs(allFrames, settings),
    );

    isProcessing = false;
    _showToast('C++ Code generated OK');
    notifyListeners();
  }

  // ---- GET OUTPUT BASE DIRECTORY ----
  // Android: tries Downloads, then external storage, then app documents
  Future<Directory> _getOutputDir() async {
    if (Platform.isAndroid) {
      // Try Download directory first
      try {
        final dl = Directory('/storage/emulated/0/Download/image2cpp');
        await dl.create(recursive: true);
        // Test write access by creating+deleting a temp file
        final testFile = File('${dl.path}/.write_test');
        await testFile.writeAsString('');
        await testFile.delete();
        return dl;
      } catch (_) {}

      // Fallback: app-specific external storage (visible in file manager)
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final outDir = Directory('${extDir.path}/image2cpp');
          await outDir.create(recursive: true);
          return outDir;
        }
      } catch (_) {}
    }
    // Final fallback: app documents directory
    final base = await getApplicationDocumentsDirectory();
    final outDir = Directory('${base.path}/image2cpp');
    await outDir.create(recursive: true);
    return outDir;
  }

  // ---- SAVE BIN FILES ----
  // Single image -> satu .bin file
  // GIF -> folder berisi frame0000.bin, frame0001.bin ...
  // customName: nama kustom untuk file/folder output
  Future<SaveResult> saveBinFiles({String? customName}) async {
    final allFiles = loadedFiles;
    if (allFiles.isEmpty) return SaveResult(path: '', fileName: '');

    final outputDir = await _getOutputDir();
    String lastPath = '';
    String lastName = '';
    int fileCount = 0;

    for (final loadedFile in allFiles) {
      // Gunakan customName jika ada, atau nama file asli
      final baseName = customName ?? loadedFile.name.split('.').first;
      final frames = loadedFile.frames;

      if (frames.length > 1) {
        // GIF -> subfolder -- clean existing first
        final subDir = Directory('${outputDir.path}/$baseName');
        if (await subDir.exists()) {
          await subDir.delete(recursive: true);
        }
        await subDir.create(recursive: true);

        final binFiles =
            ImageProcessor.generateBinFiles(frames, settings, baseName);
        for (final entry in binFiles.entries) {
          final outFile = File('${subDir.path}/${entry.key}');
          await outFile.writeAsBytes(entry.value);
          fileCount++;
        }
        lastPath = subDir.path;
        lastName = '$baseName/ (${frames.length} files)';
      } else {
        // Single image -> satu bin di output dir
        if (frames.first.processedImage != null) {
          final binData =
              ImageProcessor.frameToBin(frames.first.processedImage!, settings);
          final outFile = File('${outputDir.path}/$baseName.bin');
          if (await outFile.exists()) await outFile.delete();
          await outFile.writeAsBytes(binData);
          lastPath = outFile.path;
          lastName = '$baseName.bin';
          fileCount++;
        }
      }
    }

    if (fileCount == 0) return SaveResult(path: '', fileName: '');

    return SaveResult(
      path: lastPath,
      fileName: lastName,
    );
  }

  // ---- SAVE QOI FILES ----
  // QOI (Quite OK Image) format - lossless, fast encode/decode
  Future<SaveResult> saveQoiFiles({String? customName}) async {
    final allFiles = loadedFiles;
    if (allFiles.isEmpty) return SaveResult(path: '', fileName: '');

    final outputDir = await _getOutputDir();
    String lastPath = '';
    String lastName = '';
    int fileCount = 0;

    for (final loadedFile in allFiles) {
      final baseName = customName ?? loadedFile.name.split('.').first;
      final frames = loadedFile.frames;

      if (frames.length > 1) {
        // GIF -> subfolder -- clean existing first
        final subDir = Directory('${outputDir.path}/$baseName');
        if (await subDir.exists()) {
          await subDir.delete(recursive: true);
        }
        await subDir.create(recursive: true);

        for (int i = 0; i < frames.length; i++) {
          final frame = frames[i];
          if (frame.processedImage != null) {
            final qoiData = QoiEncoder.encode(frame.processedImage!);
            final fileName = 'frame${i.toString().padLeft(4, '0')}.qoi';
            final outFile = File('${subDir.path}/$fileName');
            await outFile.writeAsBytes(qoiData);
            fileCount++;
          }
        }
        lastPath = subDir.path;
        lastName = '$baseName/ (${frames.length} files)';
      } else {
        // Single image -> satu .qoi file
        if (frames.first.processedImage != null) {
          final qoiData = QoiEncoder.encode(frames.first.processedImage!);
          final outFile = File('${outputDir.path}/$baseName.qoi');
          if (await outFile.exists()) await outFile.delete();
          await outFile.writeAsBytes(qoiData);
          lastPath = outFile.path;
          lastName = '$baseName.qoi';
          fileCount++;
        }
      }
    }

    if (fileCount == 0) return SaveResult(path: '', fileName: '');

    return SaveResult(
      path: lastPath,
      fileName: lastName,
    );
  }

  List<ImageFrame> getAllFrames() {
    return loadedFiles.expand((f) => f.frames).toList();
  }
}

class SaveResult {
  final String path;
  final String fileName;
  SaveResult({required this.path, required this.fileName});
}

// Isolate helper
class _ProcessAllArgs {
  final List<img.Image> sources;
  final AppSettings settings;
  _ProcessAllArgs(this.sources, this.settings);
}

List<img.Image> _processFramesBatchIsolate(_ProcessAllArgs args) {
  return args.sources
      .map((src) => ImageProcessor.applySettings(src, args.settings))
      .toList();
}

class _GenerateArgs {
  final List<ImageFrame> frames;
  final AppSettings settings;
  _GenerateArgs(this.frames, this.settings);
}

String _generateOutputIsolate(_GenerateArgs args) {
  return ImageProcessor.generateCppOutput(args.frames, args.settings);
}

// Isolate helper for file loading
class _LoadFileArgs {
  final String name;
  final Uint8List bytes;
  _LoadFileArgs(this.name, this.bytes);
}

LoadedFile _loadFileIsolate(_LoadFileArgs args) {
  return ImageProcessor.loadFile(args.name, args.bytes);
}


