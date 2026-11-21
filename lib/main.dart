import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';

import 'audio/novel_audio_handler.dart';
import 'audio/playback_controller.dart';
import 'core/theme/darkroom_theme.dart';
import 'data/services/drive_service.dart';
import 'data/services/storage_service.dart';
import 'presentation/screens/home_folders_screen.dart';

const String _envGoogleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final audioHandler = await AudioService.init(
    builder: NovelAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.vyxion.n_ap.channel.audio',
      androidNotificationChannelName: 'N_ap 낭독 재생',
      androidNotificationChannelDescription:
          '화면 잠금 및 타 앱 동시 재생을 지원하는 소설 낭독 서비스',
      androidStopForegroundOnPause: false,
      androidNotificationOngoing: false,
    ),
  );

  final storageService = await StorageService.create();
  final driveService = DriveService(
    defaultServerClientId: _envGoogleServerClientId.isEmpty
        ? null
        : _envGoogleServerClientId,
  );
  final controller = PlaybackController(
    audioHandler: audioHandler,
    driveService: driveService,
    storageService: storageService,
  );
  await controller.initialize();

  runApp(NapApp(controller: controller));
}

class NapApp extends StatelessWidget {
  const NapApp({
    super.key,
    required this.controller,
  });

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'N_ap',
      debugShowCheckedModeBanner: false,
      theme: DarkroomTheme.buildThemeData(),
      home: HomeFoldersScreen(controller: controller),
    );
  }
}
