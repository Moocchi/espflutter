import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/app_settings.dart';
import '../providers/app_state.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_card.dart';
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
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                                ? _HomeContent(showMenuButton: !isDesktop, onNavigate: _selectTab)
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
  final ValueChanged<_MenuTab> onNavigate;

  const _HomeContent({required this.showMenuButton, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(showMenuButton: showMenuButton, title: 'Ganci', subtitle: 'ESP32 Image Tools'),
        const SizedBox(height: 24),
        // Quick stats row
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: const [
              _StatCard(icon: Icons.image_rounded, value: '1.2k', label: 'IMAGES CONVERTED', color: GanciColors.primary),
              SizedBox(width: 12),
              _StatCard(icon: Icons.gif_box_rounded, value: '450', label: 'GIFS PROCESSED', color: GanciColors.secondary),
              SizedBox(width: 12),
              _StatCard(icon: Icons.send_rounded, value: '890', label: 'FILES TRANSFERRED', color: GanciColors.warning),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Features', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        const SizedBox(height: 14),
        _buildFeatureGrid(context),
        const SizedBox(height: 24),
        Text('Recent Activity', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        const SizedBox(height: 14),
        _buildActivityList(),
      ],
    );
  }

  Widget _buildFeatureGrid(BuildContext context) {
    final items = [
      _FeatureItem(Icons.image_rounded, 'Image Converter', 'Convert images to byte arrays for OLED/LCD', GanciColors.primaryContainer, _MenuTab.imageConverter),
      _FeatureItem(Icons.gif_box_rounded, 'GIF Editor', 'Optimize & resize GIFs for ESP32 displays', GanciColors.secondary, _MenuTab.gifEditor),
      _FeatureItem(Icons.wifi_tethering_rounded, 'AP Transfer', 'Send files via WiFi to your ESP32', GanciColors.warning, _MenuTab.apTransferGuide),
      _FeatureItem(Icons.sensors_rounded, 'ESP Bridge', 'BLE media control & device manager', GanciColors.tertiary, _MenuTab.espBridge),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12, runSpacing: 12,
          children: items.map((item) => SizedBox(
            width: cardWidth.clamp(100.0, 400.0),
            child: _FeatureCard(item: item, onTap: () => onNavigate(item.tab)),
          )).toList(),
        );
      },
    );
  }

  Widget _buildActivityList() {
    final activities = [
      ('Converted logo.png → 240x240 RGB565', '2 min ago', Icons.check_circle_rounded, GanciColors.secondary),
      ('Transferred cat.gif to ESP32', '15 min ago', Icons.send_rounded, GanciColors.primary),
      ('Optimized animation.gif (32 frames)', '1 hr ago', Icons.auto_fix_high_rounded, GanciColors.warning),
    ];
    return Builder(builder: (context) {
      final t = GanciTheme.of(context);
      return Column(
        children: activities.map((a) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.glassBorder),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: a.$4.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(a.$3, size: 18, color: a.$4),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.$1, style: TextStyle(color: t.textPrimary, fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'Inter'), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(a.$2, style: TextStyle(color: t.textMuted, fontSize: 11, fontFamily: 'Inter')),
            ])),
          ]),
        )).toList(),
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Container(
      width: 150, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 16)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(color: t.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        ]),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(color: t.textMuted, fontSize: 9, fontWeight: FontWeight.w600, fontFamily: 'Inter', letterSpacing: 0.8)),
      ]),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  final _MenuTab tab;
  const _FeatureItem(this.icon, this.title, this.desc, this.color, this.tab);
}

