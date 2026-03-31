import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../providers/app_state.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late TextEditingController _wCtrl;
  late TextEditingController _hCtrl;
  late TextEditingController _thresholdCtrl;

  final FocusNode _wFocus = FocusNode();
  final FocusNode _hFocus = FocusNode();
  final FocusNode _threshFocus = FocusNode();
  
  // Track if canvas size was modified
  bool _canvasSizeModified = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _wCtrl = TextEditingController(text: s.canvasWidth.toString());
    _hCtrl = TextEditingController(text: s.canvasHeight.toString());
    _thresholdCtrl =
        TextEditingController(text: s.ditheringThreshold.toString());

    // Auto-apply when focus is lost
    _wFocus.addListener(() {
      if (!_wFocus.hasFocus && _canvasSizeModified) {
        _applyCanvasSize();
      }
    });
    _hFocus.addListener(() {
      if (!_hFocus.hasFocus && _canvasSizeModified) {
        _applyCanvasSize();
      }
    });
    _threshFocus.addListener(() {
      if (!_threshFocus.hasFocus) _applyThreshold();
    });
  }
  
  void _applyCanvasSize() {
    // Only apply if both fields have lost focus
    if (_wFocus.hasFocus || _hFocus.hasFocus) return;
    _forceApplyCanvasSize();
  }
  
  void _forceApplyCanvasSize() {
    final w = int.tryParse(_wCtrl.text);
    final h = int.tryParse(_hCtrl.text);
    if (w != null && w > 0 && h != null && h > 0) {
      final state = context.read<AppState>();
      state.updateSettings(state.settings.copyWith(
        canvasWidth: w,
        canvasHeight: h,
      ), changeDescription: 'Canvas -> ${w}x${h}');
    }
    _canvasSizeModified = false;
  }

  void _applyWidth() {
    final n = int.tryParse(_wCtrl.text);
    if (n != null && n > 0) {
      _canvasSizeModified = true;
      // Quick update without processing
      final state = context.read<AppState>();
      state.updateSettingsQuick(state.settings.copyWith(canvasWidth: n));
    }
  }

  void _applyHeight() {
    final n = int.tryParse(_hCtrl.text);
    if (n != null && n > 0) {
      _canvasSizeModified = true;
      // Quick update without processing
      final state = context.read<AppState>();
      state.updateSettingsQuick(state.settings.copyWith(canvasHeight: n));
    }
  }

  void _applyThreshold() {
    final n = int.tryParse(_thresholdCtrl.text);
    if (n != null)
      _update((s) => s.copyWith(ditheringThreshold: n.clamp(0, 255)));
  }

  @override
  void dispose() {
    _wFocus.dispose();
    _hFocus.dispose();
    _threshFocus.dispose();
    _wCtrl.dispose();
    _hCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<AppState>().settings;
    if (!_wFocus.hasFocus && _wCtrl.text != s.canvasWidth.toString()) {
      _wCtrl.text = s.canvasWidth.toString();
    }
    if (!_hFocus.hasFocus && _hCtrl.text != s.canvasHeight.toString()) {
      _hCtrl.text = s.canvasHeight.toString();
    }
    if (!_threshFocus.hasFocus &&
        _thresholdCtrl.text != s.ditheringThreshold.toString()) {
      _thresholdCtrl.text = s.ditheringThreshold.toString();
    }
  }

  void _update(AppSettings Function(AppSettings) fn, {String? description}) {
    final state = context.read<AppState>();
    state.updateSettings(fn(state.settings), changeDescription: description);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Canvas Size ---
        _sectionTitle('Canvas Size'),
        Row(
          children: [
            _numField(_wCtrl, _wFocus, 'Width', (v) {
              _applyWidth();
              _hFocus.requestFocus(); // Move to height field
            }),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('x', style: TextStyle(color: Color(0xFF4C42CF)))),
            _numField(_hCtrl, _hFocus, 'Height', (v) {
              _applyHeight();
              FocusScope.of(context).unfocus(); // Close keyboard
              _forceApplyCanvasSize(); // Apply both
            }),
            const Padding(
                padding: EdgeInsets.only(left: 8),
              child: Text('px', style: TextStyle(color: Color(0xFF6D7385)))),
          ],
        ),
        const SizedBox(height: 16),

        // --- Background Color ---
        _sectionTitle('Background Color'),
        _radioRow<BackgroundColor>(
          options: [
            BackgroundColor.white,
            BackgroundColor.black,
            BackgroundColor.transparent
          ],
          labels: ['White', 'Black', 'Transparent'],
          current: s.backgroundColor,
          onChanged: (v) => _update((s) => s.copyWith(backgroundColor: v),
              description: 'Background -> ${v.name}'),
        ),
        const SizedBox(height: 16),

        // --- Invert Colors ---
        _switchRow('Invert image colors', s.invertColors,
            (v) => _update((s) => s.copyWith(invertColors: v),
            description: v ? 'Invert -> ON' : 'Invert -> OFF')),
        const SizedBox(height: 16),

        // --- Dithering ---
        _sectionTitle('Dithering'),
        _dropdownRow<DitheringMode>(
          value: s.ditheringMode,
          items: const [
            DropdownMenuItem(
                value: DitheringMode.binary, child: Text('Binary')),
            DropdownMenuItem(value: DitheringMode.bayer, child: Text('Bayer')),
            DropdownMenuItem(
                value: DitheringMode.floydSteinberg,
                child: Text('Floyd-Steinberg')),
            DropdownMenuItem(
                value: DitheringMode.atkinson, child: Text('Atkinson')),
          ],
          onChanged: (v) {
            if (v != null) _update((s) => s.copyWith(ditheringMode: v),
                description: 'Dithering -> ${v.name}');
          },
        ),
        const SizedBox(height: 8),
        _sectionTitle('Brightness / Alpha Threshold (0-255)'),
        _numField(_thresholdCtrl, _threshFocus, 'Threshold',
            (v) => _applyThreshold()),
        const SizedBox(height: 16),

        // --- Anti-Alias ---
        _sectionTitle('Anti-Aliasing'),
        _dropdownRow<AntiAliasMode>(
          value: s.antiAlias,
          items: const [
            DropdownMenuItem(
                value: AntiAliasMode.nearest, child: Text('Nearest (sharp)')),
            DropdownMenuItem(
                value: AntiAliasMode.linear, child: Text('Linear')),
            DropdownMenuItem(
                value: AntiAliasMode.cubic, child: Text('Cubic (smooth)')),
            DropdownMenuItem(
                value: AntiAliasMode.average, child: Text('Average')),
            DropdownMenuItem(
                value: AntiAliasMode.gaussian3x3,
                child: Text('Gaussian 3x3 (soft)')),
          ],
          onChanged: (v) {
            if (v != null) _update((s) => s.copyWith(antiAlias: v),
                description: 'Anti-Alias -> ${v.name}');
          },
        ),
        const SizedBox(height: 16),

        // --- Scale ---
        _sectionTitle('Scaling'),
        _dropdownRow<ScaleMode>(
          value: s.scale,
          items: const [
            DropdownMenuItem(
                value: ScaleMode.original, child: Text('Original size')),
            DropdownMenuItem(
                value: ScaleMode.scaleToFit,
                child: Text('Scale to fit (keep ratio)')),
            DropdownMenuItem(
                value: ScaleMode.stretchToFill,
                child: Text('Stretch to fill canvas')),
            DropdownMenuItem(
                value: ScaleMode.stretchHorizontally,
                child: Text('Stretch horizontally')),
            DropdownMenuItem(
                value: ScaleMode.stretchVertically,
                child: Text('Stretch vertically')),
          ],
          onChanged: (v) {
            if (v != null) _update((s) => s.copyWith(scale: v),
                description: 'Scale -> ${v.name}');
          },
        ),
        const SizedBox(height: 16),

        // --- Center ---
        _sectionTitle('Center Image'),
        Row(
          children: [
            _checkboxRow(
                'Horizontally',
                s.centerHorizontally,
                (v) =>
                    _update((s) => s.copyWith(centerHorizontally: v ?? false),
                    description: 'Center H -> ${(v ?? false) ? 'ON' : 'OFF'}')),
            const SizedBox(width: 24),
            _checkboxRow(
                'Vertically',
                s.centerVertically,
                (v) =>
                    _update((s) => s.copyWith(centerVertically: v ?? false),
                    description: 'Center V -> ${(v ?? false) ? 'ON' : 'OFF'}')),
          ],
        ),
        const SizedBox(height: 16),

        // --- Rotation ---
        _sectionTitle('Rotate Image'),
        _radioRow<int>(
          options: [0, 90, 180, 270],
          labels: ['0 deg', '90 deg', '180 deg', '270 deg'],
          current: s.rotation,
          onChanged: (v) => _update((s) => s.copyWith(rotation: v),
              description: 'Rotation -> $v deg'),
        ),
        const SizedBox(height: 16),

        // --- Flip ---
        _sectionTitle('Flip Image'),
        Row(
          children: [
            _checkboxRow(
                'Horizontally',
                s.flipHorizontally,
                (v) =>
                    _update((s) => s.copyWith(flipHorizontally: v ?? false),
                    description: 'Flip H -> ${(v ?? false) ? 'ON' : 'OFF'}')),
            const SizedBox(width: 24),
            _checkboxRow('Vertically', s.flipVertically,
                (v) => _update((s) => s.copyWith(flipVertically: v ?? false),
                  description: 'Flip V -> ${(v ?? false) ? 'ON' : 'OFF'}')),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF6252E7),
                fontWeight: FontWeight.bold,
            fontSize: 13)),
      );

  Widget _numField(TextEditingController ctrl, FocusNode focusNode,
          String label, ValueChanged<String> onSubmitted) =>
      SizedBox(
        width: 72,
        child: TextField(
          controller: ctrl,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Color(0xFF2F3445), fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF8E85ED), fontSize: 11),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            filled: true,
          fillColor: const Color(0xFFF7F5FF),
            border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFC9C3FF))),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFC9C3FF))),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF6252E7), width: 1.4)),
          ),
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.done,
        ),
      );

  Widget _radioRow<T>({
    required List<T> options,
    required List<String> labels,
    required T current,
    required ValueChanged<T> onChanged,
  }) =>
      Wrap(
        spacing: 16,
        children: List.generate(
            options.length,
            (i) => GestureDetector(
                  onTap: () => onChanged(options[i]),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Radio<T>(
                        value: options[i],
                        groupValue: current,
                        onChanged: (v) {
                          if (v != null) onChanged(v);
                        },
                        fillColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return const Color(0xFF6252E7);
                          }
                          return const Color(0xFFB4B9C8);
                        }),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text(labels[i],
                          style: const TextStyle(
                              color: Color(0xFF474C5E), fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                )),
      );

  Widget _dropdownRow<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        dropdownColor: Colors.white,
        style: const TextStyle(color: Color(0xFF2F3445), fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          filled: true,
          fillColor: const Color(0xFFF7F5FF),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFC9C3FF))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFC9C3FF))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF6252E7), width: 1.4)),
        ),
        iconEnabledColor: const Color(0xFF6252E7),
        items: items,
        onChanged: onChanged,
      );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(
        children: [
          Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF6252E7),
              activeTrackColor: const Color(0xFFC9C3FF),
              inactiveThumbColor: const Color(0xFFB4B9C8),
              inactiveTrackColor: const Color(0xFFE7E8F3)),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(color: Color(0xFF474C5E), fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      );

  Widget _checkboxRow(
          String label, bool value, ValueChanged<bool?> onChanged) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF6252E7),
              checkColor: Colors.white,
              side: const BorderSide(color: Color(0xFFB4B9C8))),
          Text(label,
              style: const TextStyle(color: Color(0xFF474C5E), fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      );
}

