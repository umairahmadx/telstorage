/// File: app_search_field.dart
/// Description: Component and logic definition for app_search_field.dart in TelStorage.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final bool autofocus;

  const AppSearchField({
    super.key,
    required this.hintText,
    this.onChanged,
    this.controller,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(25),
        ),
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          style: TextStyle(color: colors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
            prefixIcon:
                Icon(Icons.search_rounded, color: colors.textTertiary, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}
