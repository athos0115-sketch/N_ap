import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// 디스크 저장 없이 RAM 내 `Uint8List` 오디오 청크를 `just_audio`에 직접 스트리밍하는 소스.
// ignore: experimental_member_use
class MemoryAudioSource extends StreamAudioSource {
  MemoryAudioSource(
    Uint8List bytes, {
    this.contentType = 'audio/mpeg',
    super.tag,
  }) : _bytes = bytes;

  Uint8List? _bytes;
  final String contentType;

  int get byteLength => _bytes?.length ?? 0;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final data = _bytes;
    if (data == null) {
      throw StateError('MemoryAudioSource has already been released.');
    }
    final safeStart = (start ?? 0).clamp(0, data.length);
    final safeEnd = (end ?? data.length).clamp(safeStart, data.length);

    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: data.length,
      contentLength: safeEnd - safeStart,
      offset: safeStart,
      stream: Stream<List<int>>.value(data.sublist(safeStart, safeEnd)),
      contentType: contentType,
    );
  }

  /// 재생 완료 후 RAM 버퍼 참조를 즉시 해제한다.
  void release() {
    _bytes = null;
  }
}
