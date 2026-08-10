class PhotoAsset {
  PhotoAsset({
    required this.id,
    required this.entryId,
    required this.createdAt,
    this.localPath,
    this.driveFileId,
  });

  final String id;
  final String entryId;
  final DateTime createdAt;
  final String? localPath;
  final String? driveFileId;

  PhotoAsset copyWith({String? localPath, String? driveFileId, String? entryId}) {
    return PhotoAsset(
      id: id,
      entryId: entryId ?? this.entryId,
      createdAt: createdAt,
      localPath: localPath ?? this.localPath,
      driveFileId: driveFileId ?? this.driveFileId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entryId': entryId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'localPath': localPath,
        'driveFileId': driveFileId,
      };

  factory PhotoAsset.fromJson(Map<dynamic, dynamic> json) {
    return PhotoAsset(
      id: json['id'] as String,
      entryId: json['entryId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      localPath: json['localPath'] as String?,
      driveFileId: json['driveFileId'] as String?,
    );
  }
}
