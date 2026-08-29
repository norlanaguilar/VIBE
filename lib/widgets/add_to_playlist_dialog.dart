import 'package:flutter/material.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

void showAddToPlaylistModal(BuildContext context, AudioPlayerService audioService, Song song) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final userPlaylists = audioService.userPlaylists;
          final playlistNames = audioService.playlistNames;

          return Container(
            height: MediaQuery.of(context).size.height * 0.65,
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

                // Header Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agregar a Playlist',
                            style: AppTypography.headlineSm.copyWith(color: AppColors.primary, fontSize: 20),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${song.title} - ${song.artist}',
                            style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
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

                // Button to Create New Playlist
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.add, size: 22),
                  label: const Text('Crear nueva Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    _showCreatePlaylistDialog(context, audioService, song, setModalState);
                  },
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.outlineVariant),
                const SizedBox(height: 12),

                // Existing Playlists List
                Expanded(
                  child: playlistNames.isEmpty
                      ? Center(
                          child: Text(
                            'No tienes playlists creadas.\n¡Crea una nueva arriba!',
                            style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: playlistNames.length,
                          itemBuilder: (context, index) {
                            final pName = playlistNames[index];
                            final songIds = userPlaylists[pName] ?? [];
                            final inPlaylist = songIds.contains(song.id);

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: inPlaylist ? AppColors.primaryContainer : AppColors.surfaceVariant,
                                  child: Icon(
                                    inPlaylist ? Icons.playlist_add_check : Icons.queue_music,
                                    color: inPlaylist ? Colors.white : AppColors.primary,
                                  ),
                                ),
                                title: Text(
                                  pName,
                                  style: AppTypography.headlineSm.copyWith(fontSize: 16, color: Colors.white),
                                ),
                                subtitle: Text(
                                  '${songIds.length} canciones',
                                  style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                                ),
                                trailing: Icon(
                                  inPlaylist ? Icons.check_circle : Icons.add_circle_outline,
                                  color: inPlaylist ? Colors.green : AppColors.secondary,
                                ),
                                onTap: () async {
                                  if (inPlaylist) {
                                    await audioService.removeSongFromPlaylist(pName, song);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Removida de "$pName"')),
                                      );
                                    }
                                  } else {
                                    await audioService.addSongToPlaylist(pName, song);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('¡Agregada a "$pName"!'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  }
                                  setModalState(() {});
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void _showCreatePlaylistDialog(
    BuildContext context, AudioPlayerService audioService, Song song, StateSetter setModalState) {
  final nameController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Nueva Playlist', style: AppTypography.headlineSm.copyWith(color: AppColors.primary)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nombre de la playlist...',
            hintStyle: const TextStyle(color: AppColors.outlineVariant),
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
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
              final pName = nameController.text.trim();
              if (pName.isNotEmpty) {
                await audioService.createPlaylist(pName);
                await audioService.addSongToPlaylist(pName, song);
                if (context.mounted) {
                  Navigator.pop(context);
                  setModalState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('¡Playlist "$pName" creada y canción agregada!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text('Crear y Agregar'),
          ),
        ],
      );
    },
  );
}
