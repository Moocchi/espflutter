import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/app_settings.dart';
import '../providers/app_state.dart';
import '../widgets/app_toast.dart';
import '../widgets/output_panel.dart';
import '../widgets/preview_widget.dart';
import '../widgets/settings_panel.dart';
import 'ap_transfer_guide_content.dart';
import '../esp_bridge/screens/player_screen.dart';
import '../esp_bridge/services/system_media_service.dart';
import '../esp_bridge/services/ble_service.dart';

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
                                        isDesktop: isDesktop,
                                      )
                                    : _selectedTab == _MenuTab.gifEditor
                                        ? _GifEditorContent(
                                            showMenuButton: !isDesktop,
                                            isDesktop: isDesktop,
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
        _buildDeviceStatusBanner(context),
        const SizedBox(height: 24),
        _buildStatsGrid(context),
        const SizedBox(height: 24),
        Text('Features', style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        const SizedBox(height: 14),
        _buildFeatureGrid(context),
      ],
    );
  }

  Widget _buildDeviceStatusBanner(BuildContext context) {
    final t = GanciTheme.of(context);
    return StreamBuilder<BleStatus>(
      stream: BleService().statusStream,
      initialData: BleService().currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? BleStatus.disconnected;
        String statusText = 'Disconnected';
        Color statusColor = t.outline;
        if (status == BleStatus.connected) {
          statusText = 'Connected via BLE';
          statusColor = const Color(0xFF006C49); // Mint
        } else if (status == BleStatus.scanning) {
          statusText = 'Scanning for devices...';
          statusColor = const Color(0xFFFFB547); // Warning/Orange
        } else if (status == BleStatus.connecting) {
          statusText = 'Connecting...';
          statusColor = t.primary;
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.outlineVariant.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: t.primary.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: t.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.developer_board_rounded, size: 22, color: t.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ESP32-S3 DevKit', style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => onNavigate(_MenuTab.espBridge),
                style: TextButton.styleFrom(
                  backgroundColor: t.surfaceContainerLow,
                  foregroundColor: t.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    final t = GanciTheme.of(context);
    final appState = context.watch<AppState>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final cardWidth = (isWide ? (constraints.maxWidth - 24) / 3 : (constraints.maxWidth - 12) / 2).floorToDouble();
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Container(
              width: cardWidth,
              height: 110,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.outlineVariant.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                    color: t.primary.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Images Converted', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                      Icon(Icons.image_outlined, color: t.textMuted, size: 18),
                    ],
                  ),
                  Text('${appState.imagesConvertedCount}', style: TextStyle(color: t.primary, fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                ],
              ),
            ),
            Container(
              width: cardWidth,
              height: 110,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.outlineVariant.withOpacity(0.5)),
                boxShadow: [
                  BoxShadow(
                    color: t.primary.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('GIFs Processed', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                      Icon(Icons.gif_box_outlined, color: t.textMuted, size: 18),
                    ],
                  ),
                  Text('${appState.gifsProcessedCount}', style: TextStyle(color: t.primary, fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                ],
              ),
            ),
            Container(
              width: isWide ? cardWidth : constraints.maxWidth,
              height: 110,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.primaryContainer,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: t.primary.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Files Synced', style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 12, fontWeight: FontWeight.w500)),
                      const Icon(Icons.sync, color: Colors.white, size: 18),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${appState.filesSyncedCount}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Total', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFeatureGrid(BuildContext context) {
    final t = GanciTheme.of(context);
    final items = [
      _FeatureItem(
        Icons.image_aspect_ratio_rounded,
        'Image Converter',
        'Convert to RGB565 / Grayscale',
        t.primary,
        _MenuTab.imageConverter,
      ),
      _FeatureItem(
        Icons.gif_box_rounded,
        'GIF Editor',
        'Extract frames & optimize',
        t.primary,
        _MenuTab.gifEditor,
      ),
      _FeatureItem(
        Icons.settings_input_antenna_rounded,
        'AP Transfer',
        'Direct Wi-Fi file upload',
        t.primary,
        _MenuTab.apTransferGuide,
      ),
      _FeatureItem(
        Icons.sync_alt_rounded,
        'ESP Bridge',
        'Serial monitor & control',
        t.primary,
        _MenuTab.espBridge,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768;
        final crossAxisCount = 2;
        final cardWidth = ((constraints.maxWidth - (crossAxisCount - 1) * 12) / crossAxisCount).floorToDouble();

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((item) => SizedBox(
            width: cardWidth,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () => onNavigate(item.tab),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.outlineVariant.withOpacity(0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: t.primary.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: t.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(item.icon, size: 22, color: t.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(item.title, style: TextStyle(color: t.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                      const SizedBox(height: 4),
                      Text(item.desc, style: TextStyle(color: t.textSecondary, fontSize: 12, fontFamily: 'Inter')),
                    ],
                  ),
                ),
              ),
            ),
          )).toList(),
        );
      },
    );
  }
}

