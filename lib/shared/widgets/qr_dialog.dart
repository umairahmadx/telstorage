/*
 * File: qr_dialog.dart
 * Description: Component and logic definition for qr_dialog.dart in TelStorage.
 */

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';

class QrDialog extends StatelessWidget {
  final String data;
  final String title;

  const QrDialog({
    super.key,
    required this.data,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return AlertDialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(
        title,
        style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: data,
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            data,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close',
              style: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
