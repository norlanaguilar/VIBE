import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_container.dart';

class LikedScreen extends StatelessWidget {
  const LikedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context);
    final likedSongs = audioService.likedSongs;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top App Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Me gusta',
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.primary,
                        fontSize: 26,
                      ),
                    ),
                    const Icon(Icons.favorite, color: AppColors.secondary),
                  ],
                ),
              ),
            ),

            // Action Header Banner Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(20),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Gradient Heart Tile
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryContainer, AppColors.secondaryContainer],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryContainer.withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.favorite, color: Colors.white, size: 40),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Text & Buttons
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Liked Songs',
                              style: AppTypography.headlineSm.copyWith(
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${likedSongs.length} tracks',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Action Buttons
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: likedSongs.isEmpty
                                      ? null
                                      : () => audioService.playPlaylist(likedSongs, likedSongs.first),
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  label: const Text('PLAY ALL'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.onPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    textStyle: AppTypography.labelCaps.copyWith(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: likedSongs.isEmpty
                                      ? null
                                      : () {
                                          audioService.toggleShuffle();
                                          audioService.playPlaylist(likedSongs, likedSongs.first);
                                        },
                                  icon: const Icon(Icons.shuffle, size: 16),
                                  label: const Text('SHUFFLE'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.onSurface,
                                    side: BorderSide(color: AppColors.outlineVariant.withOpacity(0.5)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    textStyle: AppTypography.labelCaps.copyWith(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Liked Songs List
            likedSongs.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Aún no tienes canciones en Me gusta',
                        style: AppTypography.bodySm,
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final song = likedSongs[index];
                        final isCurrent = audioService.currentSong?.id == song.id;

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                          child: GlassContainer(
                            borderRadius: BorderRadius.circular(12),
                            backgroundColor: isCurrent
                                ? AppColors.primaryContainer.withOpacity(0.2)
                                : AppColors.surfaceContainerLow.withOpacity(0.6),
                            padding: const EdgeInsets.all(8.0),
                            onTap: () => audioService.playPlaylist(likedSongs, song),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: _buildCover(song),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        style: AppTypography.bodyLg.copyWith(
                                          fontSize: 15,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                          color: isCurrent ? AppColors.primary : AppColors.onSurface,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        song.artist,
                                        style: AppTypography.bodySm.copyWith(
                                          fontSize: 12,
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.favorite, color: AppColors.secondary),
                                  onPressed: () => audioService.toggleLike(song),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: likedSongs.length,
                    ),
                  ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(Song song) {
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
        child: Icon(Icons.music_note, color: AppColors.primary),
      ),
    );
  }
}
