import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Puente entre el reproductor (just_audio) y los controles del sistema:
/// pantalla de bloqueo / Centro de Control en iOS, notificación y auriculares en Android.
class VibeAudioHandler extends BaseAudioHandler with SeekHandler {
  static const MethodChannel _iosEqualizerChannel = MethodChannel('vibe/equalizer');

  late final AndroidEqualizer _androidEqualizer = AndroidEqualizer();
  late final AndroidLoudnessEnhancer _androidLoudnessEnhancer = AndroidLoudnessEnhancer();

  late final AudioPlayer player = AudioPlayer(
    audioPipeline: Platform.isAndroid
        ? AudioPipeline(
            androidAudioEffects: [
              _androidEqualizer,
              _androidLoudnessEnhancer,
            ],
          )
        : null,
  );

  /// Callbacks que conecta AudioPlayerService para moverse por su propia cola
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function()? onPlaybackCompleted;

  /// Mantiene activa la sesión de reproducción de iOS mientras se cambia de pista
  bool isTransitioning = false;

  VibeAudioHandler() {
    _initAudioSession();

    player.playbackEventStream.listen((_) => _broadcastState(), onError: (Object e, StackTrace st) {
      // Errores de red en streaming: se reporta el estado para que la UI no se congele
      _broadcastState();
    });
    player.playingStream.listen((_) => _broadcastState());

    // Al terminar una canción: nunca emitir 'completed' si hay callback para avanzar,
    // porque en iOS eso destruye inmediatamente el widget de la pantalla de bloqueo
    // y el sistema suspende la aplicación en segundo plano.
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !isTransitioning) {
        _handlePlaybackCompleted();
      }
    });
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.longFormAudio,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
      await session.setActive(true);
    } catch (e) {
      print('AudioSession init error: $e');
    }
  }

  void beginTransition(MediaItem item) {
    isTransitioning = true;
    mediaItem.add(item);
    _broadcastState();
  }

  void endTransition() {
    if (isTransitioning) {
      isTransitioning = false;
      _broadcastState();
    }
  }

  void broadcastCurrentState() => _broadcastState();

  void _handlePlaybackCompleted() {
    if (onPlaybackCompleted != null) {
      // Mantener la sesión activa indicando que estamos cargando/bufferizando la siguiente pista.
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.buffering,
        playing: true,
        updatePosition: Duration.zero,
      ));
      onPlaybackCompleted!();
    } else {
      _broadcastState();
    }
  }

  void _broadcastState() {
    final playing = player.playing;
    final procState = player.processingState;
    final keepAliveInBackground =
        isTransitioning || (procState == ProcessingState.completed && onPlaybackCompleted != null);

    final AudioProcessingState audioProcState;
    if (keepAliveInBackground) {
      audioProcState = AudioProcessingState.buffering;
    } else {
      audioProcState = const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[procState]!;
    }

    final effectivePlaying = keepAliveInBackground ? true : playing;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (effectivePlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: audioProcState,
      playing: effectivePlaying,
      updatePosition: isTransitioning ? Duration.zero : player.position,
      bufferedPosition: isTransitioning ? Duration.zero : player.bufferedPosition,
      speed: player.speed,
    ));
  }

  /// Actualiza la cola de reproducción en los controles del sistema (iOS / Android)
  void updateQueueState(List<MediaItem> items, int currentIndex) {
    queue.add(items);
    playbackState.add(playbackState.value.copyWith(
      queueIndex: currentIndex,
    ));
  }

  /// Carga una pista con sus metadatos (título, artista, carátula) para la pantalla bloqueada
  Future<void> loadAndPlay(MediaItem item, AudioSource source, {double volume = 1.0}) async {
    isTransitioning = true;
    mediaItem.add(item);
    _broadcastState();
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (_) {}
    if (Platform.isAndroid) {
      unawaited(_androidEqualizer.setEnabled(true));
      unawaited(_androidLoudnessEnhancer.setEnabled(true));
    }
    await player.setAudioSource(source, initialPosition: Duration.zero);
    await player.setVolume(volume);
    isTransitioning = false;
    unawaited(player.play());
    _broadcastState();
  }

  /// Aplica las 5 bandas del ecualizador (60Hz, 230Hz, 910Hz, 4kHz, 14kHz) en tiempo real
  Future<void> applyEqualizerGains(List<double> normalizedGains) async {
    if (normalizedGains.length < 5) return;
    if (Platform.isIOS) {
      try {
        await _iosEqualizerChannel.invokeMethod('setGains', {
          'gains': normalizedGains.take(5).toList(),
        });
      } catch (_) {}
    } else if (Platform.isAndroid) {
      try {
        await _androidEqualizer.setEnabled(true);
        final params = await _androidEqualizer.parameters;
        final minDb = params.minDecibels;
        final maxDb = params.maxDecibels;
        final bands = params.bands;
        for (int i = 0; i < bands.length; i++) {
          final normIdx = bands.length == 1
              ? 0.0
              : (i / (bands.length - 1)) * 4.0;
          final lowIdx = normIdx.floor().clamp(0, 4);
          final highIdx = normIdx.ceil().clamp(0, 4);
          final t = normIdx - lowIdx;
          final g = normalizedGains[lowIdx] * (1.0 - t) + normalizedGains[highIdx] * t;
          final targetDb = minDb + g.clamp(0.0, 1.0) * (maxDb - minDb);
          await bands[i].setGain(targetDb.clamp(minDb, maxDb));
        }
        await _androidLoudnessEnhancer.setEnabled(true);
        final bassBoost = ((normalizedGains[0] - 0.5) * 6.0).clamp(0.0, 4.0);
        await _androidLoudnessEnhancer.setTargetGain(bassBoost);
      } catch (_) {}
    }
  }

  /// Actualiza los metadatos mostrados sin recargar el audio (ej: al editar título)
  void updateNowPlaying(MediaItem item) => mediaItem.add(item);

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => onSkipToNext?.call();

  @override
  Future<void> skipToPrevious() async => onSkipToPrevious?.call();
}
