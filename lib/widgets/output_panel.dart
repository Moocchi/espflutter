import 'package:flutter/material.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../providers/app_state.dart';
import 'app_toast.dart';

class OutputPanel extends StatefulWidget {
  const OutputPanel({super.key});

  @override
  State<OutputPanel> createState() => _OutputPanelState();
}

class _OutputPanelState extends State<OutputPanel> {
  late TextEditingController _identifierCtrl;

  @override
  void initState() {
    super.initState();
    _identifierCtrl = TextEditingController(text: 'epd_bitmap_');
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    super.dispose();
  }

  void _update(AppSettings Function(AppSettings) fn, {String? description}) {
    final state = context.read<AppState>();
    state.updateSettings(fn(state.settings), changeDescription: description);
  }

  void _showSaveSnack(String msg, {bool error = false}) {
    AppToast.show(context, msg, isError: error);
  }

  Future<String?> _showRenameDialog(String defaultName) async {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: GanciColors.surfaceContainer,
        title: const Text('Rename Output', style: TextStyle(color: GanciColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: GanciColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Nama file/folder',
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
    final s = state.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [


        // --- Draw Mode ---
        _sectionTitle('Draw Mode'),
        _dropdownRow<DrawMode>(
          value: s.drawMode,
          items: const [
            DropdownMenuItem(
                value: DrawMode.horizontal1bit,
              child: Text('Horizontal - 1 bit/px')),
            DropdownMenuItem(
                value: DrawMode.vertical1bit,
              child: Text('Vertical - 1 bit/px')),
            DropdownMenuItem(
                value: DrawMode.horizontal565,
              child: Text('Horizontal - RGB565 (2 bytes/px)')),
            DropdownMenuItem(
                value: DrawMode.horizontalAlpha,
              child: Text('Horizontal - Alpha map (1 bit/px)')),
            DropdownMenuItem(
                value: DrawMode.horizontal888,
              child: Text('Horizontal - RGB888 Pure (3 bytes/px)')),
          ],
          onChanged: (v) {
            if (v != null) _update((s) => s.copyWith(drawMode: v),
              description: 'Draw mode -> ${v.name}');
          },
        ),
        const SizedBox(height: 12),



        // --- Info note ---
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: GanciColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: GanciColors.glassBorder),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: GanciColors.primary, size: 14),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'File disimpan di: Download/image2cpp/\n'
                  'GIF -> ada Subfolder untuk setiap frame',
                  style: TextStyle(
                      color: GanciColors.textMuted, fontSize: 11, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        const SizedBox(height: 24),

        // --- Save Buttons at Bottom ---
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _actionButton(
              icon: Icons.save,
              label: 'Save .bin',
              onTap: state.loadedFiles.isEmpty
                  ? null
                  : () async {
                      // Show rename dialog
                      final defaultName = state.loadedFiles.first.name.split('.').first;
                      final customName = await _showRenameDialog(defaultName);
                      if (customName == null) return; // User cancelled
                      
                      final result = await state.saveBinFiles(
                        customName: customName.isEmpty ? null : customName,
                      );
                      if (!mounted) return;
                      if (result.path.isEmpty) {
                        _showSaveSnack('No frames to export', error: true);
                      } else {
                        _showSaveSnack('${result.fileName} disimpan');
                        state.clearFiles();
                        if (mounted) {
                          AppToast.showWithAction(
                            context,
                            'Upload file?',
                            actionLabel: 'Upload',
                            onAction: () => state.onNavigateToUpload?.call(),
                            durationMs: 5000,
                            delayMs: 2500,
                          );
                        }
                      }
                    },
            ),
            _actionButton(
              icon: Icons.bolt,
              label: 'Save .qoi',
              onTap: state.loadedFiles.isEmpty
                  ? null
                  : () async {
                      // Show rename dialog
                      final defaultName = state.loadedFiles.first.name.split('.').first;
                      final customName = await _showRenameDialog(defaultName);
                      if (customName == null) return; // User cancelled
                      
                      final result = await state.saveQoiFiles(
                        customName: customName.isEmpty ? null : customName,
                      );
                      if (!mounted) return;
                      if (result.path.isEmpty) {
                        _showSaveSnack('No frames to export', error: true);
                      } else {
                        _showSaveSnack('${result.fileName} disimpan');
                        state.clearFiles();
                        if (mounted) {
                          AppToast.showWithAction(
                            context,
                            'Upload file?',
                            actionLabel: 'Upload',
                            onAction: () => state.onNavigateToUpload?.call(),
                            durationMs: 5000,
                            delayMs: 2500,
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: GanciColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );

  Widget _dropdownRow<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        dropdownColor: GanciColors.surfaceContainer,
        style: const TextStyle(
          color: GanciColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          filled: true,
          fillColor: GanciColors.surfaceContainerHigh,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: GanciColors.glassBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: GanciColors.glassBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: GanciColors.primary, width: 1.4)),
        ),
        iconEnabledColor: GanciColors.primary,
        items: items,
        onChanged: onChanged,
      );

  Widget _checkboxRow(
          String label, bool value, ValueChanged<bool?> onChanged) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: GanciColors.primary,
              checkColor: GanciColors.surfaceContainer,
              side: BorderSide(color: GanciColors.outlineVariant)),
          Text(label,
                style: const TextStyle(
                  color: GanciColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      );

  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) =>
      AnimatedOpacity(
        opacity: onTap == null ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: GanciColors.primary,
                  width: 1.6,
                ),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [GanciColors.surfaceContainer, GanciColors.surfaceContainerHigh],
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: GanciColors.primary),
                    const SizedBox(width: 8),
                    Text(label,
                        style: const TextStyle(
                            color: GanciColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