class _BentoCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final Widget child;

  const _BentoCard({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: TextStyle(color: t.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'Inter'))),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _ConverterContent extends StatelessWidget {
  final bool showMenuButton;
  final bool isDesktop;

  const _ConverterContent({required this.showMenuButton, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasFiles = state.loadedFiles.isNotEmpty;
    final t = GanciTheme.of(context);

    final sourceFilesCard = _BentoCard(
      icon: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: t.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.upload_file_rounded, color: t.primary),
      ),
      title: 'Source Files',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: state.isProcessing ? null : state.pickFiles,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.outlineVariant.withValues(alpha: 0.8)),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_photo_alternate_rounded, color: t.primaryLight, size: 40),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: state.isProcessing ? null : state.pickFiles,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      elevation: 1,
                    ),
                    child: const Text('Choose Files', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                  ),
                  const SizedBox(height: 16),
                  Text('Supports PNG, JPG, BMP, GIF', style: TextStyle(color: t.textSecondary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Max 5MB per file', style: TextStyle(color: t.textMuted, fontSize: 12, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (hasFiles) ...[
            const SizedBox(height: 20),
            ...state.loadedFiles.map((file) => _FileCard(
              file: file,
              onRemove: () => state.removeFile(file),
            )).toList(),
          ],
        ],
      ),
    );



    final settingsCard = _BentoCard(
      icon: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: t.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.settings_rounded, color: t.primary),
      ),
      title: 'Image Settings',
      child: const SettingsPanel(),
    );

    final bottomCards = [
      const SizedBox(height: 24),
      _BentoCard(
        icon: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: t.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.visibility_rounded, color: t.primary),
        ),
        title: 'Preview',
        child: hasFiles
            ? _PreviewSection(loadedFiles: state.loadedFiles)
            : Text('No files selected', style: TextStyle(color: t.textMuted, fontSize: 14)),
      ),
      const SizedBox(height: 24),
      _BentoCard(
        icon: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: t.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.code_rounded, color: t.primary),
        ),
        title: 'Output',
        child: const OutputPanel(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          showMenuButton: showMenuButton,
          title: 'Image Converter',
          subtitle: 'Convert and optimize images for ESP32 displays',
        ),
        const SizedBox(height: 24),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  children: [sourceFilesCard],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 5,
                child: Column(
                  children: [settingsCard],
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              sourceFilesCard,
              const SizedBox(height: 24),
              settingsCard,
            ],
          ),
        ...bottomCards,
      ],
    );
  }
}

class _GifEditorContent extends StatelessWidget {
  final bool showMenuButton;
  final bool isDesktop;

  const _GifEditorContent({required this.showMenuButton, required this.isDesktop});

