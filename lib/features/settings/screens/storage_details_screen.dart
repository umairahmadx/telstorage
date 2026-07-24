import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/bloc/home_cubit.dart';

class StorageDetailsScreen extends StatelessWidget {
  const StorageDetailsScreen({super.key});

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
          'Storage & Cloud Details',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          final usedMb = state.storageUsedMb;
          final usedText = usedMb >= 1024
              ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
              : '${usedMb.toStringAsFixed(0)} MB';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.bgSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.borderSubtle, width: 1),
                ),
                child: Column(
                  children: [
                    Icon(Icons.cloud_done_rounded, size: 48, color: colors.accentPrimary),
                    const SizedBox(height: 12),
                    Text(
                      usedText,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Used of Unlimited Storage',
                      style: TextStyle(fontSize: 14, color: colors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (usedMb / 102400).clamp(0.02, 1.0),
                        minHeight: 8,
                        backgroundColor: colors.bgSurfaceInset,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Cloud Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildTile(
                colors,
                icon: Icons.check_circle_rounded,
                iconColor: colors.success,
                title: 'Telegram Storage Channel',
                subtitle: 'Active & Connected',
              ),
              _buildTile(
                colors,
                icon: Icons.shield_rounded,
                iconColor: colors.accentPrimary,
                title: 'Data Integrity',
                subtitle: 'SHA-256 Verified',
              ),
              _buildTile(
                colors,
                icon: Icons.offline_bolt_rounded,
                iconColor: colors.accentPrimary,
                title: 'Local Cache',
                subtitle: 'Fast sub-millisecond local queries',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTile(
    AppColorsExtension colors, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
