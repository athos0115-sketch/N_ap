import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../core/utils/natural_sort.dart';
import '../models/episode_item.dart';
import '../models/novel_folder.dart';
import '../models/revision_bookmark.dart';

/// Google Drive 인증 및 원고 파일·퇴고 메모 연동 서비스 (`google_sign_in` 7.x + `googleapis`).
class DriveService {
  DriveService({this._defaultServerClientId});

  static const String driveReadonlyScope =
      'https://www.googleapis.com/auth/drive.readonly';
  static const String driveFileScope =
      'https://www.googleapis.com/auth/drive.file';
  static const List<String> requiredScopes = [
    driveReadonlyScope,
    driveFileScope,
  ];
  static const String revisionMemoFileName = 'N_ap_퇴고메모.md';

  final String? _defaultServerClientId;
  final ValueNotifier<GoogleSignInAccount?> currentUserNotifier = ValueNotifier(
    null,
  );
  final ValueNotifier<bool> hasDriveFilePermissionNotifier = ValueNotifier(
    false,
  );

  bool _initialized = false;
  String? _initializedServerClientId;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;

  GoogleSignInAccount? get currentUser => currentUserNotifier.value;
  bool get isSignedIn => currentUserNotifier.value != null;

  /// GoogleSignIn 7.x 인스턴스를 초기화하고 기존 세션을 조용히 복구한다.
  Future<void> initialize({String? serverClientId}) async {
    final effectiveServerClientId =
        (serverClientId != null && serverClientId.trim().isNotEmpty)
        ? serverClientId.trim()
        : (_defaultServerClientId != null &&
                  _defaultServerClientId.trim().isNotEmpty
              ? _defaultServerClientId.trim()
              : null);

    if (_initialized && effectiveServerClientId == _initializedServerClientId) {
      return;
    }

    await _authSub?.cancel();
    final signIn = GoogleSignIn.instance;
    await signIn.initialize(serverClientId: effectiveServerClientId);
    _initialized = true;
    _initializedServerClientId = effectiveServerClientId;

    _authSub = signIn.authenticationEvents.listen(
      (event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn():
            currentUserNotifier.value = event.user;
            unawaited(_refreshScopeStatus(event.user));
          case GoogleSignInAuthenticationEventSignOut():
            currentUserNotifier.value = null;
            hasDriveFilePermissionNotifier.value = false;
        }
      },
      onError: (_) {
        // 경량 로그인 실패는 명시적 로그인 버튼으로 재시도 가능하므로 무시
      },
    );

