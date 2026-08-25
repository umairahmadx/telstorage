/*
 * File: app_segmented_control.dart
 * Description: Component and logic definition for app_segmented_control.dart in TelStorage.
 */

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppSegment<T> {
  final T value;
  final String label;

  const AppSegment({required this.value, required this.label});
}

class AppSegmentedControl<T> extends StatelessWidget {
  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;
  final double height;
  final double radius;
  final double fontSize;

  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.height = 48,
    this.radius = 24,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Padding(
      padding: padding,
      child: SizedBox(
        height: height,
        child: Row(
          children: segments.map((segment) {
            final isSelected = segment.value == value;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(segment.value),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.accentPrimary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: Text(
                    segment.label,
                    style: TextStyle(
                      color: isSelected
                          ? colors.bgPrimary
                          : colors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
