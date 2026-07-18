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
