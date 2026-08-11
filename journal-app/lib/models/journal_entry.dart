class JournalEntry {
  JournalEntry({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.text,
    this.mood,
    this.tags = const [],
    this.photoIds = const [],
    this.aiReflectionQuestion,
    this.deleted = false,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String text;
  final int? mood;
  final List<String> tags;
  final List<String> photoIds;
  final String? aiReflectionQuestion;
  final bool deleted;

  JournalEntry copyWith({
    String? text,
    int? mood,
    List<String>? tags,
    List<String>? photoIds,
    String? aiReflectionQuestion,
    bool? deleted,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      text: text ?? this.text,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
      photoIds: photoIds ?? this.photoIds,
      aiReflectionQuestion: aiReflectionQuestion ?? this.aiReflectionQuestion,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'text': text,
        'mood': mood,
        'tags': tags,
        'photoIds': photoIds,
        'aiReflectionQuestion': aiReflectionQuestion,
        'deleted': deleted,
      };

  factory JournalEntry.fromJson(Map<dynamic, dynamic> json) {
    return JournalEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      text: json['text'] as String,
      mood: json['mood'] as int?,
      tags: List<String>.from(json['tags'] as List? ?? const []),
      photoIds: List<String>.from(json['photoIds'] as List? ?? const []),
      aiReflectionQuestion: json['aiReflectionQuestion'] as String?,
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}
