import 'package:flutter_test/flutter_test.dart';
import 'package:n_ap/core/utils/ssml_parser.dart';

void main() {
  group('SsmlParser.stripMarkdown', () {
    test('removes headings, rules, emphasis, links, and quotes', () {
      const input = '''
# 제1화 시작
> 회상 장면
---
**굵게** 그리고 *기울임* [링크](https://example.com) `코드`
''';
      final cleaned = SsmlParser.stripMarkdown(input);

      expect(cleaned, isNot(contains('#')));
      expect(cleaned, isNot(contains('---')));
      expect(cleaned, isNot(contains('**')));
      expect(cleaned, isNot(contains('*')));
      expect(cleaned, isNot(contains('`')));
      expect(cleaned, isNot(contains('https://example.com')));
      expect(cleaned, contains('제1화 시작'));
      expect(cleaned, contains('회상 장면'));
      expect(cleaned, contains('굵게 그리고 기울임 링크 코드'));
    });
  });

  group('SsmlParser.splitIntoSentences', () {
    test('splits sentences while preserving dialogue and parentheses', () {
      const manuscript =
          '첫 문장이다. "정말? 지금 출발할까!" (망설일 시간이 없었다.) 마지막 문장이다.';
      final sentences = SsmlParser.splitIntoSentences(manuscript);

      expect(sentences, [
        '첫 문장이다.',
        '"정말? 지금 출발할까!"',
        '(망설일 시간이 없었다.)',
        '마지막 문장이다.',
      ]);
    });
  });

  group('SsmlParser.buildSsmlBatch', () {
    test('splits into <=2 prosody tags per request and applies dialogue/monologue rules', () {
      final batch = SsmlParser.buildSsmlBatch(
        text: '그가 말했다. "조심해!" (분명 함정일 거야.)',
        voice: 'ko-KR-InJoonNeural',
        speed: 1.0,
      );

      expect(batch.length, 2);
      expect(batch[0], contains("xml:lang='en-US'"));
      expect(batch[0], contains("<voice name='ko-KR-InJoonNeural'>"));
      expect(
        batch[0],
        contains("<prosody pitch='+0Hz' rate='+0%' volume='+0%'>그가 말했다. </prosody>"),
      );
      expect(
        batch[0],
        contains("<prosody pitch='+2Hz' rate='+0%' volume='+0%'>, 조심해!, </prosody>"),
      );
      expect(
        batch[1],
        contains(
          "<prosody pitch='-3Hz' rate='-5%' volume='+0%'>분명 함정일 거야.</prosody>",
        ),
      );
    });

    test('escapes XML characters safely', () {
      final ssml = SsmlParser.buildSsml(
        text: 'A & B < C > D',
        voice: 'ko-KR-SunHiNeural',
      );
      expect(ssml, contains('A &amp; B &lt; C &gt; D'));
    });

    test('renders single flat prosody when enableNuance is false', () {
      final batch = SsmlParser.buildSsmlBatch(
        text: '그가 말했다. "조심해!" (함정이다.)',
        voice: 'en-US-AvaMultilingualNeural',
        speed: 1.2,
        basePitchHz: -2,
        enableNuance: false,
      );
      expect(batch.length, 1);
      expect(batch.first, contains("pitch='-2Hz' rate='+20%'"));
      expect(batch.first, isNot(contains("pitch='+0Hz'")));
    });
  });
}
