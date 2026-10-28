import 'package:file_share_intent/file_share_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/incoming_share_service.dart';

void main() {
  group('IncomingShareService', () {
    test('normalizes file URLs into local file paths', () {
      final sharedFile = SharedMediaFile(
        path: Uri.file('/tmp/shared/document.pdf').toString(),
        type: SharedMediaType.file,
      );

      expect(
        IncomingShareService.localPathFor(sharedFile),
        Uri.file('/tmp/shared/document.pdf').toFilePath(),
      );
    });

    test('leaves native paths unchanged', () {
      final sharedFile = SharedMediaFile(
        path: '/tmp/shared/document.pdf',
        type: SharedMediaType.file,
      );

      expect(
        IncomingShareService.localPathFor(sharedFile),
        '/tmp/shared/document.pdf',
      );
    });
  });
}
