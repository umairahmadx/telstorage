import 'package:path/path.dart' as p;

/// Determines the TelStorage subfolder category name based on file extension.
String getSubfolderForExtension(String filename) {
  final ext = p.extension(filename).toLowerCase().replaceFirst('.', '');
  switch (ext) {
    // Photos / Images
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'bmp':
    case 'webp':
    case 'heic':
    case 'heif':
      return 'photo';
    
    // Videos
    case 'mp4':
    case 'mkv':
    case 'mov':
    case 'avi':
    case 'webm':
    case 'flv':
    case 'm4v':
    case '3gp':
      return 'video';

    // Zips / Archives
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
    case 'bz2':
    case 'xz':
      return 'zip';

    // Audios / Music
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'm4a':
    case 'ogg':
    case 'aac':
      return 'audio';

    // Documents
    case 'pdf':
    case 'doc':
    case 'docx':
    case 'xls':
    case 'xlsx':
    case 'ppt':
    case 'pptx':
    case 'txt':
    case 'csv':
    case 'epub':
      return 'documents';

    default:
      return 'others';
  }
}
