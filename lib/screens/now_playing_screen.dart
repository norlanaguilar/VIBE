import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../services/lyrics_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/spectrum_visualizer.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  /// Dialog para editar manualmente Nombre y Artista de la canción
  void _showEditMetadataDialog(BuildContext context, AudioPlayerService audioService, Song song) {
    final titleController = TextEditingController(text: song.title);
    final artistController = TextEditingController(text: song.artist == 'Artista Local' ? '' : song.artist);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Editar Metadatos',
            style: AppTypography.headlineSm.copyWith(color: AppColors.primary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Escribe el nombre correcto de la canción y el artista para que la IA descargue la carátula oficial y álbum.',
                style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nombre de la canción',
                  labelStyle: const TextStyle(color: AppColors.primary),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: artistController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nombre del Artista',
                  labelStyle: const TextStyle(color: AppColors.secondary),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.onSurfaceVariant)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Buscando carátula oficial y álbum con IA...'),
                    backgroundColor: AppColors.primaryContainer,
                  ),
                );
                final updated = await audioService.updateSongMetadata(song, titleController.text, artistController.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('¡Actualizado!: ${updated.title} - ${updated.artist}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Guardar e Identificar'),
            ),
          ],
        );
      },
    );
  }

  void _showLyricsSheet(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => RealSyncedLyricsModal(song: song),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context);
    final song = audioService.currentSong;

    if (song == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('Ninguna canción seleccionada')),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          // Background blurred artwork for ambient Glassmorphism depth
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: Opacity(
                opacity: 0.25,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: _buildCoverImage(song, isPlaying: audioService.isPlaying, isBackground: true),
                ),
              ),
            ),
          ),

          // Main Screen Shell
          SafeArea(
            child: Column(
              children: [
                // Top Header Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 6.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 32),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Text(
                        'Reproduciendo Ahora',
                        style: AppTypography.headlineSm.copyWith(
                          color: AppColors.primary,
                          fontSize: 18,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.settings, color: AppColors.primary, size: 26),
                        color: AppColors.surfaceContainerHigh,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onSelected: (value) async {
                          if (value == 'settings') {
                            Navigator.of(context).pop();
                          } else if (value == 'playlist') {
                            showAddToPlaylistModal(context, audioService, song);
                          } else if (value == 'edit') {
                            _showEditMetadataDialog(context, audioService, song);
                          } else if (value == 'lyrics') {
                            _showLyricsSheet(context, song);
                          } else if (value == 'video') {
                            final updated = await audioService.setVideoCoverForSong(song);
                            if (updated != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Video asignado como carátula (en bucle y sin audio)'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else if (value == 'ai_tag') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Identificando canción con IA...'),
                                backgroundColor: AppColors.primaryContainer,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            final updated = await audioService.runAiIdentificationForSong(song);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('¡Identificada!: ${updated?.title} - ${updated?.artist}'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'playlist',
                            child: Row(
                              children: [
                                const Icon(Icons.playlist_add, color: AppColors.primary, size: 20),
                                const SizedBox(width: 12),
                                Text('Agregar a Playlist', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'lyrics',
                            child: Row(
                              children: [
                                const Icon(Icons.subtitles, color: AppColors.secondary, size: 20),
                                const SizedBox(width: 12),
                                Text('Ver Letras Sincronizadas', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'video',
                            child: Row(
                              children: [
                                const Icon(Icons.video_library, color: AppColors.tertiary, size: 20),
                                const SizedBox(width: 12),
                                Text('Elegir Video de la Galería', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                const Icon(Icons.edit_note, color: AppColors.primary, size: 20),
                                const SizedBox(width: 12),
                                Text('Editar Título y Artista', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'ai_tag',
                            child: Row(
                              children: [
                                const Icon(Icons.manage_search, color: AppColors.secondary, size: 20),
                                const SizedBox(width: 12),
                                Text('Identificar', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'settings',
                            child: Row(
                              children: [
                                const Icon(Icons.equalizer, color: AppColors.primary, size: 20),
                                const SizedBox(width: 12),
                                Text('Ecualizador y Ajustes', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Spacer(flex: 1),

                        // Album Artwork / Video Cover Card with Neon Glow Shadow (más alto para no recortar carátulas)
                        Expanded(
                          flex: 12,
                          child: Center(
                            child: Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxWidth: 400),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.35),
                                    blurRadius: 30,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: AspectRatio(
                                  aspectRatio: 0.92,
                                  child: _buildCoverImage(song, isPlaying: audioService.isPlaying),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        const Spacer(flex: 1),

                        // Title, Artist, & Favorite Heart Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    song.title,
                                    style: AppTypography.headlineMd.copyWith(
                                      color: AppColors.onSurface,
                                      fontSize: 22,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    song.artist,
                                    style: AppTypography.bodyLg.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (song.isDownloaded) ...[
                              IconButton(
                                icon: const Icon(
                                  Icons.download_done_rounded,
                                  color: AppColors.secondary,
                                  size: 26,
                                ),
                                tooltip: 'Descargada (Disponible Offline)',
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Esta canción ya está guardada para reproducir sin conexión.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ] else if (audioService.isSongDownloading(song.id)) ...[
                              const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ] else if (song.youtubeId != null || song.isStreaming) ...[
                              IconButton(
                                icon: const Icon(
                                  Icons.arrow_circle_down_rounded,
                                  color: AppColors.onSurfaceVariant,
                                  size: 28,
                                ),
                                tooltip: 'Descargar para escuchar sin conexión',
                                onPressed: () async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Descargando "${song.title}" para escuchar sin internet...'),
                                      backgroundColor: AppColors.primaryContainer,
                                    ),
                                  );
                                  try {
                                    await audioService.downloadSongForOffline(song);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('¡"${song.title}" guardada para escuchar sin conexión!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error al descargar: $e'),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                            IconButton(
                              icon: Icon(
                                song.isLiked ? Icons.favorite : Icons.favorite_border,
                                color: song.isLiked ? AppColors.secondary : AppColors.onSurfaceVariant,
                                size: 28,
                              ),
                              onPressed: () => audioService.toggleLike(song),
                            ),
                          ],
                        ),
                        
                        const Spacer(flex: 1),

                        // Dynamic Multi-Harmonic Spectrum Visualizer
                        SpectrumVisualizer(
                          isPlaying: audioService.isPlaying,
                          barCount: 36,
                          height: 32,
                        ),
                        
                        const Spacer(flex: 1),

                        // Progress Seek Bar & Timers
                        Column(
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: AppColors.primary,
                                inactiveTrackColor: AppColors.surfaceVariant.withOpacity(0.5),
                                thumbColor: Colors.white,
                                overlayColor: AppColors.primary.withOpacity(0.2),
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              ),
                              child: Slider(
                                value: audioService.position.inSeconds
                                    .toDouble()
                                    .clamp(0.0, audioService.duration.inSeconds.toDouble() == 0 ? 1.0 : audioService.duration.inSeconds.toDouble()),
                                max: audioService.duration.inSeconds.toDouble() == 0 ? 1.0 : audioService.duration.inSeconds.toDouble(),
                                onChanged: (val) {
                                  audioService.seek(Duration(seconds: val.toInt()));
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatTime(audioService.position),
                                    style: AppTypography.monoLabel,
                                  ),
                                  Text(
                                    _formatTime(audioService.duration),
                                    style: AppTypography.monoLabel,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        
                        const Spacer(flex: 1),

                        // Playback Controls Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildModeButton(
                              isActive: audioService.isShuffle,
                              icon: Icons.shuffle,
                              tooltip: audioService.isShuffle ? 'Aleatorio: ACTIVADO' : 'Aleatorio: DESACTIVADO',
                              activeColor: AppColors.primary,
                              onTap: () => audioService.toggleShuffle(),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: AppColors.onSurface,
                                size: 40,
                              ),
                              onPressed: () => audioService.skipPrevious(),
                            ),
                            // Large Play/Pause Neon Glow Button
                            GestureDetector(
                              onTap: () => audioService.togglePlayPause(),
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primaryContainer.withOpacity(0.4),
                                  border: Border.all(color: AppColors.primary.withOpacity(0.6), width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: audioService.isBuffering
                                      ? const SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : Icon(
                                          audioService.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: AppColors.primary,
                                          size: 46,
                                        ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: AppColors.onSurface,
                                size: 40,
                              ),
                              onPressed: () => audioService.skipNext(),
                            ),
                            _buildModeButton(
                              isActive: audioService.loopMode != LoopMode.off,
                              icon: audioService.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                              tooltip: audioService.loopMode == LoopMode.one
                                  ? 'Repetir: UNA CANCIÓN'
                                  : (audioService.loopMode == LoopMode.all ? 'Repetir: TODA LA LISTA' : 'Repetir: DESACTIVADO'),
                              activeColor: audioService.loopMode == LoopMode.one ? AppColors.secondary : AppColors.primary,
                              onTap: () => audioService.toggleRepeat(),
                            ),
                          ],
                        ),
                        
                        const Spacer(flex: 2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required bool isActive,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color activeColor = AppColors.primary,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withOpacity(0.20) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? activeColor : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.40),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? activeColor : AppColors.onSurfaceVariant.withOpacity(0.6),
                size: 26,
              ),
              const SizedBox(height: 2),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? activeColor : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(Song song, {required bool isPlaying, bool isBackground = false}) {
    if (isBackground && song.localCoverPath != null && File(song.localCoverPath!).existsSync()) {
      return Image.file(
        File(song.localCoverPath!),
        fit: BoxFit.cover,
      );
    }
    final hasVideoCover = song.videoCoverPath != null &&
        song.videoCoverPath!.isNotEmpty &&
        (song.videoCoverPath!.startsWith('ph://') || File(song.videoCoverPath!).existsSync());
    if (!isBackground && hasVideoCover) {
      return LoopedMutedVideoCoverWidget(videoPath: song.videoCoverPath!, isPlaying: isPlaying);
    } else if (song.localCoverPath != null && File(song.localCoverPath!).existsSync()) {
      return Image.file(
        File(song.localCoverPath!),
        fit: BoxFit.cover,
      );
    } else if (song.coverUrl != null && song.coverUrl!.startsWith('http')) {
      return Image.network(
        song.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackCover(),
      );
    }
    return _fallbackCover();
  }

  Widget _fallbackCover() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Center(
        child: Icon(Icons.music_note, color: AppColors.primary, size: 64),
      ),
    );
  }

  String _formatTime(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class LoopedMutedVideoCoverWidget extends StatefulWidget {
  final String videoPath;
  final bool isPlaying;
  const LoopedMutedVideoCoverWidget({
    super.key,
    required this.videoPath,
    required this.isPlaying,
  });

  @override
  State<LoopedMutedVideoCoverWidget> createState() => _LoopedMutedVideoCoverWidgetState();
}

class _LoopedMutedVideoCoverWidgetState extends State<LoopedMutedVideoCoverWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  double _cropScale = 1.06;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  @override
  void didUpdateWidget(LoopedMutedVideoCoverWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _controller?.dispose();
      _isInitialized = false;
      _cropScale = 1.06;
      _initVideo();
    } else if (oldWidget.isPlaying != widget.isPlaying) {
      _syncPlayPause();
    }
  }

  void _syncPlayPause() {
    if (_controller != null && _isInitialized && _controller!.value.isInitialized) {
      if (widget.isPlaying && !_controller!.value.isPlaying) {
        _controller!.play();
      } else if (!widget.isPlaying && _controller!.value.isPlaying) {
        _controller!.pause();
      }
    }
  }

  Future<void> _initVideo() async {
    try {
      String? resolvedPath = widget.videoPath;
      double detectedScale = 1.06;

      if (Platform.isIOS) {
        try {
          const galleryChannel = MethodChannel('vibe/gallery');
          final res = await galleryChannel.invokeMethod<dynamic>(
            'resolveVideo',
            {'ref': widget.videoPath},
          );
          if (res is Map) {
            resolvedPath = res['path']?.toString();
            final sc = (res['cropScale'] as num?)?.toDouble();
            if (sc != null && sc > 1.0) {
              detectedScale = sc;
            }
          }
        } catch (_) {}
      }

      if (resolvedPath == null || resolvedPath.isEmpty || resolvedPath.startsWith('ph://')) {
        return;
      }

      final file = File(resolvedPath);
      if (await file.exists()) {
        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        await controller.setVolume(0.0); // Muted (sin audio del video)
        await controller.setLooping(true); // Bucle infinito
        if (widget.isPlaying) {
          await controller.play();
        } else {
          await controller.pause();
        }
        if (mounted) {
          setState(() {
            _controller = controller;
            _cropScale = detectedScale;
            _isInitialized = true;
          });
        }
      }
    } catch (e) {
      print('Video cover init error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncPlayPause();

    if (_isInitialized && _controller != null && _controller!.value.isInitialized) {
      final rawAspect = _controller!.value.aspectRatio;
      final safeAspect = (rawAspect > 0.1 && rawAspect.isFinite) ? rawAspect : 1.0;

      return ClipRect(
        child: Transform.scale(
          scale: _cropScale,
          alignment: Alignment.center,
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: 1000,
                height: 1000 / safeAspect,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      color: AppColors.surfaceVariant,
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

class RealSyncedLyricsModal extends StatefulWidget {
  final Song song;
  const RealSyncedLyricsModal({super.key, required this.song});

  @override
  State<RealSyncedLyricsModal> createState() => _RealSyncedLyricsModalState();
}

class _RealSyncedLyricsModalState extends State<RealSyncedLyricsModal> {
  bool _isLoading = true;
  LyricsResult _lyricsResult = LyricsResult.empty();
  final ScrollController _scrollController = ScrollController();
  List<GlobalKey> _lineKeys = [];
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    final result = await LyricsService.fetchLyrics(widget.song.artist, widget.song.title);
    if (mounted) {
      setState(() {
        _lyricsResult = result;
        _lineKeys = List.generate(result.syncedLines.length, (_) => GlobalKey());
        _isLoading = false;
      });
    }
  }

  void _scrollToActiveLine(int index) {
    if (index >= 0 && index < _lineKeys.length) {
      _lastActiveIndex = index;
      final keyContext = _lineKeys[index].currentContext;
      if (keyContext != null && keyContext.findRenderObject() != null) {
        Scrollable.ensureVisible(
          keyContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context);
    final currentPos = audioService.position;

    int activeIndex = -1;
    if (_lyricsResult.isSynced && _lyricsResult.syncedLines.isNotEmpty) {
      for (int i = 0; i < _lyricsResult.syncedLines.length; i++) {
        final line = _lyricsResult.syncedLines[i];
        final nextLineTime = i < _lyricsResult.syncedLines.length - 1
            ? _lyricsResult.syncedLines[i + 1].timestamp
            : const Duration(hours: 10);
        if (currentPos >= line.timestamp && currentPos < nextLineTime) {
          activeIndex = i;
          break;
        }
      }
      if (activeIndex != -1 && activeIndex != _lastActiveIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToActiveLine(activeIndex);
        });
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.song.title,
                      style: AppTypography.headlineSm.copyWith(color: Colors.white, fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.song.artist,
                      style: AppTypography.bodySm.copyWith(color: AppColors.secondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.outlineVariant),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        SizedBox(height: 16),
                        Text('Cargando letras en tiempo real...', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  )
                : !_lyricsResult.hasLyrics
                    ? Center(
                        child: Text(
                          'No se encontraron letras disponibles para esta canción.',
                          style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _lyricsResult.isSynced
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              final verticalPadding = constraints.maxHeight * 0.42;
                              return SingleChildScrollView(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.symmetric(
                                  vertical: verticalPadding,
                                  horizontal: 16.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: List.generate(_lyricsResult.syncedLines.length, (index) {
                                    final line = _lyricsResult.syncedLines[index];
                                    final isCurrent = index == activeIndex;
                                    final key = index < _lineKeys.length ? _lineKeys[index] : null;

                                    return GestureDetector(
                                      key: key,
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => audioService.seek(line.timestamp),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                                        child: AnimatedDefaultTextStyle(
                                          duration: const Duration(milliseconds: 250),
                                          style: TextStyle(
                                            color: isCurrent ? AppColors.primary : Colors.white.withOpacity(0.45),
                                            fontSize: isCurrent ? 22 : 16,
                                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                            height: 1.4,
                                          ),
                                          child: Text(
                                            line.text,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              );
                            },
                          )
                        : SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                _lyricsResult.plainLyrics,
                                style: AppTypography.bodyLg.copyWith(color: Colors.white, height: 1.8),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
