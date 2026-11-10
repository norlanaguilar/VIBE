import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/audio_player_service.dart';
import 'services/vibe_audio_handler.dart';
import 'theme/app_colors.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final audioHandler = await AudioService.init(
    builder: () => VibeAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.vibe_local.audio',
      androidNotificationChannelName: 'Vibe App Reproducción',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioPlayerService(audioHandler)),
      ],
      child: const VibeLocalApp(),
    ),
  );
}

class VibeLocalApp extends StatelessWidget {
  const VibeLocalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vibe App',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
