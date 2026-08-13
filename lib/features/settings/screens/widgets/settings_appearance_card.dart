import 'package:flutter/material.dart';
import '../../../../core/services/theme_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_segmented_control.dart';
import '../../../../shared/widgets/app_surface_card.dart';

class SettingsAppearanceCard extends StatelessWidget {
  const SettingsAppearanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.bgSurfaceInset,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.contrast_rounded,
                    color: colors.textPrimary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Theme Mode',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeService.instance.themeModeNotifier,
                builder: (context, mode, _) {
                  final modeText = mode == ThemeMode.system
                      ? 'System'
                      : (mode == ThemeMode.dark ? 'Dark' : 'Light');
                  return Text(
                    modeText,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeService.instance.themeModeNotifier,
              builder: (context, currentMode, _) {
                return Row(
                  children: [
                    Expanded(
                      child: AppSegmentedControl<ThemeMode>(
                        value: currentMode,
                        padding: EdgeInsets.zero,
                        height: 36,
                        radius: 8,
                        fontSize: 13,
                        segments: const [
                          AppSegment(value: ThemeMode.light, label: 'Light'),
                          AppSegment(value: ThemeMode.dark, label: 'Dark'),
                          AppSegment(value: ThemeMode.system, label: 'System'),
                        ],
                        onChanged: ThemeService.instance.setThemeMode,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
