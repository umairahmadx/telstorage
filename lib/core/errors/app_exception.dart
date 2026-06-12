/// Base exception for all TelStorage errors.
class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => code != null
      ? 'AppException[$code]: $message'
      : 'AppException: $message';
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.code});
}

class TelegramApiException extends AppException {
  const TelegramApiException(super.message, {super.code});
}

class FileSizeException extends AppException {
  const FileSizeException(super.message);
}

class StorageException extends AppException {
  const StorageException(super.message);
}
