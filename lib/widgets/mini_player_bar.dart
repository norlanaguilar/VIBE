import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../screens/now_playing_screen.dart';

class MiniPlayerBar extends StatelessWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerService>(
      builder: (context, audioService, child) {
        final song = audioService.currentSong;
        if (song == null) return const SizedBox.shrink();

        Widget coverWidget;
        if (song.localCoverPath != null && File(song.localCoverPath!).existsSync()) {
          coverWidget = Image.file(
            File(song.localCoverPath!),
            fit: BoxFit.cover,
          );
        } else if (song.coverUrl != null && song.coverUrl!.startsWith('http')) {
          coverWidget = Image.network(
            song.coverUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackCover(),
          );
        } else {
          coverWidget = _buildFallbackCover();
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const NowPlayingScreen(),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: coverWidget,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            style: AppTypography.bodyLg.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            style: AppTypography.bodySm.copyWith(
                              fontSize: 12,
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
                        size: 22,
                      ),
                      onPressed: () => audioService.toggleLike(song),
                    ),
                    IconButton(
                      icon: Icon(
                        audioService.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: AppColors.primary,
                        size: 36,
                      ),
                      onPressed: () => audioService.togglePlayPause(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallbackCover() {
    return Container(
      color: AppColors.primaryContainer.withOpacity(0.5),
      child: const Center(
        child: Icon(Icons.music_note, color: AppColors.primary, size: 24),
      ),
    );
  }
}
