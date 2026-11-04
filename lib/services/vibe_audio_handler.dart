import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

/// Puente entre el reproductor (just_audio) y los controles del sistema:
/// pantalla de bloqueo / Centro de Control en iOS, notificación y auriculares en Android.
class VibeAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  /// Callbacks que conecta AudioPlayerService para moverse por su propia cola
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;
  Future<void> Function()? onPlaybackCompleted;

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
      if (state == ProcessingState.completed) {
        _handlePlaybackCompleted();
      }
    });
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);

      // Gestionar interrupciones de audio en iOS (llamadas telefónicas, alarmas, Siri)
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              player.setVolume(0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });
    } catch (e) {
      print('AudioSession init error: $e');
    }
  }

  void _handlePlaybackCompleted() {
    if (onPlaybackCompleted != null) {
      // Mantener la sesión activa indicando que estamos cargando/bufferizando la siguiente pista.
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.buffering,
        playing: true,
      ));
      onPlaybackCompleted!();
    } else {
      _broadcastState();
    }
  }

  void _broadcastState() {
    final playing = player.playing;
    final procState = player.processingState;

    final AudioProcessingState audioProcState;
    if (procState == ProcessingState.completed && onPlaybackCompleted != null) {
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

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
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
      playing: (procState == ProcessingState.completed && onPlaybackCompleted != null) ? true : playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
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
  Future<void> loadAndPlay(MediaItem item, AudioSource source) async {
    mediaItem.add(item);
    await player.setAudioSource(source);
    unawaited(player.play());
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