  Future<String?> _showRenameDialog(BuildContext context, String defaultName, GanciTheme t) async {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: t.outlineVariant.withValues(alpha: 0.5)),
        ),
        title: Text(
          'Save Optimized GIF',
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nama file:', style: TextStyle(color: t.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Nama file .gif',
                hintStyle: TextStyle(color: t.textMuted),
                filled: true,
                fillColor: t.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.outlineVariant.withValues(alpha: 0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.outlineVariant.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: t.primary, width: 2),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text('Batal', style: TextStyle(color: t.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 1,
            ),
            child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.w600)),
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
    final t = GanciTheme.of(context);

    final sourceAnimationCard = _BentoCard(
      icon: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: t.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.upload_file_rounded, color: t.primary),
      ),
      title: 'Source Animation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: state.isGifEditorProcessing ? null : state.pickGifForEditor,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.outlineVariant.withValues(alpha: 0.8)),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_photo_alternate_rounded, color: t.primaryLight, size: 40),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: state.isGifEditorProcessing ? null : state.pickGifForEditor,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      elevation: 1,
                    ),
                    child: Text(hasGif ? 'Choose Another GIF' : 'Choose GIF', style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                  ),
                  const SizedBox(height: 16),
                  Text('Supports GIF format', style: TextStyle(color: t.textSecondary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Max 5MB per file', style: TextStyle(color: t.textMuted, fontSize: 12, letterSpacing: 0.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (hasGif) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: t.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.glassBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: t.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${gif.name} • ${gif.frames.length} frames',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ),
            )
          ],
        ],
      ),
    );

    final settingsCard = _BentoCard(
      icon: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: t.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.tune_rounded, color: t.primary),
      ),
      title: 'Optimization Settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Center Crop', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter')),
                    Text('Fill target area', style: TextStyle(color: t.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Switch(
                value: settings.centerCrop,
                activeColor: t.primary,
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
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: t.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Target Dimensions', style: TextStyle(color: t.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: t.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
                  child: Text('240x240', style: TextStyle(color: t.primary, fontFamily: 'JetBrains Mono', fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Background Color', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SelectionPill(
                  active: settings.fillColor == GifFillColor.black,
                  label: 'Black',
                  onTap: state.isGifEditorProcessing ? null : () => state.updateGifEditorSettings(settings.copyWith(fillColor: GifFillColor.black)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SelectionPill(
                  active: settings.fillColor == GifFillColor.white,
                  label: 'White',
                  onTap: state.isGifEditorProcessing ? null : () => state.updateGifEditorSettings(settings.copyWith(fillColor: GifFillColor.white)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Optimization Method', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter')),
          const SizedBox(height: 8),
          DropdownButtonFormField<GifOptimizationMethod>(
            value: settings.optimizationMethod,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              filled: true,
              fillColor: t.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.outlineVariant.withValues(alpha: 0.5))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.outlineVariant.withValues(alpha: 0.5))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.primary, width: 1.5)),
            ),
            items: const [
              DropdownMenuItem(value: GifOptimizationMethod.lossy, child: Text('Lossy Compression', style: TextStyle(fontFamily: 'Inter', fontSize: 14))),
            ],
            onChanged: state.isGifEditorProcessing ? null : (value) {
              if (value != null) state.updateGifEditorSettings(settings.copyWith(optimizationMethod: value), autoProcess: false);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Compression Level', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter'))),
              Text('${settings.compressionLevel}%', style: TextStyle(color: t.primary, fontFamily: 'JetBrains Mono', fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: t.primary,
              inactiveTrackColor: t.surfaceContainerHigh,
              thumbColor: t.primary,
              overlayColor: t.primary.withValues(alpha: 0.12),
            ),
            child: Slider(
              min: 1,
              max: 100,
              divisions: 99,
              value: settings.compressionLevel.toDouble(),
              onChanged: state.isGifEditorProcessing ? null : (value) => state.updateGifEditorSettings(settings.copyWith(compressionLevel: value.round()), autoProcess: false),
              onChangeEnd: state.isGifEditorProcessing ? null : (_) => state.processGifEditor(showToast: false),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('High Quality', style: TextStyle(color: t.textMuted, fontSize: 12)),
              Text('Small Size', style: TextStyle(color: t.textMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );

    final actionButtons = Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (!hasGif || state.isGifEditorProcessing) ? null : () => state.processGifEditor(),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.surfaceContainerLow,
              foregroundColor: t.primary,
              side: BorderSide(color: t.primary.withValues(alpha: 0.5), width: 1),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(state.isGifEditorProcessing ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded),
            label: Text(state.isGifEditorProcessing ? 'Processing...' : 'Process GIF', style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (!hasGif || state.isGifEditorProcessing) ? null : () async {
              final baseName = gif.name.contains('.') ? gif.name.substring(0, gif.name.lastIndexOf('.')) : gif.name;
              final customName = await _showRenameDialog(context, '${baseName}_optimized', t);
              if (customName == null) return;
              final result = await state.saveOptimizedGif(customName: customName.isEmpty ? null : customName);
              if (!context.mounted) return;
              if (result.path.isEmpty) {
                AppToast.show(context, 'Gagal save optimized GIF', isError: true);
              } else {
                AppToast.show(context, '${result.fileName} disimpan ke image2cpp');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            icon: Icon(state.isGifEditorProcessing ? Icons.hourglass_bottom_rounded : Icons.save_rounded),
            label: Text(state.isGifEditorProcessing ? 'Saving...' : 'Save Optimized', style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter')),
          ),
        ),
      ],
    );

    final previewCard = _BentoCard(
      icon: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: t.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
        child: Icon(Icons.preview_rounded, color: t.primary),
      ),
      title: 'Preview',
      child: Column(
        children: [
          if (hasGif)
            Container(
              child: PreviewWidget(
                frames: gif.frames.map((f) => f.sourceImage).toList(growable: false),
                isGif: true,
              ),
            )
          else
            Container(
              width: 240, height: 240,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: t.surfaceContainerHighest, width: 4),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gif_box_outlined, size: 48, color: t.textMuted.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),
                  Text('No preview available', style: TextStyle(color: t.textMuted.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ESTIMATED OUTPUT STATS', style: TextStyle(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, fontFamily: 'Inter')),
                const SizedBox(height: 16),
                _buildStatRow(t, Icons.sd_storage_outlined, 'File Size', hasGif ? '${state.gifEditorEstimatedFileSizeKb} KB' : '-- KB'),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(color: t.outlineVariant.withValues(alpha: 0.2), height: 1)),
                _buildStatRow(t, Icons.animation_rounded, 'Frames', hasGif ? '${gif.frames.length}' : '--'),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(color: t.outlineVariant.withValues(alpha: 0.2), height: 1)),
                _buildStatRow(t, Icons.speed_rounded, 'Framerate', hasGif ? '15 FPS' : '-- FPS'),
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(color: t.outlineVariant.withValues(alpha: 0.2), height: 1)),
                _buildStatRow(t, Icons.memory_rounded, 'RAM Est.', hasGif ? '${state.gifEditorEstimatedRamKb} KB' : '-- KB'),
              ],
            ),
          ),
        ],
      ),
    );

    final leftColCards = [sourceAnimationCard, const SizedBox(height: 20), settingsCard, const SizedBox(height: 20), actionButtons];
    final rightColCards = [previewCard];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderSection(
          showMenuButton: showMenuButton,
          title: 'Gif Editor',
          subtitle: 'Optimize and prepare animations for ESP32 display',
        ),
        const SizedBox(height: 16),
        if (isDesktop)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  children: leftColCards,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: Column(
                  children: rightColCards,
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              ...leftColCards,
              const SizedBox(height: 14),
              ...rightColCards,
            ],
          ),
      ],
    );
  }

  Widget _buildStatRow(GanciTheme t, IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: t.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
        Text(value, style: TextStyle(color: t.textPrimary, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono')),
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
      width: 250,
      decoration: BoxDecoration(
        color: t.surfaceContainer,
        border: Border(right: BorderSide(color: t.glassBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [t.primary, t.primary.withValues(alpha: 0.7)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: t.primary.withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: const Icon(Icons.diamond_rounded, size: 24, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Text('Ganci', style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w800, fontSize: 22, fontFamily: 'Inter', letterSpacing: -0.5)),
              ],
            ),
          ),
          const SizedBox(height: 36),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('MAIN MENU', style: TextStyle(color: t.textMuted.withValues(alpha: 0.7), fontWeight: FontWeight.w700, fontSize: 11, fontFamily: 'Inter', letterSpacing: 1.5)),
          ),
          const SizedBox(height: 16),
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('TOOLS', style: TextStyle(color: t.textMuted.withValues(alpha: 0.7), fontWeight: FontWeight.w700, fontSize: 11, fontFamily: 'Inter', letterSpacing: 1.5)),
          ),
          const SizedBox(height: 12),
          _NavTile(icon: Icons.settings_rounded, label: 'Settings', isActive: false, onTap: () {}),
          _NavTile(icon: Icons.info_outline_rounded, label: 'About', isActive: false, onTap: () {}),
          const SizedBox(height: 24),
        ],
      ),
    );

    final hasDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;
    if (hasDrawer) {
      return Drawer(
        width: 250,
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          splashColor: t.primary.withValues(alpha: 0.1),
          highlightColor: t.primary.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isActive ? t.primary.withValues(alpha: 0.12) : Colors.transparent,
            ),
            child: Row(children: [
              Icon(icon, size: 22, color: isActive ? t.primary : t.textMuted.withValues(alpha: 0.8)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? t.primary : t.textSecondary, 
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, 
                    fontSize: 14, 
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              if (isActive)
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: t.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
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
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: t.primary.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: t.surfaceContainerLow,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: t.outlineVariant.withOpacity(0.3))),
            ),
            child: Text(title, style: TextStyle(color: t.primary, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
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

class _FeatureItem {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  final _MenuTab tab;
  const _FeatureItem(this.icon, this.title, this.desc, this.color, this.tab);
}
