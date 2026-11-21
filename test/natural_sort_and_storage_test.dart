import 'package:flutter_test/flutter_test.dart';
import 'package:n_ap/core/utils/natural_sort.dart';
import 'package:n_ap/data/models/episode_item.dart';
import 'package:n_ap/data/models/novel_folder.dart';
import 'package:n_ap/data/models/revision_bookmark.dart';
import 'package:n_ap/data/services/drive_service.dart';
import 'package:n_ap/data/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NaturalSort', () {
    test('orders numbered Korean episode titles naturally', () {
      final unsorted = ['10화.txt', '2화.txt', '1화.txt', '100화.txt', '3화.txt'];
      final sorted = NaturalSort.sortedBy(unsorted, (s) => s);
      expect(sorted, ['1화.txt', '2화.txt', '3화.txt', '10화.txt', '100화.txt']);
    });
  });

  group('EpisodeItem & DriveService helpers', () {
    test('identifies supported manuscript types and ignores memo file', () {
      expect(
        EpisodeItem.isSupportedFile(
          name: '1화.txt',
          mimeType: EpisodeItem.plainTextMimeType,
        ),
        isTrue,
      );
      expect(
        EpisodeItem.isSupportedFile(
          name: '2화.md',
          mimeType: EpisodeItem.markdownMimeType,
        ),
        isTrue,
      );
      expect(
        EpisodeItem.isSupportedFile(
          name: '3화',
          mimeType: EpisodeItem.googleDocMimeType,
        ),
        isTrue,
      );
      expect(
        EpisodeItem.isSupportedFile(
          name: 'N_ap_퇴고메모.md',
          mimeType: EpisodeItem.markdownMimeType,
        ),
        isFalse,
      );
    });

    test('extracts folder id from share URL or raw ID', () {
      expect(
        DriveService.extractFolderId(
          'https://drive.google.com/drive/folders/1AbCdEfG_123?usp=sharing',
        ),
        '1AbCdEfG_123',
      );
      expect(
        DriveService.extractFolderId('1AbCdEfG_123'),
        '1AbCdEfG_123',
      );
    });
  });

  group('RevisionBookmark & StorageService', () {
    test('formats revision bookmark markdown line correctly', () {
      final bookmark = RevisionBookmark(
        id: '1',
        folderId: 'f1',
        folderName: '판타지 장편',
        episodeId: 'e1',
        episodeTitle: '12화 회귀',
        sentenceIndex: 14,
        sentenceText: '그는 칼을 | 뽑았다.',
        timestamp: DateTime(2026, 11, 22, 1, 5, 9),
      );
      expect(
        bookmark.toMarkdownLine(),
        '- [2026-11-22 01:05:09] | [12화 회귀] | [Line 15] | 그는 칼을 \\| 뽑았다.',
      );
    });

    test('persists folders, progress, TTS settings, and bookmarks', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.create();

      final folder = NovelFolder(
        id: 'folder_1',
        name: '장편소설',
        lastFileId: 'ep_10',
        lastFileName: '10화.md',
        lastSentenceIndex: 23,
      );
      await storage.saveFolders([folder]);
      await storage.saveVoice('en-US-AvaMultilingualNeural');
      await storage.saveSpeed(1.4);
      await storage.savePitchHz(-3);
      await storage.saveNuanceEnabled(false);
      await storage.saveFontSizeLevel(2);

      final loadedFolders = storage.loadFolders();
      expect(loadedFolders.length, 1);
      expect(loadedFolders.first.lastFileId, 'ep_10');
      expect(loadedFolders.first.lastSentenceIndex, 23);
      expect(storage.loadVoice(), 'en-US-AvaMultilingualNeural');
      expect(storage.loadSpeed(), 1.4);
      expect(storage.loadPitchHz(), -3);
      expect(storage.loadNuanceEnabled(), isFalse);
      expect(storage.loadFontSizeLevel(), 2);
    });
  });
}
