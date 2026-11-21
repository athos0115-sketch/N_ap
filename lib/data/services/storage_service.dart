import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/novel_folder.dart';
import '../models/revision_bookmark.dart';
import 'edge_tts_service.dart';

/// `shared_preferences` 기반 경량 JSON 메타데이터·진도·설정 영속화 서비스.
/// 오디오 파일은 절대 저장하지 않으며 폴더 목록, 재생 위치, TTS 설정, 퇴고 로그만 관리한다.
class StorageService {
  StorageService(this._prefs);

  static const String _keyFolders = 'n_ap_folders_v1';
  static const String _keyVoice = 'n_ap_tts_voice_v1';
  static const String _keySpeed = 'n_ap_tts_speed_v1';
  static const String _keyPitch = 'n_ap_tts_pitch_v1';
  static const String _keyNuance = 'n_ap_tts_nuance_v1';
  static const String _keyFontSizeLevel = 'n_ap_font_size_level_v1';
  static const String _keyBookmarks = 'n_ap_bookmarks_v1';
  static const String _keyServerClientId = 'n_ap_google_server_client_id_v1';
  static const String _keyLastFolderId = 'n_ap_last_folder_id_v1';

  final SharedPreferences _prefs;

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // --- 등록 폴더 및 진도 ---

  List<NovelFolder> loadFolders() {
    final raw = _prefs.getString(_keyFolders);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(NovelFolder.fromJson)
          .where((f) => f.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveFolders(List<NovelFolder> folders) async {
    final encoded = jsonEncode(folders.map((f) => f.toJson()).toList());
    await _prefs.setString(_keyFolders, encoded);
  }

  String? loadLastFolderId() => _prefs.getString(_keyLastFolderId);

  Future<void> saveLastFolderId(String? folderId) async {
    if (folderId == null || folderId.isEmpty) {
      await _prefs.remove(_keyLastFolderId);
    } else {
      await _prefs.setString(_keyLastFolderId, folderId);
    }
  }

  // --- TTS 설정 ---

  String loadVoice() {
    final raw = _prefs.getString(_keyVoice);
    if (raw == null || raw.isEmpty) return EdgeTtsService.defaultFemaleVoice;
    return EdgeTtsService.normalizeVoiceId(raw);
  }

  Future<void> saveVoice(String voiceId) async {
    await _prefs.setString(_keyVoice, EdgeTtsService.normalizeVoiceId(voiceId));
  }

  double loadSpeed() {
    final val = _prefs.getDouble(_keySpeed) ?? 1.0;
    return val.clamp(0.8, 2.0);
  }

  Future<void> saveSpeed(double speed) async {
    await _prefs.setDouble(_keySpeed, speed.clamp(0.8, 2.0));
  }

  int loadPitchHz() {
    final val = _prefs.getInt(_keyPitch) ?? 0;
    return val.clamp(-6, 6);
  }

  Future<void> savePitchHz(int pitchHz) async {
    await _prefs.setInt(_keyPitch, pitchHz.clamp(-6, 6));
  }

  bool loadNuanceEnabled() => _prefs.getBool(_keyNuance) ?? true;

  Future<void> saveNuanceEnabled(bool enabled) async {
    await _prefs.setBool(_keyNuance, enabled);
  }

  /// 원고 글자 크기 단계 (`0: S`, `1: M`, `2: L`)
  int loadFontSizeLevel() => (_prefs.getInt(_keyFontSizeLevel) ?? 1).clamp(0, 2);

  Future<void> saveFontSizeLevel(int level) async {
    await _prefs.setInt(_keyFontSizeLevel, level.clamp(0, 2));
  }

  // --- Google OAuth 선택적 Web Client ID ---

  String? loadServerClientId() {
    final val = _prefs.getString(_keyServerClientId)?.trim();
    return (val == null || val.isEmpty) ? null : val;
  }

  Future<void> saveServerClientId(String? clientId) async {
    final trimmed = clientId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await _prefs.remove(_keyServerClientId);
    } else {
      await _prefs.setString(_keyServerClientId, trimmed);
    }
  }

  // --- 퇴고 북마크 로그 ---

  List<RevisionBookmark> loadBookmarks() {
    final raw = _prefs.getString(_keyBookmarks);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(RevisionBookmark.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveBookmarks(List<RevisionBookmark> bookmarks) async {
    final encoded = jsonEncode(bookmarks.map((b) => b.toJson()).toList());
    await _prefs.setString(_keyBookmarks, encoded);
  }
}
