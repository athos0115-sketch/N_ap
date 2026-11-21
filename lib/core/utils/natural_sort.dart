/// 숫자 토큰을 수치 크기로 비교해 `1화, 2화, ..., 10화` 순서로 정렬하는 자연 정렬 유틸리티.
class NaturalSort {
  NaturalSort._();

  static final RegExp _tokenRegex = RegExp(r'(\d+|\D+)');

  /// 두 문자열을 자연 정렬 기준으로 비교한다.
  static int compare(String a, String b) {
    final tokensA = _tokenRegex
        .allMatches(a)
        .map((m) => m.group(0)!)
        .toList(growable: false);
    final tokensB = _tokenRegex
        .allMatches(b)
        .map((m) => m.group(0)!)
        .toList(growable: false);

    final minLen =
        tokensA.length < tokensB.length ? tokensA.length : tokensB.length;

    for (var i = 0; i < minLen; i++) {
      final ta = tokensA[i];
      final tb = tokensB[i];

      final numA = BigInt.tryParse(ta);
      final numB = BigInt.tryParse(tb);

      if (numA != null && numB != null) {
        final cmp = numA.compareTo(numB);
        if (cmp != 0) return cmp;
        // 수치가 같으면 자릿수(예: 01 vs 1)로 안정적 순서 보장
        final lenCmp = ta.length.compareTo(tb.length);
        if (lenCmp != 0) return lenCmp;
      } else {
        final cmp = ta.toLowerCase().compareTo(tb.toLowerCase());
        if (cmp != 0) return cmp;
        final exactCmp = ta.compareTo(tb);
        if (exactCmp != 0) return exactCmp;
      }
    }

    return tokensA.length.compareTo(tokensB.length);
  }

  /// 리스트를 자연 정렬 기준으로 제자리 또는 새 리스트로 정렬한다.
  static List<T> sortedBy<T>(
    Iterable<T> items,
    String Function(T item) keySelector,
  ) {
    final list = items.toList();
    list.sort((a, b) => compare(keySelector(a), keySelector(b)));
    return list;
  }
}
