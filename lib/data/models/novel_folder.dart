/// 사용자가 등록한 Google Drive 소설 프로젝트 폴더 및 마지막 재생 진도 모델.
class NovelFolder {
  const NovelFolder({
    required this.id,
    required this.name,
    this.lastFileId,
    this.lastFileName,
    this.lastSentenceIndex = 0,
    this.updatedAtIso,
  });

  final String id;
  final String name;
  final String? lastFileId;
  final String? lastFileName;
  final int lastSentenceIndex;
  final String? updatedAtIso;

  NovelFolder copyWith({
    String? id,
    String? name,
    String? lastFileId,
    String? lastFileName,
    int? lastSentenceIndex,
    String? updatedAtIso,
    bool clearLastFile = false,
  }) {
    return NovelFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      lastFileId: clearLastFile ? null : (lastFileId ?? this.lastFileId),
      lastFileName: clearLastFile ? null : (lastFileName ?? this.lastFileName),
      lastSentenceIndex: lastSentenceIndex ?? this.lastSentenceIndex,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lastFileId': lastFileId,
    'lastFileName': lastFileName,
    'lastSentenceIndex': lastSentenceIndex,
    'updatedAtIso': updatedAtIso,
  };

  factory NovelFolder.fromJson(Map<String, dynamic> json) {
    return NovelFolder(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '이름 없는 폴더',
      lastFileId: json['lastFileId'] as String?,
      lastFileName: json['lastFileName'] as String?,
      lastSentenceIndex: json['lastSentenceIndex'] as int? ?? 0,
      updatedAtIso: json['updatedAtIso'] as String?,
    );
  }
}
