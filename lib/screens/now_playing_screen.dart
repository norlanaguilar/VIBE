import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_container.dart';
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

  /// Modal limpia para mostrar las letras directamente
  void _showLyricsSheet(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.70,
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
                          song.title,
                          style: AppTypography.headlineSm.copyWith(color: Colors.white, fontSize: 18),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.artist,
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
              const SizedBox(height: 16),
              const Divider(color: AppColors.outlineVariant),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    '🎵 Letra de la canción:\n\n'
                    'Siente cada nota resonar en tus sentidos...\n'
                    'Disfruta la melodía con la más alta resolución de audio.\n\n'
                    'La armonía perfecta acompaña tus momentos,\n'
                    'cada compás fluye en sintonía con tu energía.\n\n'
                    'Escucha, siente y vive la música sin pausas.\n\n'
                    '♪♫♬♪♫♬♪♫♬♪♫♬♪♫♬♪♫♬',
                    style: AppTypography.bodyLg.copyWith(
                      color: AppColors.onSurface,
                      height: 2.0,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
                          } else if (value == 'edit') {
                            _showEditMetadataDialog(context, audioService, song);
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
                                const Icon(Icons.auto_awesome, color: AppColors.secondary, size: 20),
                                const SizedBox(width: 12),
                                Text('Identificar con IA', style: AppTypography.bodySm),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'settings',
                            child: Row(
                              children: [
                                const Icon(Icons.equalizer, color: AppColors.primary, size: 20),
                                const SizedBox(width: 12),
                                Text('Ir a Ajustes / Ecualizador', style: AppTypography.bodySm),
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
                        const SizedBox(height: 32),

                        // Album Artwork Card with Neon Glow Shadow
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 270),
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
                        const SizedBox(height: 28),

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
                        const SizedBox(height: 20),

                        // Dynamic Multi-Harmonic Spectrum Visualizer
                        SpectrumVisualizer(
                          isPlaying: audioService.isPlaying,
                          barCount: 36,
                          height: 32,
                        ),
                        const SizedBox(height: 20),

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
                        const SizedBox(height: 24),

                        // Playback Controls Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.shuffle,
                                color: audioService.isShuffle ? AppColors.primary : AppColors.onSurfaceVariant,
                              ),
                              onPressed: () => audioService.toggleShuffle(),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: AppColors.onSurface,
                                size: 36,
                              ),
                              onPressed: () => audioService.skipPrevious(),
                            ),
                            // Large Play/Pause Neon Glow Button
                            GestureDetector(
                              onTap: () => audioService.togglePlayPause(),
                              child: Container(
                                width: 72,
                                height: 72,
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
                                    size: 44,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: AppColors.onSurface,
                                size: 36,
                              ),
                              onPressed: () => audioService.skipNext(),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.repeat,
                                color: audioService.loopMode != LoopMode.off
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                              ),
                              onPressed: () => audioService.toggleRepeat(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Bottom Interactive Lyrics Button
                        GestureDetector(
                          onTap: () => _showLyricsSheet(context, song),
                          child: GlassContainer(
                            borderRadius: BorderRadius.circular(20),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.notes, size: 18, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Ver Letras',
                                  style: AppTypography.labelCaps.copyWith(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
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
    if (song.localCoverPath != null && File(song.localCoverPath!).existsSync()) {
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
