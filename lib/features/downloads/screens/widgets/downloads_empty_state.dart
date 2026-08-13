import 'package:flutter/material.dart';
import '../../../../shared/widgets/app_common_widgets.dart';

class DownloadsEmptyState extends StatelessWidget {
  final int activeTab;

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
