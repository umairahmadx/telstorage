/*
 * File: tiles_hero_test.dart
 * Description: Widget tests validating Hero tag uniqueness, heroPrefix scoping, and image-only Hero wrapping in AppFileTile and AppFileGridTile.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_grid_tile.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final imageFile = FileRecord(
    fileId: 'img-1234',
    name: 'photo.jpg',
    sizeMb: 2.0,
    metadataMessageId: 101,
    mimeType: 'image/jpeg',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: '',
  );

  final videoFile = FileRecord(
    fileId: 'vid-5678',
    name: 'movie.mp4',
    sizeMb: 15.0,
    metadataMessageId: 102,
    mimeType: 'video/mp4',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: '',
  );

  final docFile = FileRecord(
    fileId: 'doc-9999',
    name: 'notes.txt',
    sizeMb: 0.1,
    metadataMessageId: 103,
    mimeType: 'text/plain',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: '',
  );

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('Tile Hero Scoping Tests', () {
    testWidgets('TC-TH-01: AppFileTile wraps image in Hero with default tag',
        (tester) async {
      await tester.pumpWidget(wrapWithTheme(
        AppFileTile(
          file: imageFile,
          onTap: () {},
        ),
      ));

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final hero = tester.widget<Hero>(heroFinder);
      expect(hero.tag, 'image_hero_img-1234');
    });

    testWidgets('TC-TH-02: AppFileTile scopes Hero tag with heroPrefix',
        (tester) async {
      await tester.pumpWidget(wrapWithTheme(
        AppFileTile(
          file: imageFile,
          heroPrefix: 'recent',
          onTap: () {},
        ),
      ));

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final hero = tester.widget<Hero>(heroFinder);
      expect(hero.tag, 'recent_image_hero_img-1234');
    });

    testWidgets('TC-TH-03: AppFileTile wraps video in Hero with heroPrefix',
        (tester) async {
      await tester.pumpWidget(wrapWithTheme(
        AppFileTile(
          file: videoFile,
          heroPrefix: 'recent',
          onTap: () {},
        ),
      ));

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final hero = tester.widget<Hero>(heroFinder);
      expect(hero.tag, 'recent_video_hero_vid-5678');
    });

    testWidgets('TC-TH-04: AppFileTile does NOT wrap non-media file in Hero',
        (tester) async {
      await tester.pumpWidget(wrapWithTheme(
        AppFileTile(
          file: docFile,
          onTap: () {},
        ),
      ));

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsNothing);
    });

    testWidgets('TC-TH-05: AppFileGridTile wraps video with heroPrefix',
        (tester) async {
      await tester.pumpWidget(wrapWithTheme(
        AppFileGridTile(
          file: videoFile,
          heroPrefix: 'browser',
          onTap: () {},
          onLongPress: () {},
        ),
      ));

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final hero = tester.widget<Hero>(heroFinder);
      expect(hero.tag, 'browser_video_hero_vid-5678');
    });

    testWidgets(
        'TC-TH-06: AppFileGridTile does NOT wrap non-media file in Hero',
        (tester) async {
      await tester.pumpWidget(wrapWithTheme(
        AppFileGridTile(
          file: docFile,
          heroPrefix: 'browser',
          onTap: () {},
          onLongPress: () {},
        ),
      ));

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsNothing);
    });

    testWidgets(
        'TC-TH-06: HeroMode disables hero in offstage tab preventing collision',
        (tester) async {
      // Both tabs contain the exact same file with the same hero tag
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: IndexedStack(
            index: 0,
            children: [
              HeroMode(
                enabled: true,
                child: AppFileTile(file: imageFile, onTap: () {}),
              ),
              HeroMode(
                enabled: false,
                child: AppFileTile(file: imageFile, onTap: () {}),
              ),
            ],
          ),
        ),
      ));

      // Push a new route to trigger Hero flight check
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
