import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:n_ap/core/utils/ssml_parser.dart';
import 'package:n_ap/presentation/widgets/darkroom_components.dart';
import 'package:n_ap/presentation/widgets/manuscript_viewer.dart';

void main() {
  test('sample manuscript parses non-empty sentences for audio engine', () {
    const sample = '''
# 제1화 새벽의 작업실
빗방울이 창문을 두드리는 소리가 작업실에 울려 퍼졌다.
"지금 이 원고가 제대로 읽히는지 확인해 보자."
''';
    final sentences = SsmlParser.splitIntoSentences(sample);
    expect(sentences.length, 3);
  });

  testWidgets('DarkroomPillButton in ListTile.trailing does not collapse title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('새벽의 연대기'),
            trailing: DarkroomPillButton(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () {},
              child: const Text('등록'),
            ),
          ),
        ),
      ),
    );

    final titleSize = tester.getSize(find.text('새벽의 연대기'));
    final trailingSize = tester.getSize(find.byType(DarkroomPillButton));
    expect(titleSize.width, greaterThan(40));
    expect(trailingSize.width, lessThan(120));
  });

  testWidgets('ManuscriptViewer blocks sentence taps when touchLocked is true', (
    tester,
  ) async {
    int? tappedIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManuscriptViewer(
            sentences: const ['첫 번째 문장입니다.', '두 번째 문장입니다.'],
            currentIndex: 0,
            bufferedIndices: const {0, 1},
            fontSizeLevel: 1,
            isPlaying: false,
            touchLocked: false,
            onTapSentence: (i) => tappedIndex = i,
          ),
        ),
      ),
    );

    await tester.tap(find.text('두 번째 문장입니다.'));
    expect(tappedIndex, 1);

    tappedIndex = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManuscriptViewer(
            sentences: const ['첫 번째 문장입니다.', '두 번째 문장입니다.'],
            currentIndex: 0,
            bufferedIndices: const {0, 1},
            fontSizeLevel: 1,
            isPlaying: false,
            touchLocked: true,
            onTapSentence: (i) => tappedIndex = i,
          ),
        ),
      ),
    );

    await tester.tap(find.text('두 번째 문장입니다.'), warnIfMissed: false);
    expect(tappedIndex, isNull);
  });
}
