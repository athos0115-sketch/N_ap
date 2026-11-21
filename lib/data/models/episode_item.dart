/// Google Drive 폴더 내 원고 회차 파일(.txt, .md, Google Docs) 모델.
class EpisodeItem {
  const EpisodeItem({
    required this.id,
    required this.name,
    required this.mimeType,
    this.modifiedTime,
  });

  static const String googleDocMimeType = 'application/vnd.google-apps.document';
  static const String plainTextMimeType = 'text/plain';
  static const String markdownMimeType = 'text/markdown';

  final String id;
  final String name;
  final String mimeType;
  final DateTime? modifiedTime;

  bool get isGoogleDoc => mimeType == googleDocMimeType;

  /// 확장자가 제거된 표시용 화 제목을 반환한다.
  String get displayTitle {
    final lower = name.toLowerCase();
    if (lower.endsWith('.txt')) {
      return name.substring(0, name.length - 4);
    }
    if (lower.endsWith('.md')) {
      return name.substring(0, name.length - 3);
    }
    return name;
  }

  String get typeBadge {
    if (isGoogleDoc) return 'DOCS';
    if (name.toLowerCase().endsWith('.md')) return 'MD';
    return 'TXT';
  }

  /// GEMINI.md 4.2에서 허용하는 원고 파일 형식 여부를 판별한다.
  static bool isSupportedFile({
    required String name,
    required String mimeType,
  }) {
    if (mimeType == googleDocMimeType) return true;
    final lower = name.toLowerCase();
    if (lower == 'n_ap_퇴고메모.md') return false;
    return lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        mimeType == plainTextMimeType ||
        mimeType == markdownMimeType;
  }
}
