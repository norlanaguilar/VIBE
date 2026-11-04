import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Puente entre el reproductor (just_audio) y los controles del sistema:
/// pantalla de bloqueo / Centro de Control en iOS, notificación y auriculares en Android.
///
/// A diferencia de just_audio_background, aquí declaramos explícitamente los
/// botones Anterior / Siguiente, así iOS los muestra activos aunque solo haya
/// una canción cargada en el reproductor (la cola la maneja AudioPlayerService).
class VibeAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();

  /// Callbacks que conecta AudioPlayerService para moverse por su propia cola
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  VibeAudioHandler() {
    player.playbackEventStream.listen((_) => _broadcastState(), onError: (Object e, StackTrace st) {
      // Errores de red en streaming: se reporta el estado para que la UI no se congele
      _broadcastState();
    });
    player.playingStream.listen((_) => _broadcastState());
  }

  void _broadcastState() {
    final playing = player.playing;
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
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: 0,
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
