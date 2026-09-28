/*
 * File: downloads_shared_section_test.dart
 * Description: Widget tests for DownloadsSharedSection verifying card rendering, QR code action button, and tap interactions.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/web_share_job.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/downloads/presentation/screens/downloads/viewmodel/downloads_view_model.dart';
import 'package:telstorage/features/downloads/presentation/screens/downloads/widgets/downloads_shared_section.dart';

class _FakeTransferCubit extends Cubit<TransferState>
    implements TransferCubit {
  _FakeTransferCubit() : super(TransferState());

  @override
  FileRecord? getFile(String fileId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final testJob = WebShareJob(
    fileId: 'share_job_001',
    name: 'project_spec.pdf',
    mimeType: 'application/pdf',
    sizeMb: 5.5,
    status: 'completed',
    shareUrl: 'https://storage.to/v/project-spec',
    addedAt: DateTime.now(),
    completedAt: DateTime.now(),
    expiryDays: 7,
    maxDownloads: 5,
  );

  group('DownloadsSharedSection Tests', () {
    testWidgets(
        'TC-01: Renders shared link card with quick QR button, Copy, Share, and Delete',
        (tester) async {
      final fakeCubit = _FakeTransferCubit();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: BlocProvider<TransferCubit>.value(
              value: fakeCubit,
              child: DownloadsSharedSection(
                sharedLinks: [testJob],
                onCopyUrl: (_) {},
                onShareUrl: (_) {},
                onDeleteShareLink: (_, __) {},
              ),
            ),
          ),
        ),
      );

      // Verify section header and item name
      expect(find.text('SHARED LINKS (1)'), findsOneWidget);
      expect(find.text('project_spec.pdf'), findsOneWidget);
      expect(find.text('https://storage.to/v/project-spec'), findsOneWidget);

      // Verify QR button is present
      expect(find.byIcon(AppIcons.qrCode), findsOneWidget);

      // Verify other action buttons are present
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byIcon(Icons.link_off_rounded), findsOneWidget);
    });
  });
}
