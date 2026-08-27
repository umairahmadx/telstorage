/*
 * File: share_link_options_section.dart
 * Description: Modular form section configuring expiration duration, optional password protection, and custom vanity slug for public web shares.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// Form inputs for configuring link expiry, password lock, and vanity URL aliases.
class ShareLinkOptionsSection extends StatelessWidget {
  final int expiryDays;
  final ValueChanged<int> onExpiryDaysChanged;
  final bool setPassword;
  final ValueChanged<bool> onSetPasswordChanged;
  final TextEditingController passwordController;
  final TextEditingController slugController;

  const ShareLinkOptionsSection({
    super.key,
    required this.expiryDays,
    required this.onExpiryDaysChanged,
    required this.setPassword,
    required this.onSetPasswordChanged,
    required this.passwordController,
    required this.slugController,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy')
        .format(DateTime.now().add(Duration(days: expiryDays)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expires',
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 12),
        PopupMenuButton<int>(
          onSelected: (days) {
            HapticFeedback.selectionClick();
            onExpiryDaysChanged(days);
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 1, child: Text('In 1 day')),
            PopupMenuItem(value: 3, child: Text('In 3 days')),
            PopupMenuItem(value: 7, child: Text('In 7 days')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(AppIcons.calendar, size: 20, color: colors.textTertiary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'In $expiryDays days',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(AppIcons.dropdownArrow, color: colors.textTertiary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Password (Optional)',
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(AppIcons.lock, size: 20, color: colors.textTertiary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Set password',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Switch(
                value: setPassword,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  onSetPasswordChanged(v);
                },
                activeTrackColor: colors.accentPrimary,
                activeThumbColor: colors.bgPrimary,
              ),
            ],
          ),
        ),
        if (setPassword) ...[
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            obscureText: true,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Enter password',
              hintStyle: TextStyle(color: colors.textTertiary),
              filled: true,
              fillColor: colors.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Custom Vanity Link (Optional)',
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: slugController,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            prefixText: 'storage.to/v/',
            prefixStyle: TextStyle(
              color: colors.accentPrimary,
              fontWeight: FontWeight.bold,
            ),
            hintText: 'my-custom-alias',
            hintStyle: TextStyle(color: colors.textTertiary),
            filled: true,
            fillColor: colors.bgSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
