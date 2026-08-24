/// File: downloads_empty_state.dart
/// Description: Empty state view rendered when no active or completed transfers exist.
library;

import 'package:flutter/material.dart';
import '../../../../../../shared/widgets/app_common_widgets.dart';

/// Empty state placeholder for downloads and transfers screen tabs.
class DownloadsEmptyState extends StatelessWidget {
  /// Active tab index (0: Downloads, 1: Uploads, 2: Shared).
  final int activeTab;

  /// Constructs DownloadsEmptyState.
  const DownloadsEmptyState({super.key, required this.activeTab});

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon;

    switch (activeTab) {
      case 1:
        message = 'No active or completed uploads';
        icon = Icons.cloud_upload_outlined;
        break;
      case 2:
        message = 'No active shared links';
        icon = Icons.link_off_rounded;
        break;
      default:
        message = 'No active or completed downloads';
        icon = Icons.download_done_rounded;
        break;
    }

    return AppEmptyState(
      message: message,
      icon: icon,
      padding: const EdgeInsets.only(top: 80),
    );
  }
}
