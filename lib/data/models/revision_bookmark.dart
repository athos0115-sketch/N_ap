/// 청취 중 어색한 문장을 즉시 기록하는 퇴고 북마크 모델.
class RevisionBookmark {
  const RevisionBookmark({
    required this.id,
    required this.folderId,
    required this.folderName,
    required this.episodeId,
    required this.episodeTitle,
    required this.sentenceIndex,
    required this.sentenceText,
    required this.timestamp,
    this.syncedToDrive = false,
  });

  final String id;
  final String folderId;
  final String folderName;
  final String episodeId;
  final String episodeTitle;
  final int sentenceIndex;
  final String sentenceText;
  final DateTime timestamp;
  final bool syncedToDrive;

  RevisionBookmark copyWith({
    bool? syncedToDrive,
  }) {
    return RevisionBookmark(
      id: id,
      folderId: folderId,
      folderName: folderName,
      episodeId: episodeId,
      episodeTitle: episodeTitle,
      sentenceIndex: sentenceIndex,
      sentenceText: sentenceText,
      timestamp: timestamp,
      syncedToDrive: syncedToDrive ?? this.syncedToDrive,
    );
  }

  /// GEMINI.md 5번 포맷: `[Timestamp] | [Episode Title] | [Line #] | [Current Sentence Text]`
  String toMarkdownLine() {
    final ts = _formatTimestamp(timestamp);
    final sanitizedSentence = sentenceText
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('|', '\\|')
        .trim();
    return '- [$ts] | [$episodeTitle] | [Line ${sentenceIndex + 1}] | $sanitizedSentence';
  }

  static String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'folderId': folderId,
    'folderName': folderName,
    'episodeId': episodeId,
    'episodeTitle': episodeTitle,
    'sentenceIndex': sentenceIndex,
    'sentenceText': sentenceText,
    'timestamp': timestamp.toIso8601String(),
    'syncedToDrive': syncedToDrive,
  };

  factory RevisionBookmark.fromJson(Map<String, dynamic> json) {
    return RevisionBookmark(
      id: json['id'] as String? ?? '',
      folderId: json['folderId'] as String? ?? '',
      folderName: json['folderName'] as String? ?? '',
      episodeId: json['episodeId'] as String? ?? '',
      episodeTitle: json['episodeTitle'] as String? ?? '',
      sentenceIndex: json['sentenceIndex'] as int? ?? 0,
      sentenceText: json['sentenceText'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      syncedToDrive: json['syncedToDrive'] as bool? ?? false,
    );
  }
}
