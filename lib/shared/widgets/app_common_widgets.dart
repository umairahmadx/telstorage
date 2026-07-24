import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppSectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry? padding;
  final double fontSize;
  final Color? color;

  const AppSectionLabel(
    this.text, {
    super.key,
    this.padding,
    this.fontSize = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final label = Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: color ?? colors.textPrimary,
      ),
    );

    if (padding == null) return label;
    return Padding(padding: padding!, child: label);
  }
}

class AppEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  final EdgeInsetsGeometry padding;
  final double iconSize;

  const AppEmptyState({
    super.key,
    required this.message,
    required this.icon,
    this.padding = const EdgeInsets.only(top: 100),
    this.iconSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Padding(
      padding: padding,
      child: Column(
        children: [
          Center(child: Icon(icon, size: iconSize, color: colors.textTertiary)),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: colors.textTertiary)),
        ],
      ),
    );
  }
}

class AppProgressBar extends StatelessWidget {
  final double? value;
  final double minHeight;
  final double radius;
  final Color? valueColor;

  const AppProgressBar({
    super.key,
    required this.value,
    this.minHeight = 4,
    this.radius = 10,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LinearProgressIndicator(
        value: value,
        minHeight: minHeight,
        backgroundColor: colors.bgSurfaceInset,
        valueColor: AlwaysStoppedAnimation<Color>(
          valueColor ?? colors.accentPrimary,
        ),
      ),
    );
  }
}
