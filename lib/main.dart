import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'services/download_service.dart';
import 'controllers/favorites_controller.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background audio playback service
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.antigravity.ytdownload.channel.audio',
    androidNotificationChannelName: 'YouTube Playback',
    androidNotificationOngoing: true,
  );

  // Configure AudioSession for music playback to prevent volume ducking by OS
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // Initialize download service (loads local cache metadata)
  await DownloadService().init();

  // Initialize favorites service
  await FavoritesController().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enjoy Watch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.red,
          secondary: Colors.redAccent,
          surface: Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}
