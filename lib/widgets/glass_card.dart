import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool showGlow;

  const GlassCard({super.key, required this.child, this.padding,
    this.borderRadius = 16, this.showGlow = false});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showGlow ? [BoxShadow(
          color: t.primary.withOpacity(0.10),
          blurRadius: 20, spreadRadius: 2,
        )] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.glassCard,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: t.glassBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassSectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final IconData? icon;

  const GlassSectionCard({super.key, required this.title, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = GanciTheme.of(context);
    return Container(
      width: double.infinity,
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
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: t.primaryLight), const SizedBox(width: 10)],
              Text(title, style: TextStyle(color: t.primaryLight, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }
}