    try {
      await signIn.attemptLightweightAuthentication();
    } catch (_) {
      // 세션 미존재 시 무시
    }
  }

  Future<void> _refreshScopeStatus(GoogleSignInAccount user) async {
    try {
      final fileAuth = await user.authorizationClient.authorizationForScopes([
        driveFileScope,
      ]);
      hasDriveFilePermissionNotifier.value = fileAuth != null;
    } catch (_) {
      hasDriveFilePermissionNotifier.value = false;
    }
  }

  /// 사용자 버튼 탭으로 Google 로그인 및 Drive 스코프 인가를 진행한다.
  Future<GoogleSignInAccount> signInAndAuthorize() async {
    if (!_initialized) {
      await initialize();
    }
    final signIn = GoogleSignIn.instance;
    if (!signIn.supportsAuthenticate()) {
      throw const DriveServiceException(
        '현재 플랫폼에서는 Google 로그인 인증을 지원하지 않습니다.',
      );
    }

    final account = await signIn.authenticate();
    currentUserNotifier.value = account;

    final existing = await account.authorizationClient.authorizationForScopes(
      requiredScopes,
    );
    if (existing == null) {
      await account.authorizationClient.authorizeScopes(requiredScopes);
    }
    await _refreshScopeStatus(account);
    return account;
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    currentUserNotifier.value = null;
    hasDriveFilePermissionNotifier.value = false;
  }

  Future<_DriveClientHandle> _acquireClient({
    bool allowInteractive = false,
    bool requireWriteScope = false,
  }) async {
    final user = currentUserNotifier.value;
    if (user == null) {
      throw const DriveAuthException('Google 계정에 먼저 로그인해 주세요.');
    }

    final scopes = requireWriteScope
        ? requiredScopes
        : const [driveReadonlyScope];
    var auth = await user.authorizationClient.authorizationForScopes(scopes);
    if (auth == null && allowInteractive) {
      auth = await user.authorizationClient.authorizeScopes(scopes);
    }
    if (auth == null) {
      throw const DriveAuthException(
        'Google Drive 접근 권한이 만료되었거나 허용되지 않았습니다. 다시 연결해 주세요.',
      );
    }

    final headers = <String, String>{
      'Authorization': 'Bearer ${auth.accessToken}',
      'X-Goog-AuthUser': '0',
    };
    final httpClient = _GoogleAuthHttpClient(headers);
    return _DriveClientHandle(
      api: drive.DriveApi(httpClient),
      httpClient: httpClient,
      accessToken: auth.accessToken,
      user: user,
    );
  }

  Future<T> _withDriveApi<T>(
    Future<T> Function(drive.DriveApi api) action, {
    bool requireWriteScope = false,
  }) async {
    var handle = await _acquireClient(requireWriteScope: requireWriteScope);
    try {
      return await action(handle.api);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401) {
        // 토큰 만료 시 캐시된 토큰 제거 후 1회 무음 재발급 시도
        await handle.user.authorizationClient.clearAuthorizationToken(
          accessToken: handle.accessToken,
        );
        handle.close();
        handle = await _acquireClient(requireWriteScope: requireWriteScope);
        try {
          return await action(handle.api);
        } on drive.DetailedApiRequestError catch (retryErr) {
          if (retryErr.status == 401) {
            throw const DriveAuthException(
              'Google Drive 인증 토큰이 만료되었습니다. 계정을 다시 연결해 주세요.',
            );
          }
          throw DriveServiceException(
            'Drive API 오류 (${retryErr.status}): ${retryErr.message ?? ''}',
          );
        }
      }
      throw DriveServiceException(
        'Drive API 오류 (${e.status}): ${e.message ?? ''}',
      );
    } finally {
      handle.close();
    }
  }

  /// 지정된 상위 폴더(기본: 내 드라이브 루트)의 하위 폴더 목록을 자연 정렬로 반환한다.
  Future<List<NovelFolder>> listFolders({String? parentId}) async {
    return _withDriveApi((api) async {
      final parent = (parentId == null || parentId.isEmpty) ? 'root' : parentId;
      final q =
          "mimeType = 'application/vnd.google-apps.folder' "
          "and '$parent' in parents and trashed = false";

      final collected = <NovelFolder>[];
      String? pageToken;
      do {
        final res = await api.files.list(
          q: q,
          pageSize: 100,
          pageToken: pageToken,
          spaces: 'drive',
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
          $fields: 'nextPageToken, files(id, name)',
        );
        for (final file in res.files ?? const <drive.File>[]) {
          final id = file.id;
          final name = file.name;
          if (id != null && name != null) {
            collected.add(NovelFolder(id: id, name: name));
          }
        }
        pageToken = res.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      return NaturalSort.sortedBy(collected, (f) => f.name);
    });
  }

  /// URL 또는 폴더 ID 문자열로 폴더 메타데이터를 조회해 등록용 모델로 반환한다.
  Future<NovelFolder> resolveFolder(String inputOrUrl) async {
    final folderId = extractFolderId(inputOrUrl);
    if (folderId.isEmpty) {
      throw const DriveServiceException('유효한 Google Drive 폴더 ID 또는 링크가 아닙니다.');
    }

    return _withDriveApi((api) async {
      final obj = await api.files.get(
        folderId,
        supportsAllDrives: true,
        $fields: 'id, name, mimeType, trashed',
      );
      if (obj is! drive.File || obj.id == null) {
        throw const DriveServiceException('폴더 정보를 불러오지 못했습니다.');
      }
      if (obj.mimeType != 'application/vnd.google-apps.folder') {
        throw const DriveServiceException('선택한 항목은 Google Drive 폴더가 아닙니다.');
      }
      if (obj.trashed == true) {
        throw const DriveServiceException('휴지통에 있는 폴더는 등록할 수 없습니다.');
      }
      return NovelFolder(
        id: obj.id!,
        name: obj.name ?? '이름 없는 폴더',
      );
    });
  }

  /// Google Drive 폴더 내 지원 원고(.txt, .md, Google Docs)를 조회해 자연 정렬로 반환한다.
  Future<List<EpisodeItem>> listEpisodesInFolder(String folderId) async {
    return _withDriveApi((api) async {
      final q = "'$folderId' in parents and trashed = false";
      final collected = <EpisodeItem>[];
      String? pageToken;

      do {
        final res = await api.files.list(
          q: q,
          pageSize: 200,
          pageToken: pageToken,
          spaces: 'drive',
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
          $fields: 'nextPageToken, files(id, name, mimeType, modifiedTime)',
        );
        for (final file in res.files ?? const <drive.File>[]) {
          final id = file.id;
          final name = file.name;
          final mimeType = file.mimeType ?? '';
          if (id == null || name == null) continue;
          if (!EpisodeItem.isSupportedFile(name: name, mimeType: mimeType)) {
            continue;
          }
          collected.add(
            EpisodeItem(
              id: id,
              name: name,
              mimeType: mimeType,
              modifiedTime: file.modifiedTime,
            ),
          );
        }
        pageToken = res.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      return NaturalSort.sortedBy(collected, (e) => e.name);
    });
  }

  /// 원고 파일 본문을 UTF-8 텍스트로 추출한다(.txt/.md -> fullMedia, Google Docs -> text/plain export).
  Future<String> downloadEpisodeText(EpisodeItem episode) async {
    return _withDriveApi((api) async {
      drive.Media? media;
      if (episode.isGoogleDoc) {
        media = await api.files.export(
          episode.id,
          'text/plain',
          downloadOptions: drive.DownloadOptions.fullMedia,
        );
      } else {
        final result = await api.files.get(
          episode.id,
          supportsAllDrives: true,
          downloadOptions: drive.DownloadOptions.fullMedia,
        );
        if (result is drive.Media) {
          media = result;
        }
      }

      if (media == null) {
        throw DriveServiceException('${episode.name} 본문을 다운로드하지 못했습니다.');
      }

      final bytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in media.stream) {
        bytesBuilder.add(chunk);
      }
      final bytes = bytesBuilder.takeBytes();
      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('\uFEFF')) {
        text = text.substring(1);
      }
      return text;
    });
  }

  /// 해당 폴더의 `N_ap_퇴고메모.md`에 북마크 항목을 추가한다(`drive.file` 권한 필요).
  Future<void> appendRevisionBookmark({
    required String folderId,
    required RevisionBookmark bookmark,
  }) async {
    await _withDriveApi(
      requireWriteScope: true,
      (api) async {
        final q =
            "name = '$revisionMemoFileName' and '$folderId' in parents and trashed = false";
        final existingList = await api.files.list(
          q: q,
          pageSize: 1,
          spaces: 'drive',
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
          $fields: 'files(id, name)',
        );
        final existing = existingList.files?.firstOrNull;
        final newLine = bookmark.toMarkdownLine();

        if (existing?.id != null) {
          final existingId = existing!.id!;
          var existingContent = '';
          try {
            final res = await api.files.get(
              existingId,
              supportsAllDrives: true,
              downloadOptions: drive.DownloadOptions.fullMedia,
            );
            if (res is drive.Media) {
              final builder = BytesBuilder(copy: false);
              await for (final chunk in res.stream) {
                builder.add(chunk);
              }
              existingContent = utf8.decode(
                builder.takeBytes(),
                allowMalformed: true,
              );
            }
          } catch (_) {
            existingContent = '# N_ap 퇴고 메모\n';
          }

          final normalized = existingContent.endsWith('\n')
              ? existingContent
              : '$existingContent\n';
          final updatedBytes = utf8.encode('$normalized$newLine\n');
          await api.files.update(
            drive.File(),
            existingId,
            supportsAllDrives: true,
            uploadMedia: drive.Media(
              Stream<List<int>>.value(updatedBytes),
              updatedBytes.length,
              contentType: 'text/markdown',
            ),
          );
        } else {
          final initialContent = '# N_ap 퇴고 메모\n\n$newLine\n';
          final bytes = utf8.encode(initialContent);
          final fileMeta = drive.File()
            ..name = revisionMemoFileName
            ..parents = [folderId]
            ..mimeType = 'text/markdown';
          await api.files.create(
            fileMeta,
            supportsAllDrives: true,
            uploadMedia: drive.Media(
              Stream<List<int>>.value(bytes),
              bytes.length,
              contentType: 'text/markdown',
            ),
          );
        }
      },
    );
  }

  /// Google Drive 폴더 공유 URL 또는 순수 폴더 ID에서 폴더 ID를 추출한다.
  static String extractFolderId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    final urlMatch = RegExp(
      r'/folders/([a-zA-Z0-9_-]+)',
    ).firstMatch(trimmed);
    if (urlMatch != null) {
      return urlMatch.group(1) ?? '';
    }
    final queryMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (queryMatch != null) {
      return queryMatch.group(1) ?? '';
    }
    return trimmed;
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    currentUserNotifier.dispose();
    hasDriveFilePermissionNotifier.dispose();
  }
}

class _DriveClientHandle {
  const _DriveClientHandle({
    required this.api,
    required this.httpClient,
    required this.accessToken,
    required this.user,
  });

  final drive.DriveApi api;
  final http.Client httpClient;
  final String accessToken;
  final GoogleSignInAccount user;

  void close() => httpClient.close();
}

class _GoogleAuthHttpClient extends http.BaseClient {
  _GoogleAuthHttpClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class DriveServiceException implements Exception {
  const DriveServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DriveAuthException extends DriveServiceException {
  const DriveAuthException(super.message);
}
