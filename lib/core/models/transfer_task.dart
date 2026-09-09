/*
 * File: transfer_task.dart
 * Description: Component and logic definition for transfer_task.dart in TelStorage.
 */

enum TransferType { upload, download, share }

enum TransferStatus {
  pending,
  preparing,
  waiting,
  uploading,
  downloading,
  sharing,
  paused,
  retrying,
  completed,
  failed,
  cancelled,
}

class TransferTask {
  final String id;
  final String name;
  final TransferType type;
  final double sizeMb;
  double progress;
  TransferStatus status;
  String? currentStage;
  String? error;
  DateTime addedAt;
  DateTime? completedAt;
  double speedKbps;
  String? eta;

  TransferTask({
    required this.id,
    required this.name,
    required this.type,
    required this.sizeMb,
    this.progress = 0.0,
    this.status = TransferStatus.pending,
    this.currentStage,
    this.error,
    required this.addedAt,
    this.completedAt,
    this.speedKbps = 0.0,
    this.eta,
  });

  bool get isActive =>
      status != TransferStatus.completed &&
      status != TransferStatus.failed &&
      status != TransferStatus.cancelled;

  /// Formats an arbitrary size in megabytes into human-readable adaptive units (B, KB, MB, GB).
  static String formatStorage(double mb) {
    if (mb <= 0 || mb.isNaN || !mb.isFinite) return '0 B';
    final bytes = (mb * 1024 * 1024).round();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Formats speed in KB/s into human-readable adaptive units (B/s, KB/s, MB/s).
  static String formatSpeed(double speedKbps) {
    if (speedKbps <= 0 || speedKbps.isNaN || !speedKbps.isFinite) return '';
    if (speedKbps < 1.0) {
      final bytesPerSec = (speedKbps * 1024).round();
      return '$bytesPerSec B/s';
    }
    if (speedKbps < 1024.0) {
      return '${speedKbps.toStringAsFixed(speedKbps < 10 ? 1 : 0)} KB/s';
    }
    return '${(speedKbps / 1024.0).toStringAsFixed(1)} MB/s';
  }

  /// Formatted total size of this task.
  String get formattedSize => formatStorage(sizeMb);

  /// Formatted speed of this task.
  String get formattedSpeed => formatSpeed(speedKbps);

  /// Formatted progress showing percentage with 1 decimal place (e.g. "45.2%").
  String get formattedProgress {
    final pct = (progress.clamp(0.0, 1.0) * 100.0);
    return '${pct.toStringAsFixed(1)}%';
  }

  /// Formatted progress showing transferred and total amounts sharing the appropriate unit.
  String get formattedTransferredAndTotal {
    if (sizeMb <= 0 || sizeMb.isNaN || !sizeMb.isFinite) return '0 B';
    final totalBytes = (sizeMb * 1024 * 1024).round();
    final transferredBytes = (progress.clamp(0.0, 1.0) * totalBytes).round();

    if (totalBytes < 1024) {
      return '$transferredBytes / $totalBytes B';
    }
    if (totalBytes < 1024 * 1024) {
      final transferredKb = (transferredBytes / 1024).toStringAsFixed(1);
      final totalKb = (totalBytes / 1024).toStringAsFixed(1);
      return '$transferredKb / $totalKb KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      final transferredMb =
          (transferredBytes / (1024 * 1024)).toStringAsFixed(1);
      final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      return '$transferredMb / $totalMb MB';
    }
    final transferredGb =
        (transferredBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
    final totalGb = (totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
    return '$transferredGb / $totalGb GB';
  }

  TransferTask copyWith({
    double? progress,
    TransferStatus? status,
    String? currentStage,
    String? error,
    DateTime? completedAt,
    double? speedKbps,
    String? eta,
  }) {
    return TransferTask(
      id: id,
      name: name,
      type: type,
      sizeMb: sizeMb,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      currentStage: currentStage ?? this.currentStage,
      error: error ?? this.error,
      addedAt: addedAt,
      completedAt: completedAt ?? this.completedAt,
      speedKbps: speedKbps ?? this.speedKbps,
      eta: eta ?? this.eta,
    );
  }
}