class _FeatureCard extends StatelessWidget {
  final _FeatureItem item;
  final VoidCallback onTap;
  const _FeatureCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: item.color.withOpacity(0.08),
        highlightColor: item.color.withOpacity(0.04),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: item.color.withOpacity(0.15)),
            boxShadow: [BoxShadow(color: item.color.withOpacity(0.05), blurRadius: 12)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: item.color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(item.icon, size: 22, color: item.color),
            ),
            const SizedBox(height: 12),
            Text(item.title, style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
            const SizedBox(height: 4),
            Text(item.desc, style: TextStyle(color: t.textMuted, fontSize: 11, fontFamily: 'Inter'), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Icon(Icons.arrow_forward_rounded, size: 16, color: item.color),
            ]),
          ]),
        ),
      ),
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
                  style: TextStyle(color: GanciColors.primaryLight, fontSize: 12),
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
                    style: TextStyle(color: GanciColors.textMuted, fontSize: 12),
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
                    style: TextStyle(color: GanciColors.textMuted, fontSize: 12),
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
        backgroundColor: GanciColors.surfaceContainer,
        title: const Text(
          'Save Optimized GIF',
          style: TextStyle(color: GanciColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: GanciColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Nama file .gif',
            hintStyle: TextStyle(color: GanciColors.textMuted),
            filled: true,
            fillColor: GanciColors.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: GanciColors.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: GanciColors.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: GanciColors.primary, width: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: GanciColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan', style: TextStyle(color: GanciColors.primary)),
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
                      color: GanciColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: GanciColors.glassBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: GanciColors.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${gif.name} • ${gif.frames.length} frames',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: GanciColors.primary,
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
                    style: TextStyle(color: GanciColors.textMuted, fontSize: 12),
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
                          color: GanciColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Switch(
                      value: settings.centerCrop,
                      activeColor: GanciColors.primary,
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
                    color: GanciColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: GanciColors.glassBorder),
                  ),
                  child: const Text(
                    'Resize target: 240 x 240 px',
                    style: TextStyle(
                      color: GanciColors.primaryLight,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Fill Background',
                  style: TextStyle(
                    color: GanciColors.textPrimary,
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
                    color: GanciColors.textPrimary,
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
                    fillColor: GanciColors.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: GanciColors.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: GanciColors.glassBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: GanciColors.primary, width: 1.4),
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
                          color: GanciColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: GanciColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: GanciColors.glassBorder),
                      ),
                      child: Text(
                        '${settings.compressionLevel}',
                        style: const TextStyle(
                          color: GanciColors.primaryLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: GanciColors.primary,
                    inactiveTrackColor: GanciColors.outlineVariant,
                    thumbColor: GanciColors.primary,
                    overlayColor: GanciColors.primary.withOpacity(0.12),
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
                        backgroundColor: GanciColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            GanciColors.primary.withOpacity(0.65),
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
                    style: TextStyle(color: GanciColors.textMuted, fontSize: 12),
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

  const _HeaderSection({required this.showMenuButton, required this.title, required this.subtitle});

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
              border: Border.all(color: t.glassBorder),
            ),
            child: IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
              color: t.textSecondary,
            ),
          )
        else
          Icon(Icons.menu_rounded, color: t.textMuted),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: t.textPrimary, fontSize: 26, fontWeight: FontWeight.w700, fontFamily: 'Inter', letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: t.textMuted, fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'Inter')),
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

    final t = GanciTheme.of(context);
    final content = Container(
      width: 200,
      decoration: BoxDecoration(
        color: t.surfaceContainer,
        border: Border(right: BorderSide(color: t.glassBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          // Brand header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [t.primary, t.primaryContainer],
                    ),
                    boxShadow: [BoxShadow(color: t.primary.withOpacity(0.3), blurRadius: 12)],
                  ),
                  child: const Icon(Icons.diamond_rounded, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ganci', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w700, fontSize: 18, fontFamily: 'Inter')),
                    Text('v1.0.0', style: TextStyle(color: t.textMuted.withOpacity(0.6), fontSize: 11, fontFamily: 'Inter')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Main menu section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('MAIN MENU', style: TextStyle(color: t.textMuted.withOpacity(0.5), fontWeight: FontWeight.w600, fontSize: 10, fontFamily: 'Inter', letterSpacing: 1.2)),
          ),
          const SizedBox(height: 12),
          _NavTile(icon: Icons.home_rounded, label: 'Home', isActive: selectedTab == _MenuTab.home, onTap: () => handleSelect(_MenuTab.home)),
          const SizedBox(height: 4),
          _NavTile(icon: Icons.image_rounded, label: 'Image Converter', isActive: selectedTab == _MenuTab.imageConverter, onTap: () => handleSelect(_MenuTab.imageConverter)),
          const SizedBox(height: 4),
          _NavTile(icon: Icons.gif_box_rounded, label: 'GIF Editor', isActive: selectedTab == _MenuTab.gifEditor, onTap: () => handleSelect(_MenuTab.gifEditor)),
          const SizedBox(height: 4),
          _NavTile(icon: Icons.wifi_tethering_rounded, label: 'AP Transfer', isActive: selectedTab == _MenuTab.apTransferGuide, onTap: () => handleSelect(_MenuTab.apTransferGuide)),
          const SizedBox(height: 4),
          _NavTile(icon: Icons.sensors_rounded, label: 'ESP Bridge', isActive: selectedTab == _MenuTab.espBridge, onTap: () => handleSelect(_MenuTab.espBridge)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('TOOLS', style: TextStyle(color: t.textMuted.withOpacity(0.5), fontWeight: FontWeight.w600, fontSize: 10, fontFamily: 'Inter', letterSpacing: 1.2)),
          ),
          const SizedBox(height: 8),
          _NavTile(icon: Icons.settings_rounded, label: 'Settings', isActive: false, onTap: () {}),
          _NavTile(icon: Icons.info_outline_rounded, label: 'About', isActive: false, onTap: () {}),
          const SizedBox(height: 12),
          // Theme toggle — clean compact row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Consumer<ThemeProvider>(
              builder: (context, tp, _) {
                return Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => tp.toggle(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.glassBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            tp.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                            size: 18, color: t.primaryLight,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tp.isDark ? 'Dark Mode' : 'Light Mode',
                              style: TextStyle(fontSize: 12, color: t.textSecondary, fontFamily: 'Inter', fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(Icons.swap_horiz_rounded, size: 16, color: t.textMuted),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );

    final hasDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;
    if (hasDrawer) {
      return Drawer(
        width: 200,
        backgroundColor: t.surfaceContainer,
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

  const _NavTile({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          splashColor: t.primary.withOpacity(0.1),
          highlightColor: t.primary.withOpacity(0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isActive ? t.primary.withOpacity(0.15) : Colors.transparent,
              border: isActive ? Border.all(color: t.primary.withOpacity(0.25)) : null,
            ),
            child: Row(children: [
              Icon(icon, size: 20, color: isActive ? t.primaryLight : t.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: isActive ? t.primaryLight : t.textSecondary, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500, fontSize: 13, fontFamily: 'Inter')),
              ),
            ]),
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

  const _StepCard({required this.title, required this.child, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.glassBorder),
        boxShadow: [BoxShadow(color: t.glassGlow, blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: t.primary.withOpacity(0.06),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: t.glassBorder)),
            ),
            child: Text(title, style: TextStyle(color: t.primaryLight, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
          ),
          Padding(padding: const EdgeInsets.all(20), child: child),
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
    final t = GanciTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: loadedFiles.map((file) {
        final processedFrames = file.frames.map((f) => f.processedImage).toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.glassBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(file.isGif ? Icons.gif_box_outlined : Icons.image_outlined, color: t.primary, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.primary, fontWeight: FontWeight.w700, fontSize: 12, fontFamily: 'Inter')),
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
    final t = GanciTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.primary.withOpacity(0.3), width: 1.4),
      ),
      child: Row(children: [
        Icon(file.isGif ? Icons.gif_box_outlined : Icons.image_outlined, color: t.primaryLight, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.primaryLight, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Inter'))),
        IconButton(icon: Icon(Icons.close, color: t.primaryLight.withOpacity(0.7), size: 18), onPressed: onRemove, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
      ]),
    );
  }
}

class _SelectionPill extends StatelessWidget {
  final bool active;
  final String label;
  final VoidCallback? onTap;

  const _SelectionPill({required this.active, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? t.primary.withOpacity(0.15) : t.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? t.primary : t.outlineVariant, width: active ? 1.4 : 1),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: active ? t.primaryLight : t.textMuted, fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PrimaryActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: t.primary.withOpacity(0.12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [t.primary.withOpacity(onTap == null ? 0.2 : 0.15), t.primary.withOpacity(onTap == null ? 0.1 : 0.08)],
            ),
            border: Border.all(color: onTap == null ? t.primary.withOpacity(0.2) : t.primary.withOpacity(0.5), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: onTap == null ? t.primary.withOpacity(0.5) : t.primaryLight, size: 20),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(color: onTap == null ? t.primaryLight.withOpacity(0.5) : t.primaryLight, fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter')),
            ]),
          ),
        ),
      ),
    );
  }
}

