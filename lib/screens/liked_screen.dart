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

  void _showCreatePlaylistDialog(BuildContext context, AudioPlayerService audioService) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Nueva Playlist',
            style: AppTypography.headlineSm.copyWith(color: AppColors.primary),
          ),
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.onSurfaceVariant)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  await audioService.createPlaylist(name);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Playlist "$name" creada'),
                        backgroundColor: AppColors.primaryContainer,
                      ),
                    );
                    _showPlaylistDetailSheet(context, audioService, name, isLikedPlaylist: false);
                  }
                }
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );
  }

  void _showDeletePlaylistSelector(BuildContext context, AudioPlayerService audioService) {
    final playlists = audioService.playlistNames;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes playlists creadas para eliminar.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.playlist_remove, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 10),
                    const Text(
                      'Eliminar Playlist',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Selecciona la playlist que deseas eliminar:',
                  style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (c, i) {
                      final name = playlists[i];
                      final count = audioService.userPlaylists[name]?.length ?? 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.queue_music, color: AppColors.secondary, size: 20),
                        ),
                        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '$count canciones',
                          style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onTap: () {
                          Navigator.pop(ctx);
                          _confirmDeletePlaylist(context, audioService, name);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDeletePlaylist(
    BuildContext context,
    AudioPlayerService audioService,
    String playlistName,
  ) async {
    final count = audioService.userPlaylists[playlistName]?.length ?? 0;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Eliminar "$playlistName"',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '¿Qué deseas hacer con la playlist "$playlistName" ($count canciones)?',
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'only_playlist'),
            child: const Text('Solo Playlist', style: TextStyle(color: AppColors.secondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('Playlist y Canciones', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (action == 'all') {
      await audioService.deletePlaylistWithSongs(playlistName, deleteSongsFromLibrary: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist "$playlistName" y sus canciones eliminadas')),
        );
      }
      return true;
    } else if (action == 'only_playlist') {
      await audioService.deletePlaylistWithSongs(playlistName, deleteSongsFromLibrary: false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist "$playlistName" eliminada')),
        );
      }
      return true;
    }
    return false;
  }

  void _showPlaylistDetailSheet(
    BuildContext context,
    AudioPlayerService audioService,
    String playlistName, {
    required bool isLikedPlaylist,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Consumer<AudioPlayerService>(
          builder: (ctx, service, _) {
            final List<Song> currentSongs = isLikedPlaylist
                ? service.likedSongs
                : (service.playlists[playlistName] ?? []);

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.82,
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
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isLikedPlaylist ? 'Me Gusta' : playlistName,
                              style: AppTypography.headlineSm.copyWith(color: Colors.white, fontSize: 22),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${currentSongs.length} canciones',
                              style: AppTypography.bodySm.copyWith(color: AppColors.secondary),
                            ),
                          ],
                        ),
                      ),
                      if (!isLikedPlaylist)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          tooltip: 'Eliminar Playlist',
                          onPressed: () async {
                            final deleted = await _confirmDeletePlaylist(context, service, playlistName);
                            if (deleted && sheetCtx.mounted) {
                              Navigator.pop(sheetCtx);
                            }
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Action Buttons: Reproducir + Agregar Canciones
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.play_arrow, size: 20),
                          label: const Text(
                            'REPRODUCIR',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onPressed: currentSongs.isEmpty
                              ? null
                              : () {
                                  service.playPlaylist(currentSongs, currentSongs.first);
                                },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.secondary,
                            side: const BorderSide(color: AppColors.secondary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.playlist_add, size: 20),
                          label: const Text(
                            'AGREGAR CANCIONES',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onPressed: () {
                            _showSelectSongsSheet(
                              context,
                              service,
                              playlistName: playlistName,
                              isLikedPlaylist: isLikedPlaylist,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.outlineVariant),
                  const SizedBox(height: 8),

                  Expanded(
                    child: currentSongs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.queue_music,
                                  size: 48,
                                  color: AppColors.onSurfaceVariant.withOpacity(0.4),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No hay canciones en esta playlist.\nToca "AGREGAR CANCIONES" para seleccionarlas.',
                                  style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: currentSongs.length,
                            itemBuilder: (c, index) {
                              final song = currentSongs[index];
                              final isCurrent = service.currentSong?.id == song.id;

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? AppColors.primaryContainer.withOpacity(0.25)
                                      : AppColors.surfaceContainerHigh.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 46,
                                      height: 46,
                                      child: _buildCover(song),
                                    ),
                                  ),
                                  title: Text(
                                    song.title,
                                    style: TextStyle(
                                      color: isCurrent ? AppColors.primary : Colors.white,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    song.artist,
                                    style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      isLikedPlaylist ? Icons.favorite : Icons.remove_circle_outline,
                                      color: isLikedPlaylist ? AppColors.secondary : Colors.redAccent,
                                    ),
                                    tooltip: isLikedPlaylist ? 'Quitar de Me Gusta' : 'Quitar de la playlist',
                                    onPressed: () async {
                                      if (isLikedPlaylist) {
                                        service.toggleLike(song);
                                      } else {
                                        await service.removeSongFromPlaylist(playlistName, song);
                                      }
                                    },
                                  ),
                                  onTap: () {
                                    service.playPlaylist(currentSongs, song);
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

  void _showSelectSongsSheet(
    BuildContext context,
    AudioPlayerService audioService, {
    required String playlistName,
    required bool isLikedPlaylist,
  }) {
    final Set<String> existingIds = isLikedPlaylist
        ? audioService.likedSongs.map((s) => s.id).toSet()
        : (audioService.userPlaylists[playlistName] ?? []).toSet();
    final Set<String> selectedIds = <String>{};
    String filterQuery = '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final allSongs = audioService.librarySongs.where((s) {
              if (filterQuery.isEmpty) return true;
              final q = filterQuery.toLowerCase();
              return s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q);
            }).toList();

            final availableToSelect = allSongs.where((s) => !existingIds.contains(s.id)).toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.85,
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
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seleccionar Canciones',
                              style: AppTypography.headlineSm.copyWith(color: AppColors.primary, fontSize: 20),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Para: ${isLikedPlaylist ? 'Me Gusta' : playlistName}',
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (availableToSelect.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              if (selectedIds.length == availableToSelect.length) {
                                selectedIds.clear();
                              } else {
                                selectedIds.addAll(availableToSelect.map((s) => s.id));
                              }
                            });
                          },
                          child: Text(
                            selectedIds.length == availableToSelect.length ? 'Deseleccionar' : 'Todas',
                            style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Buscador rápido
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Buscar en tus canciones...',
                      hintStyle: const TextStyle(color: AppColors.outlineVariant),
                      prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                      filled: true,
                      fillColor: AppColors.surfaceContainerHigh,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        filterQuery = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: allSongs.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron canciones en tu biblioteca.',
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            itemCount: allSongs.length,
                            itemBuilder: (c, idx) {
                              final song = allSongs[idx];
                              final alreadyIn = existingIds.contains(song.id);
                              final isChecked = alreadyIn || selectedIds.contains(song.id);

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? AppColors.primaryContainer.withOpacity(0.22)
                                      : AppColors.surfaceContainerHigh.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: _buildCover(song),
                                    ),
                                  ),
                                  title: Text(
                                    song.title,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    alreadyIn ? '${song.artist} • Ya incluida' : song.artist,
                                    style: AppTypography.bodySm.copyWith(
                                      color: alreadyIn ? AppColors.secondary : AppColors.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Checkbox(
                                    value: isChecked,
                                    activeColor: AppColors.primary,
                                    checkColor: Colors.black,
                                    onChanged: alreadyIn
                                        ? null
                                        : (val) {
                                            setModalState(() {
                                              if (val == true) {
                                                selectedIds.add(song.id);
                                              } else {
                                                selectedIds.remove(song.id);
                                              }
                                            });
                                          },
                                  ),
                                  onTap: alreadyIn
                                      ? null
                                      : () {
                                          setModalState(() {
                                            if (selectedIds.contains(song.id)) {
                                              selectedIds.remove(song.id);
                                            } else {
                                              selectedIds.add(song.id);
                                            }
                                          });
                                        },
                                ),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(
                        selectedIds.isEmpty
                            ? 'Selecciona canciones para agregar'
                            : 'Agregar ${selectedIds.length} canciones',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onPressed: selectedIds.isEmpty
                          ? null
                          : () async {
                              if (isLikedPlaylist) {
                                await audioService.addMultipleSongsToLiked(selectedIds.toList());
                              } else {
                                await audioService.addMultipleSongsToPlaylist(
                                  playlistName,
                                  selectedIds.toList(),
                                );
                              }
                              if (modalCtx.mounted) {
                                Navigator.pop(modalCtx);
                              }
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

  Widget _buildPlaylistCard({
    required BuildContext context,
    required AudioPlayerService audioService,
    required String title,
    required List<Song> songs,
    required bool isLikedCard,
  }) {
    final Song? coverSong = songs.isNotEmpty ? songs.first : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        onTap: () => _showPlaylistDetailSheet(
          context,
          audioService,
          title,
          isLikedPlaylist: isLikedCard,
        ),
        child: Row(
          children: [
            // Icono o carátula con estilo de tarjeta Me Gusta
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: isLikedCard
                      ? const [AppColors.primaryContainer, AppColors.secondaryContainer]
                      : [AppColors.secondaryContainer, AppColors.primaryContainer.withOpacity(0.8)],
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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: (!isLikedCard && coverSong != null)
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildCover(coverSong),
                          Container(
                            color: Colors.black.withOpacity(0.25),
                            child: const Center(
                              child: Icon(Icons.queue_music, color: Colors.white, size: 34),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Icon(
                          isLikedCard ? Icons.favorite : Icons.queue_music,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),

            // Texto y botones de acción con el mismo diseño
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.headlineSm.copyWith(
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isLikedCard)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _confirmDeletePlaylist(context, audioService, title),
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${songs.length} canciones',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () => audioService.playPlaylist(songs, songs.first),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('REPRODUCIR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () {
                                if (!audioService.isShuffle) {
                                  audioService.toggleShuffle();
                                }
                                audioService.playPlaylist(songs, songs.first);
                              },
                        icon: const Icon(Icons.shuffle, size: 15),
                        label: const Text('ALEATORIO'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onSurface,
                          side: BorderSide(color: AppColors.outlineVariant.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: AppTypography.labelCaps.copyWith(fontSize: 10),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context);
    final likedSongs = audioService.likedSongs;
    final customPlaylistNames = audioService.playlistNames;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Barra de acciones superior para Crear o Eliminar Playlist (sin el título "Me gusta" ni el corazón)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showCreatePlaylistDialog(context, audioService),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text(
                          'Crear Playlist',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showDeletePlaylistSelector(context, audioService),
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                        label: const Text(
                          'Eliminar Playlist',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.redAccent.withOpacity(0.6)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Card principal: Me Gusta
            SliverToBoxAdapter(
              child: _buildPlaylistCard(
                context: context,
                audioService: audioService,
                title: 'Me Gusta',
                songs: likedSongs,
                isLikedCard: true,
              ),
            ),

            // Cards de todas las demás playlists con el mismo estilo
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final pName = customPlaylistNames[index];
                  final pSongs = audioService.playlists[pName] ?? [];
                  return _buildPlaylistCard(
                    context: context,
                    audioService: audioService,
                    title: pName,
                    songs: pSongs,
                    isLikedCard: false,
                  );
                },
                childCount: customPlaylistNames.length,
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
