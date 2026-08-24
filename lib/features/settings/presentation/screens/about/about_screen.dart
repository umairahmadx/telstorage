/// File: about_screen.dart
/// Description: About screen displaying application version, architecture highlights, and credits.
library;

import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';

/// Screen component showing app information and features overview.
class AboutScreen extends StatelessWidget {
  /// Constructs AboutScreen.
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About TelStorage',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: colors.accentPrimary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Icon(
                      Icons.cloud_queue_rounded,
                      color: colors.bgPrimary,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'TelStorage',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0 (Build 1)',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.borderSubtle, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unlimited Telegram Cloud Storage',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'TelStorage leverages the powerful Telegram Bot API as a secure, high-speed, unlimited cloud backend. Your files are automatically encrypted and indexed locally with offline-first sync.',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoSection(
            colors,
            title: 'Key Features',
            items: [
              '⚡ Sub-millisecond local-first optimistic operations',
              '📁 Cut, copy, move & folder tree file management',
              '🔄 Background sync engine with retry queue',
              '📊 Dedicated Sync Center & activity logs',
              '🎯 Zero-bandwidth local caching & thumbnail generation',
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Designed & Built with ❤️ for TelStorage',
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds information section box with bullet points.
  Widget _buildInfoSection(
    AppColorsExtension colors, {
    required String title,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                item,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
