import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
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
        body: Center(child: Text('No song selected')),
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
                  child: _buildCoverImage(song),
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
                  padding: const EdgeInsets.fromLTRB(16.0, 36.0, 16.0, 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.primary, size: 32),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Text(
                        'Now Playing',
                        style: AppTypography.headlineSm.copyWith(
                          color: AppColors.primary,
                          fontSize: 18,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.settings_suggest, color: AppColors.primary, size: 26),
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
                                  content: Text('🎬 Video asignado como carátula (en bucle y sin audio)'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else if (value == 'ai_tag') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🤖 Identificando canción con IA...'),
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
                                Text('➕ Agregar a Playlist', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'lyrics',
                            child: Row(
                              children: [
                                const Icon(Icons.subtitles, color: AppColors.secondary, size: 20),
                                const SizedBox(width: 12),
                                Text('📜 Ver Letras Sincronizadas', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'video',
                            child: Row(
                              children: [
                                const Icon(Icons.video_library, color: AppColors.tertiary, size: 20),
                                const SizedBox(width: 12),
                                Text('🎬 Elegir Video de la Galería', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                const Icon(Icons.edit_note, color: AppColors.primary, size: 20),
                                const SizedBox(width: 12),
                                Text('✏️ Editar Título y Artista', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'ai_tag',
                            child: Row(
                              children: [
                                const Icon(Icons.auto_awesome, color: AppColors.secondary, size: 20),
                                const SizedBox(width: 12),
                                Text('🤖 Identificar con IA', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'settings',
                            child: Row(
                              children: [
                                const Icon(Icons.equalizer, color: AppColors.primary, size: 20),
                                const SizedBox(width: 12),
                                Text('⚙️ Ecualizador & Ajustes', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 36),

                        // Album Artwork / Video Cover Card with Neon Glow Shadow
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 280),
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
                              aspectRatio: 1.0,
                              child: _buildCoverImage(song),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

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
                        const SizedBox(height: 24),

                        // Dynamic Multi-Harmonic Spectrum Visualizer
                        SpectrumVisualizer(
                          isPlaying: audioService.isPlaying,
                          barCount: 36,
                          height: 32,
                        ),
                        const SizedBox(height: 24),

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
                        const SizedBox(height: 28),

                        // Playback Controls Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.shuffle,
                                color: audioService.isShuffle ? AppColors.primary : AppColors.onSurfaceVariant,
                                size: 28,
                              ),
                              onPressed: () => audioService.toggleShuffle(),
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
                                  child: Icon(
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
                            IconButton(
                              icon: Icon(
                                audioService.loopMode == LoopMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                color: audioService.loopMode != LoopMode.off
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                                size: 28,
                              ),
                              onPressed: () => audioService.toggleRepeat(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 48),
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

  Widget _buildCoverImage(Song song) {
    if (song.videoCoverPath != null && File(song.videoCoverPath!).existsSync()) {
      return LoopedMutedVideoCoverWidget(videoPath: song.videoCoverPath!);
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
  const LoopedMutedVideoCoverWidget({super.key, required this.videoPath});

  @override
  State<LoopedMutedVideoCoverWidget> createState() => _LoopedMutedVideoCoverWidgetState();
}

class _LoopedMutedVideoCoverWidgetState extends State<LoopedMutedVideoCoverWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

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
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      final file = File(widget.videoPath);
      if (await file.exists()) {
        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        await controller.setVolume(0.0); // Muted (sin audio del video)
        await controller.setLooping(true); // Bucle infinito
        await controller.play();
        if (mounted) {
          setState(() {
            _controller = controller;
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
    if (_isInitialized && _controller != null && _controller!.value.isInitialized) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
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
        _isLoading = false;
      });
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
                        Text('Buscando letras en tiempo real...', style: TextStyle(color: Colors.white70)),
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
                        ? ListView.builder(
                            controller: _scrollController,
                            itemCount: _lyricsResult.syncedLines.length,
                            itemBuilder: (context, index) {
                              final line = _lyricsResult.syncedLines[index];
                              final isCurrent = index < _lyricsResult.syncedLines.length - 1
                                  ? (currentPos >= line.timestamp && currentPos < _lyricsResult.syncedLines[index + 1].timestamp)
                                  : currentPos >= line.timestamp;

                              return GestureDetector(
                                onTap: () => audioService.seek(line.timestamp),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      color: isCurrent ? AppColors.primary : Colors.white.withOpacity(0.5),
                                      fontSize: isCurrent ? 20 : 16,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      height: 1.4,
                                    ),
                                    child: Text(
                                      line.text,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
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
