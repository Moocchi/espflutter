import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../providers/app_state.dart';
import '../esp_bridge/services/ble_service.dart';
import 'app_toast.dart';

class SettingsPanel extends StatefulWidget {
  final bool showBluetooth;
  final bool showImageSettings;
  const SettingsPanel({
    super.key,
    this.showBluetooth = false,
    this.showImageSettings = true,
  });

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

  final BleService _ble = BleService();
  BleStatus _bleStatus = BleStatus.disconnected;
  StreamSubscription? _bleSub;
  late TextEditingController _btNameCtrl;
  bool _isSavingBt = false;
  bool _isOnCooldown = false;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _wCtrl = TextEditingController(text: s.canvasWidth.toString());
    _hCtrl = TextEditingController(text: s.canvasHeight.toString());
    _thresholdCtrl =
        TextEditingController(text: s.ditheringThreshold.toString());

    _bleStatus = _ble.currentStatus;
    _bleSub = _ble.statusStream.listen((status) {
      if (mounted) setState(() => _bleStatus = status);
    });
    _btNameCtrl = TextEditingController();
    _ble.getTargetDevName().then((val) {
      if (mounted) _btNameCtrl.text = val;
    });

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
    _bleSub?.cancel();
    _btNameCtrl.dispose();
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
    final t = GanciTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showBluetooth) _buildBluetoothSection(t),
        if (widget.showImageSettings) ...[
          if (widget.showBluetooth) const SizedBox(height: 16),
          // --- Canvas Size ---
          _sectionTitle('Canvas Size', t),
          Row(
            children: [
              _numField(_wCtrl, _wFocus, 'Width', (v) {
                _applyWidth();
                _hFocus.requestFocus(); // Move to height field
              }, t),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('x', style: TextStyle(color: t.primaryLight))),
              _numField(_hCtrl, _hFocus, 'Height', (v) {
                _applyHeight();
                FocusScope.of(context).unfocus(); // Close keyboard
                _forceApplyCanvasSize(); // Apply both
              }, t),
              Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('px', style: TextStyle(color: t.textMuted))),
            ],
          ),
          const SizedBox(height: 16),

          // --- Anti-Alias ---
          _sectionTitle('Anti-Aliasing', t),
          _dropdownRow<AntiAliasMode>(
            value: s.antiAlias,
            t: t,
            items: const [
              DropdownMenuItem(
                  value: AntiAliasMode.smart, child: Text('Smart (auto smooth)')),
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
          _sectionTitle('Scaling', t),
          _dropdownRow<ScaleMode>(
            value: s.scale,
            t: t,
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
          _sectionTitle('Center Image', t),
          Row(
            children: [
              _checkboxRow(
                  'Horizontally',
                  s.centerHorizontally,
                  (v) =>
                      _update((s) => s.copyWith(centerHorizontally: v ?? false),
                      description: 'Center H -> ${(v ?? false) ? 'ON' : 'OFF'}'), t),
              const SizedBox(width: 24),
              _checkboxRow(
                  'Vertically',
                  s.centerVertically,
                  (v) =>
                      _update((s) => s.copyWith(centerVertically: v ?? false),
                      description: 'Center V -> ${(v ?? false) ? 'ON' : 'OFF'}'), t),
            ],
          ),
          const SizedBox(height: 16),

          // --- Rotation ---
          _sectionTitle('Rotate Image', t),
          _radioRow<int>(
            options: [0, 90, 180, 270],
            labels: ['0 deg', '90 deg', '180 deg', '270 deg'],
            current: s.rotation,
            t: t,
            onChanged: (v) => _update((s) => s.copyWith(rotation: v),
                description: 'Rotation -> $v deg'),
          ),
          const SizedBox(height: 16),

          // --- Flip ---
          _sectionTitle('Flip Image', t),
          Row(
            children: [
              _checkboxRow(
                  'Horizontally',
                  s.flipHorizontally,
                  (v) =>
                      _update((s) => s.copyWith(flipHorizontally: v ?? false),
                      description: 'Flip H -> ${(v ?? false) ? 'ON' : 'OFF'}'), t),
              const SizedBox(width: 24),
              _checkboxRow('Vertically', s.flipVertically,
                  (v) => _update((s) => s.copyWith(flipVertically: v ?? false),
                    description: 'Flip V -> ${(v ?? false) ? 'ON' : 'OFF'}'), t),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(String text, GanciTheme t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                color: t.primary,
                fontWeight: FontWeight.bold,
            fontSize: 13)),
      );

  Widget _numField(TextEditingController ctrl, FocusNode focusNode,
          String label, ValueChanged<String> onSubmitted, GanciTheme t) =>
      SizedBox(
        width: 72,
        child: TextField(
          controller: ctrl,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: label,
          labelStyle: TextStyle(color: t.textMuted, fontSize: 11),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            filled: true,
          fillColor: t.surfaceContainerHigh,
            border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.glassBorder)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.glassBorder)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.primary, width: 1.4)),
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
    required GanciTheme t,
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
                            return t.primary;
                          }
                          return t.outlineVariant;
                        }),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text(labels[i],
                          style: TextStyle(
                              color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                )),
      );

  Widget _dropdownRow<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required GanciTheme t,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        dropdownColor: t.surfaceContainer,
        style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          filled: true,
          fillColor: t.surfaceContainerHigh,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.glassBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.glassBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: t.primary, width: 1.4)),
        ),
        iconEnabledColor: t.primary,
        items: items,
        onChanged: onChanged,
      );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(
        children: [
          Switch(
              value: value,
              onChanged: onChanged,
              activeColor: GanciColors.primary,
              activeTrackColor: GanciColors.glassBorder,
              inactiveThumbColor: GanciColors.outlineVariant,
              inactiveTrackColor: GanciColors.outlineVariant),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(color: GanciColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      );

  Widget _buildBluetoothSection(GanciTheme t) {
    Color statusColor = t.textMuted;
    String statusText = 'Disconnected';
    IconData icon = Icons.bluetooth_disabled_rounded;

    if (_bleStatus == BleStatus.connected) {
      statusColor = t.primary;
      statusText = 'Connected';
      icon = Icons.bluetooth_connected_rounded;
    } else if (_bleStatus == BleStatus.connecting || _bleStatus == BleStatus.scanning) {
      statusColor = t.primaryLight;
      statusText = 'Syncing...';
      icon = Icons.bluetooth_searching_rounded;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('ESP32 Bluetooth Bridge', t),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Status Koneksi', style: TextStyle(color: t.textMuted, fontSize: 11, fontFamily: 'Inter')),
                        const SizedBox(height: 2),
                        Text(statusText, style: TextStyle(color: statusColor, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Inter')),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _bleStatus == BleStatus.connected ? t.surfaceContainerLow : t.primary,
                      foregroundColor: _bleStatus == BleStatus.connected ? t.textPrimary : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onPressed: () async {
                      if (_bleStatus == BleStatus.connected) {
                        _ble.disconnect();
                      } else {
                        final isOn = await _ble.isBluetoothOn();
                        if (!isOn && mounted) {
                          final wantTurnOn = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: GanciTheme.of(ctx).surfaceContainerHigh,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              title: Row(
                                children: [
                                  Icon(Icons.bluetooth_disabled_rounded, color: GanciTheme.of(ctx).primary),
                                  const SizedBox(width: 10),
                                  const Text('Bluetooth Tidak Aktif', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Inter')),
                                ],
                              ),
                              content: const Text(
                                'Bluetooth di HP Anda sedang tidak nyala. Apakah Anda ingin menyalakan Bluetooth sekarang langsung dari aplikasi tanpa perlu membuka pusat kontrol?',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 14),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('Batal', style: TextStyle(color: GanciTheme.of(ctx).textSecondary, fontFamily: 'Inter')),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: GanciTheme.of(ctx).primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  icon: const Icon(Icons.bluetooth_rounded, size: 16),
                                  label: const Text('Nyalakan Bluetooth', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Inter')),
                                ),
                              ],
                            ),
                          );
                          if (wantTurnOn == true) {
                            if (mounted) {
                              AppToast.show(context, 'Menyalakan Bluetooth dari aplikasi...');
                            }
                            final success = await _ble.turnOnBluetooth();
                            if (success) {
                              if (mounted) {
                                AppToast.show(context, 'Bluetooth berhasil aktif! Mencoba menghubungkan...');
                              }
                              _ble.scanAndConnect();
                            } else if (mounted) {
                              AppToast.show(context, 'Gagal menyalakan Bluetooth otomatis. Silakan nyalakan secara manual.', isError: true);
                            }
                          }
                        } else {
                          _ble.scanAndConnect();
                        }
                      }
                    },
                    icon: Icon(_bleStatus == BleStatus.connected ? Icons.link_off_rounded : Icons.bluetooth_searching_rounded, size: 16),
                    label: Text(_bleStatus == BleStatus.connected ? 'Putuskan' : 'Hubungkan', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Inter')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: t.glassBorder, height: 1),
              const SizedBox(height: 16),
              Text('Ganti Nama Bluetooth ESP32 (Max 24 kar):', style: TextStyle(color: t.textSecondary, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _btNameCtrl,
                      maxLength: 24,
                      style: TextStyle(color: t.textPrimary, fontSize: 13, fontFamily: 'Inter'),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Nama Bluetooth ESP32',
                        hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: t.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.glassBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.glassBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: t.primary, width: 1.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (_bleStatus != BleStatus.connected || _isSavingBt || _isOnCooldown) ? t.surfaceContainerHigh : t.primary,
                      foregroundColor: (_bleStatus != BleStatus.connected || _isSavingBt || _isOnCooldown) ? t.textMuted : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: (_bleStatus != BleStatus.connected || _isSavingBt || _isOnCooldown) ? null : _saveBtName,
                    child: _isSavingBt
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            _isOnCooldown ? 'Tunggu (${_cooldownSeconds}s)' : 'Simpan',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Inter'),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: t.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mengganti nama akan merestart modul ESP32 otomatis dan aplikasi auto-reconnect ke nama baru.',
                        style: TextStyle(color: t.textMuted, fontSize: 11, fontFamily: 'Inter'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _saveBtName() async {
    if (_bleStatus != BleStatus.connected || _isSavingBt || _isOnCooldown) return;
    final newName = _btNameCtrl.text.trim();
    if (newName.isEmpty || newName.length > 24) return;
    setState(() => _isSavingBt = true);

    final ok = await _ble.changeDeviceName(newName);
    if (ok && mounted) {
      AppToast.show(context, 'ESP32 restart... Auto-connect ke "$newName"');
      await _ble.saveTargetDevName(newName);
      setState(() {
        _isSavingBt = false;
        _isOnCooldown = true;
        _cooldownSeconds = 5;
      });
      // Cooldown timer 5 detik
      for (int i = 5; i > 0; i--) {
        if (!mounted) return;
        setState(() => _cooldownSeconds = i);
        await Future.delayed(const Duration(seconds: 1));
      }
      if (mounted) {
        setState(() {
          _isOnCooldown = false;
          _cooldownSeconds = 0;
        });
        _ble.scanAndConnect();
      }
    } else if (mounted) {
      AppToast.show(context, 'Gagal mengganti nama BLE', isError: true);
      setState(() => _isSavingBt = false);
    }
  }

  Widget _checkboxRow(
          String label, bool value, ValueChanged<bool?> onChanged, GanciTheme t) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: t.primary,
              checkColor: t.surfaceContainer,
              side: BorderSide(color: t.outlineVariant)),
          Text(label,
              style: TextStyle(color: t.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      );
}

