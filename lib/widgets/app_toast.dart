import 'dart:async';
import 'package:flutter/material.dart';

class AppToast {
  static OverlayEntry? _current;
  static Timer? _autoTimer;
  static GlobalKey<_ToastWidgetState>? _activeKey;
  static String? _lastMessage;

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    int? durationMs,
  }) {
    _showInternal(context, message, isError: isError, durationMs: durationMs);
  }

  /// Show a toast with a tappable action label (like "Upload").
  /// [delayMs] waits before showing, so the previous toast has time to fade.
  static void showWithAction(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
    int durationMs = 5000,
    int delayMs = 0,
  }) {
    if (delayMs > 0) {
      Timer(Duration(milliseconds: delayMs), () {
        if (!context.mounted) return;
        _showInternal(
          context, message,
          actionLabel: actionLabel,
          onAction: onAction,
          durationMs: durationMs,
        );
      });
    } else {
      _showInternal(
        context, message,
        actionLabel: actionLabel,
        onAction: onAction,
        durationMs: durationMs,
      );
    }
  }

  static void _showInternal(
    BuildContext context,
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
    int? durationMs,
  }) {
    if (!context.mounted) return;

    // Dedup: if same message is already shown, just reset the timer
    if (_current != null && _activeKey?.currentState != null && !(_activeKey!.currentState!._dismissed)) {
      if (_lastMessage == message) {
        _autoTimer?.cancel();
        final dur = durationMs ?? (isError ? 2400 : 2200);
        _autoTimer = Timer(
          Duration(milliseconds: dur),
          () {
            _activeKey?.currentState?.fadeOut();
          },
        );
        return;
      }
    }
    _lastMessage = message;

    // Always cancel pending auto-dismiss
    _autoTimer?.cancel();
    _autoTimer = null;

    // Remove the old toast immediately (no stacking)
    final oldEntry = _current;
    final oldKey = _activeKey;
    _current = null;
    _activeKey = null;

    // Synchronously kill old toast widget to prevent overlap
    if (oldKey?.currentState != null && !(oldKey!.currentState!._dismissed)) {
      oldKey.currentState!._dismissed = true;
    }
    try { oldEntry?.remove(); } catch (_) {}

    final key = GlobalKey<_ToastWidgetState>();
    _activeKey = key;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        key: key,
        message: message,
        isError: isError,
        actionLabel: actionLabel,
        onAction: onAction != null ? () {
          onAction();
          // dismiss after tap
          key.currentState?.fadeOut();
        } : null,
        onDismissed: () {
          try { entry.remove(); } catch (_) {}
          if (_current == entry) {
            _current = null;
            _activeKey = null;
          }
        },
      ),
    );

    _current = entry;
    Overlay.of(context).insert(entry);

    // Processing/generating/loading messages stay pinned until replaced
    final isPinned = message.toLowerCase().contains('processing') ||
        message.toLowerCase().contains('generating') ||
        message.toLowerCase().contains('loading');

    if (!isPinned) {
      final dur = durationMs ?? (isError ? 2400 : 2200);
      _autoTimer = Timer(
        Duration(milliseconds: dur),
        () {
          _activeKey?.currentState?.fadeOut();
        },
      );
    }
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismissed;

  const _ToastWidget({
    super.key,
    required this.message,
    required this.isError,
    this.actionLabel,
    this.onAction,
    required this.onDismissed,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _slide;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<double>(begin: -80, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();
  }

  Future<void> fadeOut() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    try {
      await _ctrl.reverse();
    } catch (_) {}
    if (mounted) widget.onDismissed();
  }

  void fastFadeOut() {
    if (_dismissed) return;
    _dismissed = true;
    _ctrl
        .animateTo(0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeIn)
        .then((_) {
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseBottom = MediaQuery.of(context).padding.bottom + 44;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // _slide.value: -80 → 0, so bottom goes from (base-80) → base (slides up)
        final bottom = baseBottom + _slide.value;
        final hasAction = widget.actionLabel != null;
        final innerContent = Material(
            color: Colors.transparent,
            child: FadeTransition(
              opacity: _fade,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: IntrinsicWidth(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE7E8EC)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                color: Color(0xFF22252F),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.fade,
                              softWrap: true,
                              textAlign: TextAlign.left,
                            ),
                          ),
                          if (hasAction) ...[
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: widget.onAction,
                              child: Text(
                                widget.actionLabel!,
                                style: const TextStyle(
                                  color: Color(0xFF6252E7),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        );
        return Positioned(
          bottom: bottom,
          left: 0,
          right: 0,
          child: hasAction ? innerContent : IgnorePointer(child: innerContent),
        );
      },
    );
  }
}
