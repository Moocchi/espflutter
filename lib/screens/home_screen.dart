import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../providers/app_state.dart';
import '../widgets/app_toast.dart';
import '../widgets/output_panel.dart';
import '../widgets/preview_widget.dart';
import '../widgets/settings_panel.dart';
import 'ap_transfer_guide_content.dart';
import '../esp_bridge/screens/player_screen.dart';
import '../esp_bridge/services/system_media_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _MenuTab {
  home,
  imageConverter,
  gifEditor,
  apTransferGuide,
  espBridge,
}

class _HomeScreenState extends State<HomeScreen> {
  _MenuTab _selectedTab = _MenuTab.home;
  static bool _espBridgeInitialized = false;
  final SystemMediaBridgeService _espBridgeService =
      SystemMediaBridgeService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      state.onToast = (msg, {bool isError = false}) {
        if (!mounted) return;
        AppToast.show(context, msg, isError: isError);
      };
      state.onNavigateToUpload = () {
        if (!mounted) return;
        _selectTab(_MenuTab.apTransferGuide);
      };
    });

    if (!_espBridgeInitialized) {
      _espBridgeInitialized = true;
      _espBridgeService.init();
    }

    _espBridgeService.setBridgeActive(false);
  }

  void _selectTab(_MenuTab tab) {
    _espBridgeService.setUiBusy(false);
    _espBridgeService.setBridgeActive(tab == _MenuTab.espBridge);
    setState(() => _selectedTab = tab);
  }

  void _prepareDrawerSelection(_MenuTab targetTab) {
    if (_selectedTab == _MenuTab.espBridge && targetTab != _MenuTab.espBridge) {
      _espBridgeService.setUiBusy(true);
      _espBridgeService.setBridgeActive(false);
    }
  }

  @override
  void dispose() {
    _espBridgeService.setUiBusy(false);
    _espBridgeService.setBridgeActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 820;
        return PopScope(
          canPop: _selectedTab == _MenuTab.home,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _selectTab(_MenuTab.home);
          },
          child: Scaffold(
            drawerEnableOpenDragGesture: !isDesktop,
            onDrawerChanged: (isOpen) {
              if (_selectedTab != _MenuTab.espBridge) {
                return;
              }
              if (isOpen) {
                _espBridgeService.setUiBusy(true);
              } else {
                _espBridgeService.setUiBusy(false, holdMsAfterRelease: 240);
              }
            },
            backgroundColor: const Color(0xFFF3F2FF),
            drawer: isDesktop
                ? null
                : _SidebarMenu(
                    selectedTab: _selectedTab,
                    onBeforeSelect: _prepareDrawerSelection,
                    onSelected: _selectTab,
                  ),
            body: SafeArea(
              child: Row(
                children: [
                  if (isDesktop)
                    _SidebarMenu(
                      selectedTab: _selectedTab,
                      onSelected: _selectTab,
                    ),
                  Expanded(
                    child: _selectedTab == _MenuTab.espBridge
                        ? _EspBridgeContent(showMenuButton: !isDesktop)
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: _selectedTab == _MenuTab.home
                                ? _HomeContent(showMenuButton: !isDesktop)
                                : _selectedTab == _MenuTab.imageConverter
                                    ? _ConverterContent(
                                        showMenuButton: !isDesktop,
                                      )
                                    : _selectedTab == _MenuTab.gifEditor
                                        ? _GifEditorContent(
                                            showMenuButton: !isDesktop,
                                          )
                                    : ApTransferGuideContent(
                                        showMenuButton: !isDesktop,
                                      ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeContent extends StatelessWidget {
  final bool showMenuButton;

  const _HomeContent({required this.showMenuButton});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          showMenuButton: showMenuButton,
          title: 'Hello, Daisy!',
          subtitle: 'Have a nice day :)',
        ),
        const SizedBox(height: 16),
        const _QuickFilters(),
        const SizedBox(height: 18),
        const _ProjectCarousel(),
        const SizedBox(height: 18),
        const _ProgressSection(),
      ],
    );
  }
}

class _ConverterContent extends StatelessWidget {
  final bool showMenuButton;

  const _ConverterContent({required this.showMenuButton});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasFiles = state.loadedFiles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          showMenuButton: showMenuButton,
          title: 'Image Converter',
          subtitle: 'Convert image to C++ output',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _StepCard(
            title: 'Select Image / GIF',
            outlined: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Supports PNG, JPG, BMP, and GIF (multi-frame).',
                  style: TextStyle(color: Color(0xFF6252E7), fontSize: 12),
                ),
                const SizedBox(height: 14),
                _PrimaryActionButton(
                  icon: Icons.add_photo_alternate_outlined,
                  label: 'Choose Files',
                  onTap: state.isProcessing ? null : state.pickFiles,
                ),
                const SizedBox(height: 14),
                if (hasFiles)
                  ...state.loadedFiles
                      .map((file) => _FileCard(
                            file: file,
                            onRemove: () => state.removeFile(file),
                          ))
                      .toList()
                else
                  const Text(
                    'No files selected',
                    style: TextStyle(color: Color(0xFF8E85ED), fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: double.infinity,
          child: _StepCard(
            title: 'Image Settings',
            outlined: true,
            child: SettingsPanel(),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _StepCard(
            title: 'Preview',
            outlined: true,
            child: hasFiles
                ? _PreviewSection(loadedFiles: state.loadedFiles)
                : const Text(
                    'No files selected',
                    style: TextStyle(color: Color(0xFF8E85ED), fontSize: 12),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        const SizedBox(
          width: double.infinity,
          child: _StepCard(
            title: 'Output',
            outlined: true,
            child: OutputPanel(),
          ),
        ),
      ],
    );
  }
}

class _GifEditorContent extends StatelessWidget {
  final bool showMenuButton;

  const _GifEditorContent({required this.showMenuButton});

  Future<String?> _showRenameDialog(BuildContext context, String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFDFDFF),
        title: const Text(
          'Save Optimized GIF',
          style: TextStyle(color: Color(0xFF2F3445)),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF2F3445)),
          decoration: InputDecoration(
            hintText: 'Nama file .gif',
            hintStyle: const TextStyle(color: Color(0xFF9AA0B3)),
            filled: true,
            fillColor: const Color(0xFFF7F5FF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC9C3FF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFC9C3FF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF6252E7), width: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF6D7385))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan', style: TextStyle(color: Color(0xFF6252E7))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.gifEditorSettings;
    final gif = state.gifEditorFile;
    final hasGif = gif != null && gif.frames.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          showMenuButton: showMenuButton,
          title: 'Gif Editor',
          subtitle: 'Center crop, resize 240x240, and optimize GIF',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _StepCard(
            title: 'Select GIF',
            outlined: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PrimaryActionButton(
                  icon: Icons.gif_box_rounded,
                  label: hasGif ? 'Choose Another GIF' : 'Choose GIF',
                  onTap: state.isGifEditorProcessing ? null : state.pickGifForEditor,
                ),
                const SizedBox(height: 12),
                if (hasGif)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F5FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFC9C3FF)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF6252E7), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${gif.name} • ${gif.frames.length} frames',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF6252E7),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Text(
                    'Belum ada GIF dipilih.',
                    style: TextStyle(color: Color(0xFF8E85ED), fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _StepCard(
            title: 'GIF Settings',
            outlined: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Center Crop',
                        style: TextStyle(
                          color: Color(0xFF3F4670),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Switch(
                      value: settings.centerCrop,
                      activeColor: const Color(0xFF6252E7),
                      onChanged: state.isGifEditorProcessing
                          ? null
                          : (value) {
                              state.updateGifEditorSettings(
                                settings.copyWith(centerCrop: value),
                              );
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F5FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFC9C3FF)),
                  ),
                  child: const Text(
                    'Resize target: 240 x 240 px',
                    style: TextStyle(
                      color: Color(0xFF4C42CF),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Fill Background',
                  style: TextStyle(
                    color: Color(0xFF3F4670),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SelectionPill(
                        active: settings.fillColor == GifFillColor.black,
                        label: 'Black',
                        onTap: state.isGifEditorProcessing
                            ? null
                            : () {
                                state.updateGifEditorSettings(
                                  settings.copyWith(fillColor: GifFillColor.black),
                                );
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SelectionPill(
                        active: settings.fillColor == GifFillColor.white,
                        label: 'White',
                        onTap: state.isGifEditorProcessing
                            ? null
                            : () {
                                state.updateGifEditorSettings(
                                  settings.copyWith(fillColor: GifFillColor.white),
                                );
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Optimization Method',
                  style: TextStyle(
                    color: Color(0xFF3F4670),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<GifOptimizationMethod>(
                  value: settings.optimizationMethod,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF7F5FF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFC9C3FF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFC9C3FF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF6252E7), width: 1.4),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: GifOptimizationMethod.lossy,
                      child: Text('Lossy Compression'),
                    ),
                  ],
                  onChanged: state.isGifEditorProcessing
                      ? null
                      : (value) {
                          if (value == null) return;
                          state.updateGifEditorSettings(
                            settings.copyWith(optimizationMethod: value),
                            autoProcess: false,
                          );
                        },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Compression',
                        style: TextStyle(
                          color: Color(0xFF3F4670),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F5FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFC9C3FF)),
                      ),
                      child: Text(
                        '${settings.compressionLevel}',
                        style: const TextStyle(
                          color: Color(0xFF4C42CF),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF6252E7),
                    inactiveTrackColor: const Color(0xFFD4D1FF),
                    thumbColor: const Color(0xFF6252E7),
                    overlayColor: const Color(0xFF6252E7).withOpacity(0.12),
                  ),
                  child: Slider(
                    min: 1,
                    max: 100,
                    divisions: 99,
                    value: settings.compressionLevel.toDouble(),
                    onChanged: state.isGifEditorProcessing
                        ? null
                        : (value) {
                            state.updateGifEditorSettings(
                              settings.copyWith(compressionLevel: value.round()),
                              autoProcess: false,
                            );
                          },
                    onChangeEnd: state.isGifEditorProcessing
                        ? null
                        : (_) {
                            state.processGifEditor(showToast: false);
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _StepCard(
            title: 'Process & Save',
            outlined: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PrimaryActionButton(
                  icon: state.isGifEditorProcessing
                      ? Icons.hourglass_top_rounded
                      : Icons.auto_fix_high_rounded,
                  label: state.isGifEditorProcessing ? 'Processing...' : 'Process GIF',
                  onTap: (!hasGif || state.isGifEditorProcessing)
                      ? null
                      : () => state.processGifEditor(),
                ),
                const SizedBox(height: 12),
                AnimatedOpacity(
                  opacity: state.isGifEditorProcessing ? 0.45 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (!hasGif || state.isGifEditorProcessing)
                          ? null
                          : () async {
                              final baseName = gif.name.contains('.')
                                  ? gif.name.substring(0, gif.name.lastIndexOf('.'))
                                  : gif.name;
                              final customName = await _showRenameDialog(
                                context,
                                '${baseName}_optimized',
                              );
                              if (customName == null) return;

                              final result = await state.saveOptimizedGif(
                                customName: customName.isEmpty ? null : customName,
                              );
                              if (!context.mounted) return;
                              if (result.path.isEmpty) {
                                AppToast.show(
                                  context,
                                  'Gagal save optimized GIF',
                                  isError: true,
                                );
                              } else {
                                AppToast.show(
                                  context,
                                  '${result.fileName} disimpan',
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6252E7),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFF6252E7).withOpacity(0.65),
                        disabledForegroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: state.isGifEditorProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_alt_rounded),
                      label: Text(
                        state.isGifEditorProcessing
                            ? 'Saving Optimized GIF...'
                            : 'Save Optimized GIF',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _StepCard(
            title: 'Preview',
            outlined: true,
            child: hasGif
              ? PreviewWidget(
                frames: gif.frames
                  .map((f) => f.sourceImage)
                  .toList(growable: false),
                isGif: true,
                )
                : const Text(
                    'Pilih GIF terlebih dahulu untuk melihat preview.',
                    style: TextStyle(color: Color(0xFF8E85ED), fontSize: 12),
                  ),
          ),
        ),
      ],
    );
  }
}

class _EspBridgeContent extends StatelessWidget {
  final bool showMenuButton;

  const _EspBridgeContent({required this.showMenuButton});

  @override
  Widget build(BuildContext context) {
    final mediaBridgeService = SystemMediaBridgeService();
    return Builder(
      builder: (ctx) => PlayerScreen(
        showMenuButton: showMenuButton,
        onMenuTap: () {
          mediaBridgeService.setUiBusy(true);
          Scaffold.maybeOf(ctx)?.openDrawer();
        },
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  final bool showMenuButton;
  final String title;
  final String subtitle;

  const _HeaderSection({
    required this.showMenuButton,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showMenuButton)
          IconButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
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
                style: TextStyle(
                  color: Color(0xFF2F3445),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Color(0xFF8A90A2),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickFilters extends StatelessWidget {
  const _QuickFilters();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      children: [
        _FilterChip(label: 'My tasks', active: true),
        _FilterChip(label: 'Project'),
        _FilterChip(label: 'Team'),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;

  const _FilterChip({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFDCD9FF) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFF5853D2) : const Color(0xFF8A90A2),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProjectCarousel extends StatelessWidget {
  const _ProjectCarousel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 178,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: const [
          _ProjectCard(
            title: 'Back End\nDevelopment',
            month: 'October 2020',
          ),
          SizedBox(width: 14),
          _ProjectCard(
            title: 'UI Design',
            month: 'November 2020',
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final String title;
  final String month;

  const _ProjectCard({required this.title, required this.month});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6457E9), Color(0xFF5A44E0)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.person_outline, size: 16, color: Colors.white),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            month,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Progress',
          style: TextStyle(
            color: Color(0xFF2F3445),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF6252E7),
                child: Icon(Icons.lock_outline, size: 18, color: Colors.white),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Name Here',
                      style: TextStyle(
                        color: Color(0xFF2F3445),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '3 Days Left',
                      style: TextStyle(
                        color: Color(0xFF9AA0B3),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.more_vert, color: Color(0xFF9AA0B3), size: 20),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarMenu extends StatelessWidget {
  final _MenuTab selectedTab;
  final ValueChanged<_MenuTab>? onBeforeSelect;
  final ValueChanged<_MenuTab> onSelected;

  const _SidebarMenu({
    required this.selectedTab,
    this.onBeforeSelect,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    void handleSelect(_MenuTab tab) {
      final hasDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;
      if (hasDrawer) {
        onBeforeSelect?.call(tab);
        Navigator.of(context).pop();
        Future.delayed(const Duration(milliseconds: 230), () {
          if (context.mounted) {
            onSelected(tab);
          }
        });
        return;
      }
      onSelected(tab);
    }

    final content = Container(
      width: 160,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Menu',
              style: TextStyle(
                color: Color(0xFF9AA0B3),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _NavTile(
            icon: Icons.home_rounded,
            label: 'Home',
            isActive: selectedTab == _MenuTab.home,
            onTap: () => handleSelect(_MenuTab.home),
          ),
          const SizedBox(height: 8),
          _NavTile(
            icon: Icons.image_rounded,
            label: 'Image Converter',
            isActive: selectedTab == _MenuTab.imageConverter,
            onTap: () => handleSelect(_MenuTab.imageConverter),
          ),
          const SizedBox(height: 8),
          _NavTile(
            icon: Icons.gif_box_rounded,
            label: 'Gif Editor',
            isActive: selectedTab == _MenuTab.gifEditor,
            onTap: () => handleSelect(_MenuTab.gifEditor),
          ),
          const SizedBox(height: 8),
          _NavTile(
            icon: Icons.wifi_tethering_rounded,
            label: 'AP Transfer',
            isActive: selectedTab == _MenuTab.apTransferGuide,
            onTap: () => handleSelect(_MenuTab.apTransferGuide),
          ),
          const SizedBox(height: 8),
          _NavTile(
            icon: Icons.sensors_rounded,
            label: 'ESP Bridge',
            isActive: selectedTab == _MenuTab.espBridge,
            onTap: () => handleSelect(_MenuTab.espBridge),
          ),
        ],
      ),
    );

    final hasDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;
    if (hasDrawer) {
      return Drawer(
        width: 160,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: content,
      );
    }
    return content;
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFE6E2FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color:
                    isActive ? const Color(0xFF6252E7) : const Color(0xFF9BA2B4),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFF6252E7)
                        : const Color(0xFF6D7385),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String title;
  final Widget child;
  final bool outlined;

  const _StepCard({
    required this.title,
    required this.child,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = outlined
        ? const Color(0xFF6252E7).withOpacity(0.32)
        : const Color(0xFF1A3048);
    return Container(
      decoration: BoxDecoration(
        color: outlined ? const Color(0xFFFDFDFF) : const Color(0xFF0E1E2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: outlined
            ? [
                BoxShadow(
                  color: const Color(0xFF6252E7).withOpacity(0.08),
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

class _PreviewSection extends StatelessWidget {
  final List<LoadedFile> loadedFiles;

  const _PreviewSection({required this.loadedFiles});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: loadedFiles.map((file) {
        final processedFrames = file.frames.map((frame) => frame.processedImage).toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F5FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC9C3FF)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            file.isGif
                                ? Icons.gif_box_outlined
                                : Icons.image_outlined,
                            color: const Color(0xFF6252E7),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF6252E7),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              PreviewWidget(frames: processedFrames, isGif: file.isGif),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _FileCard extends StatelessWidget {
  final LoadedFile file;
  final VoidCallback onRemove;

  const _FileCard({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6252E7), width: 1.6),
      ),
      child: Row(
        children: [
          Icon(
            file.isGif ? Icons.gif_box_outlined : Icons.image_outlined,
            color: const Color(0xFF6252E7),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF6252E7),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF6252E7), size: 18),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _SelectionPill extends StatelessWidget {
  final bool active;
  final String label;
  final VoidCallback? onTap;

  const _SelectionPill({
    required this.active,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8E4FF) : const Color(0xFFF7F5FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? const Color(0xFF6252E7) : const Color(0xFFC9C3FF),
            width: active ? 1.4 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF4C42CF) : const Color(0xFF5F6680),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F5FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: onTap == null
                  ? const Color(0xFF6252E7).withOpacity(0.35)
                  : const Color(0xFF6252E7),
              width: 1.8,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: const Color(0xFF6252E7), size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: onTap == null
                        ? const Color(0xFF6252E7).withOpacity(0.65)
                        : const Color(0xFF6252E7),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

