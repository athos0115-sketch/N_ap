/// 소설 원고 텍스트 정제, 문장 분할 및 단일 화자 SSML 변환 유틸리티.
class SsmlParser {
  SsmlParser._();

  static final RegExp _headingRegex = RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true);
  static final RegExp _hrRegex = RegExp(r'^\s*([-*_])\s*(\1\s*){2,}$', multiLine: true);
  static final RegExp _blockquoteRegex = RegExp(r'^\s*>\s?', multiLine: true);
  static final RegExp _imageRegex = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
  static final RegExp _linkRegex = RegExp(r'\[([^\]]+)\]\([^)]*\)');
  static final RegExp _codeFenceRegex = RegExp(r'```[\s\S]*?```');
  static final RegExp _inlineCodeRegex = RegExp(r'`([^`]*)`');
  static final RegExp _boldItalicRegex = RegExp(r'(\*\*\*|___)(.+?)\1');
  static final RegExp _boldRegex = RegExp(r'(\*\*|__)(.+?)\1');
  static final RegExp _italicRegex = RegExp(r'(\*|_)(.+?)\1');
  static final RegExp _strikeRegex = RegExp(r'~~(.+?)~~');
  static final RegExp _strayMarkdownRegex = RegExp(r'(^|\s)[*_~]+|[*_~]+(\s|$)');
  static final RegExp _multiSpaceRegex = RegExp(r'[ \t]{2,}');
  static final RegExp _readableCharRegex = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// 대사("...", “...”) 또는 내면 독백((...)) 토큰 매칭
  static final RegExp _segmentRegex = RegExp(
    r'("[^"\n]+"|“[^”\n]+”|\([^()\n]+\))',
  );

  /// 마크다운 기호를 제거해 TTS가 기호를 읽지 않도록 정제한다.
  static String stripMarkdown(String rawText) {
    var text = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = text.replaceAll(_codeFenceRegex, ' ');
    text = text.replaceAll(_hrRegex, '\n');
    text = text.replaceAll(_headingRegex, '');
    text = text.replaceAll(_blockquoteRegex, '');
    text = text.replaceAllMapped(_imageRegex, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_linkRegex, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_inlineCodeRegex, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(_boldItalicRegex, (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(_boldRegex, (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(_italicRegex, (m) => m.group(2) ?? '');
    text = text.replaceAllMapped(_strikeRegex, (m) => m.group(1) ?? '');
    text = text.replaceAllMapped(
      _strayMarkdownRegex,
      (m) => '${m.group(1) ?? ''}${m.group(2) ?? ''}',
    );
    return text.replaceAll(_multiSpaceRegex, ' ').trim();
  }

  /// 원고 텍스트를 마크다운 제거 후 문장 단위 청크 리스트로 분할한다.
  static List<String> splitIntoSentences(
    String rawText, {
    int maxChunkLength = 420,
  }) {
    final cleaned = stripMarkdown(rawText);
    if (cleaned.isEmpty) return const [];

    final results = <String>[];
    final paragraphs = cleaned.split(RegExp(r'\n+'));

    for (final rawParagraph in paragraphs) {
      final paragraph = rawParagraph.trim();
      if (paragraph.isEmpty || !_readableCharRegex.hasMatch(paragraph)) {
        continue;
      }
      _splitParagraph(paragraph, maxChunkLength, results);
    }

    return results;
  }

  static void _splitParagraph(
    String paragraph,
    int maxChunkLength,
    List<String> out,
  ) {
    final buffer = StringBuffer();
    var inDoubleQuote = false;
    var inCurlyQuote = false;
    var parenDepth = 0;

    void flushBuffer() {
      final candidate = buffer.toString().trim();
      buffer.clear();
      if (candidate.isEmpty || !_readableCharRegex.hasMatch(candidate)) {
        return;
      }
      if (candidate.length <= maxChunkLength) {
        out.add(candidate);
      } else {
        _splitLongSentence(candidate, maxChunkLength, out);
      }
    }

    for (var i = 0; i < paragraph.length; i++) {
      final ch = paragraph[i];
      buffer.write(ch);

      if (ch == '"') {
        inDoubleQuote = !inDoubleQuote;
      } else if (ch == '“') {
        inCurlyQuote = true;
      } else if (ch == '”') {
        inCurlyQuote = false;
      } else if (ch == '(') {
        parenDepth++;
      } else if (ch == ')' && parenDepth > 0) {
        parenDepth--;
      }

      final nextChar = i + 1 < paragraph.length ? paragraph[i + 1] : '';
      final isSentenceEndPunct =
          ch == '.' || ch == '!' || ch == '?' || ch == '。' || ch == '…';
      final isClosingAfterPunct =
          (ch == '"' || ch == '”' || ch == ')') &&
          i > 0 &&
          (paragraph[i - 1] == '.' ||
              paragraph[i - 1] == '!' ||
              paragraph[i - 1] == '?' ||
              paragraph[i - 1] == '…');

      if (!inDoubleQuote && !inCurlyQuote && parenDepth == 0) {
        if (isClosingAfterPunct && (nextChar.isEmpty || nextChar == ' ')) {
          flushBuffer();
        } else if (isSentenceEndPunct &&
            nextChar != '.' &&
            nextChar != '"' &&
            nextChar != '”' &&
            nextChar != ')' &&
            (nextChar.isEmpty || nextChar == ' ')) {
          flushBuffer();
        }
      }
    }

    flushBuffer();
  }

  static void _splitLongSentence(
    String sentence,
    int maxChunkLength,
    List<String> out,
  ) {
    var remaining = sentence;
    while (remaining.length > maxChunkLength) {
      var splitAt = remaining.lastIndexOf(', ', maxChunkLength);
      if (splitAt <= maxChunkLength ~/ 3) {
        splitAt = remaining.lastIndexOf(' ', maxChunkLength);
      }
      if (splitAt <= 0) {
        splitAt = maxChunkLength;
      } else {
        splitAt += 1;
      }
      final part = remaining.substring(0, splitAt).trim();
      if (part.isNotEmpty && _readableCharRegex.hasMatch(part)) {
        out.add(part);
      }
      remaining = remaining.substring(splitAt).trim();
    }
    if (remaining.isNotEmpty && _readableCharRegex.hasMatch(remaining)) {
      out.add(remaining);
    }
  }

  /// 단일 화자 뉘앙스(내레이션/대사/독백)가 반영된 Edge TTS용 SSML 목록을 생성한다.
  ///
  /// Microsoft Edge Read Aloud 서버는 `<speak>`의 `xml:lang='en-US'` 고정,
  /// `<break>` 태그 미허용, 그리고 요청당 `<prosody>` 최대 2개까지만 허용한다.
  /// 따라서 3개 이상의 뉘앙스 구간이 섞인 문장은 2개 단위 SSML로 분할해 반환한다.
  static List<String> buildSsmlBatch({
    required String text,
    required String voice,
    double speed = 1.0,
    int basePitchHz = 0,
    bool enableNuance = true,
  }) {
    final sanitized = removeIncompatibleCharacters(text).trim();
    if (sanitized.isEmpty) return const [];

    final baseRatePct = ((speed.clamp(0.5, 2.5) - 1.0) * 100).round();
    final monologueRatePct =
        ((speed.clamp(0.5, 2.5) * 0.95 - 1.0) * 100).round();

    final tags = <String>[];
    final matches =
        enableNuance ? _segmentRegex.allMatches(sanitized) : const <RegExpMatch>[];

    if (matches.isEmpty) {
      tags.add(
        _wrapProsody(
          escapeXml(sanitized),
          pitchHz: basePitchHz,
          ratePct: baseRatePct,
        ),
      );
    } else {
      var cursor = 0;
      for (final match in matches) {
        final hasLeading = match.start > cursor &&
            sanitized.substring(cursor, match.start).trim().isNotEmpty;
        if (hasLeading) {
          final narration = sanitized.substring(cursor, match.start);
          tags.add(
            _wrapProsody(
              escapeXml(narration),
              pitchHz: basePitchHz,
              ratePct: baseRatePct,
            ),
          );
        }

        final token = match.group(0)!;
        if (token.startsWith('(') && token.endsWith(')')) {
          // 내면 독백: 괄호 기호 없이 -3Hz 피치 하강, -5% 속도
          final inner = token.substring(1, token.length - 1).trim();
          if (inner.isNotEmpty) {
            tags.add(
              _wrapProsody(
                escapeXml(inner),
                pitchHz: basePitchHz - 3,
                ratePct: monologueRatePct,
              ),
            );
          }
        } else {
          // 대사("...", “...”): +2Hz 피치 상승 및 앞뒤 자연 휴지
          final dialogue = token.substring(1, token.length - 1).trim();
          if (dialogue.isNotEmpty) {
            final prefix = hasLeading ? ', ' : '';
            final hasTrailing = match.end < sanitized.length &&
                sanitized.substring(match.end).trim().isNotEmpty;
            final suffix = hasTrailing ? ', ' : '';
            tags.add(
              _wrapProsody(
                '$prefix${escapeXml(dialogue)}$suffix',
                pitchHz: basePitchHz + 2,
                ratePct: baseRatePct,
              ),
            );
          }
        }
        cursor = match.end;
      }

      if (cursor < sanitized.length) {
        final tail = sanitized.substring(cursor);
        if (tail.trim().isNotEmpty) {
          tags.add(
            _wrapProsody(
              escapeXml(tail),
              pitchHz: basePitchHz,
              ratePct: baseRatePct,
            ),
          );
        }
      }
    }

    if (tags.isEmpty) return const [];

    // Edge Read Aloud 서버 제약: 요청당 <prosody> 최대 2개까지 묶어서 전송
    final result = <String>[];
    for (var i = 0; i < tags.length; i += 2) {
      final end = (i + 2).clamp(0, tags.length);
      final chunkTags = tags.sublist(i, end).join();
      result.add(
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xml:lang='en-US'>"
        "<voice name='$voice'>"
        '$chunkTags'
        '</voice>'
        '</speak>',
      );
    }
    return result;
  }

  /// 단일 SSML 문자열을 반환한다(구간이 2개 이하일 때 단일 요청, 초과 시 첫 2구간).
  static String buildSsml({
    required String text,
    required String voice,
    double speed = 1.0,
    int basePitchHz = 0,
    bool enableNuance = true,
  }) {
    final batch = buildSsmlBatch(
      text: text,
      voice: voice,
      speed: speed,
      basePitchHz: basePitchHz,
      enableNuance: enableNuance,
    );
    if (batch.isNotEmpty) return batch.first;
    return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xml:lang='en-US'><voice name='$voice'></voice></speak>";
  }

  static String _wrapProsody(
    String escapedText, {
    required int pitchHz,
    required int ratePct,
  }) {
    final pitchStr = pitchHz >= 0 ? '+${pitchHz}Hz' : '${pitchHz}Hz';
    final rateStr = ratePct >= 0 ? '+$ratePct%' : '$ratePct%';
    return "<prosody pitch='$pitchStr' rate='$rateStr' volume='+0%'>"
        '$escapedText'
        '</prosody>';
  }

  /// Edge TTS 서비스에서 오류를 유발하는 제어 문자를 공백으로 치환한다.
  static String removeIncompatibleCharacters(String input) {
    final buffer = StringBuffer();
    for (final code in input.codeUnits) {
      if ((code >= 0 && code <= 8) ||
          (code >= 11 && code <= 12) ||
          (code >= 14 && code <= 31)) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// XML 특수문자를 이스케이프한다.
  static String escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll("'", '&apos;')
        .replaceAll('"', '&quot;');
  }
}
