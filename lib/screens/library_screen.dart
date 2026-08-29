import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_container.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedCategory = 'All Files';
  final List<String> _categories = ['All Files', 'Playlists', 'Artists', 'Albums'];
  String _searchQuery = '';
  bool _isSearching = false;

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

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context);
    final songs = audioService.librarySongs.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q);
    }).toList();

    final recentlyAdded = audioService.librarySongs.take(5).toList();

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
                      'Library',
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.primary,
                        fontSize: 26,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.sync, color: AppColors.secondary),
                          onPressed: () => audioService.scanLocalLibrary(),
                          tooltip: 'Escanear música local',
                        ),
                        IconButton(
                          icon: Icon(
                            _isSearching ? Icons.close : Icons.search,
                            color: AppColors.primary,
                          ),
                          onPressed: () {
                            setState(() {
                              _isSearching = !_isSearching;
                              if (!_isSearching) _searchQuery = '';
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Search Bar (if active)
            if (_isSearching)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search songs or artists...',
                      hintStyle: TextStyle(color: AppColors.outlineVariant),
                      filled: true,
                      fillColor: AppColors.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  ),
                ),
              ),

            // Quick Filters (Categories Chips)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = _selectedCategory == cat;

                    return Container(
                      margin: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(
                          cat,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: AppColors.primaryContainer,
                        backgroundColor: AppColors.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() {
                              _selectedCategory = cat;
                            });
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),

            // Bento Grid for Recently Added Tracks (Visible in All Files)
            if (_selectedCategory == 'All Files' && recentlyAdded.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recently Added',
                        style: AppTypography.headlineSm.copyWith(
                          fontSize: 18,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),

                      SizedBox(
                        height: 180,
                        child: Row(
                          children: [
                            // Main Large Bento Feature Card
                            Expanded(
                              flex: 5,
                              child: GestureDetector(
                                onTap: () => audioService.playSong(recentlyAdded.first),
                                child: GlassContainer(
                                  borderRadius: BorderRadius.circular(16),
                                  padding: const EdgeInsets.all(12),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Opacity(
                                            opacity: 0.4,
                                            child: _buildCoverImage(recentlyAdded.first),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 8,
                                        left: 8,
                                        right: 8,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    recentlyAdded.first.title,
                                                    style: AppTypography.headlineSm.copyWith(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    recentlyAdded.first.artist,
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
                                            CircleAvatar(
                                              backgroundColor: AppColors.primary,
                                              radius: 18,
                                              child: const Icon(
                                                Icons.play_arrow,
                                                color: AppColors.onPrimary,
                                                size: 22,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Smaller Bento Cards Column
                            if (recentlyAdded.length > 1)
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: List.generate(
                                    (recentlyAdded.length - 1).clamp(0, 2),
                                    (idx) {
                                      final song = recentlyAdded[idx + 1];
                                      return Expanded(
                                        child: GestureDetector(
                                          onTap: () => audioService.playSong(song),
                                          child: Container(
                                            margin: EdgeInsets.only(bottom: idx == 0 ? 8.0 : 0.0),
                                            child: GlassContainer(
                                              borderRadius: BorderRadius.circular(12),
                                              padding: const EdgeInsets.all(8),
                                              child: Row(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: SizedBox(
                                                      width: 44,
                                                      height: 44,
                                                      child: _buildCoverImage(song),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      song.title,
                                                      style: AppTypography.bodySm.copyWith(
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Header Title for Selected Category
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  _selectedCategory == 'All Files'
                      ? 'All Local Tracks'
                      : _selectedCategory,
                  style: AppTypography.headlineSm.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),

            // Content Switcher for Categories
            ..._buildCategoryView(audioService, songs),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  /// Visualizador Dinámico según Categoría Seleccionada
  List<Widget> _buildCategoryView(AudioPlayerService audioService, List<Song> songs) {
    if (_selectedCategory == 'Playlists') {
      final playlists = audioService.playlists;
      return [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final playlistName = playlists.keys.elementAt(index);
              final playlistSongs = playlists[playlistName] ?? [];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(16),
                  padding: const EdgeInsets.all(16),
                  onTap: () {
                    if (playlistSongs.isNotEmpty) {
                      audioService.playSong(playlistSongs.first);
                    }
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.playlist_play, color: AppColors.primary, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              playlistName,
                              style: AppTypography.headlineSm.copyWith(fontSize: 16, color: Colors.white),
                            ),
                            Text(
                              '${playlistSongs.length} canciones',
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.play_circle_fill, color: AppColors.primary, size: 32),
                    ],
                  ),
                ),
              );
            },
            childCount: playlists.length,
          ),
        ),
      ];
    }

    if (_selectedCategory == 'Artists') {
      final artistsMap = audioService.songsByArtist;
      if (artistsMap.isEmpty) {
        return [_buildEmptySliver('No hay artistas encontrados.')];
      }
      return [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final artistName = artistsMap.keys.elementAt(index);
              final artistSongs = artistsMap[artistName] ?? [];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(16),
                  padding: const EdgeInsets.all(16),
                  onTap: () {
                    if (artistSongs.isNotEmpty) {
                      audioService.playSong(artistSongs.first);
                    }
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.secondaryContainer,
                        child: const Icon(Icons.person, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              artistName,
                              style: AppTypography.headlineSm.copyWith(fontSize: 16, color: Colors.white),
                            ),
                            Text(
                              '${artistSongs.length} canciones grabadas',
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.primary),
                    ],
                  ),
                ),
              );
            },
            childCount: artistsMap.length,
          ),
        ),
      ];
    }

    if (_selectedCategory == 'Albums') {
      final albumsMap = audioService.songsByAlbum;
      if (albumsMap.isEmpty) {
        return [_buildEmptySliver('No hay álbumes registrados.')];
      }
      return [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final albumName = albumsMap.keys.elementAt(index);
              final albumSongs = albumsMap[albumName] ?? [];
              final firstSong = albumSongs.first;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(16),
                  padding: const EdgeInsets.all(12),
                  onTap: () {
                    if (albumSongs.isNotEmpty) {
                      audioService.playSong(albumSongs.first);
                    }
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: _buildCoverImage(firstSong),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              albumName,
                              style: AppTypography.headlineSm.copyWith(fontSize: 15, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${firstSong.artist} • ${albumSongs.length} pistas',
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.album_rounded, color: AppColors.secondary),
                    ],
                  ),
                ),
              );
            },
            childCount: albumsMap.length,
          ),
        ),
      ];
    }

    // Default 'All Files' View
    if (songs.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.library_music_outlined, size: 64, color: AppColors.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'No tienes canciones guardadas',
                    style: AppTypography.headlineSm.copyWith(color: AppColors.onSurface),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Guarda o copia tus archivos de música (.mp3, .m4a, .wav) en la carpeta VibeLocal de la app Archivos en iOS o almacenamiento local.',
                    style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => audioService.scanLocalLibrary(),
                    icon: const Icon(Icons.sync),
                    label: const Text('Escanear música local'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = songs[index];
            final isCurrent = audioService.currentSong?.id == song.id;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
              child: GlassContainer(
                borderRadius: BorderRadius.circular(12),
                backgroundColor: isCurrent
                    ? AppColors.primaryContainer.withOpacity(0.2)
                    : AppColors.surfaceContainerLow.withOpacity(0.6),
                padding: const EdgeInsets.all(8.0),
                onTap: () => audioService.playSong(song),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Stack(
                          children: [
                            Positioned.fill(child: _buildCoverImage(song)),
                            if (isCurrent && audioService.isPlaying)
                              Container(
                                color: Colors.black.withOpacity(0.4),
                                child: const Center(
                                  child: Icon(
                                    Icons.equalizer,
                                    color: AppColors.primary,
                                    size: 24,
                                  ),
                                ),
                              ),
                          ],
                        ),
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
                            '${song.artist} • ${_formatDuration(song.duration)}',
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
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppColors.onSurfaceVariant,
                      ),
                      color: AppColors.surfaceContainerHigh,
                      onSelected: (val) {
                        if (val == 'edit') {
                          _showEditMetadataDialog(context, audioService, song);
                        } else if (val == 'ai') {
                          audioService.runAiIdentificationForSong(song);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Identificando metadata con IA...'),
                              backgroundColor: AppColors.primaryContainer,
                            ),
                          );
                        } else if (val == 'like') {
                          audioService.toggleLike(song);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: const Row(
                            children: [
                              Icon(Icons.edit_note, color: AppColors.primary),
                              SizedBox(width: 8),
                              Text('Editar Título y Artista'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'like',
                          child: Row(
                            children: [
                              Icon(
                                song.isLiked ? Icons.favorite : Icons.favorite_border,
                                color: song.isLiked ? AppColors.secondary : Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(song.isLiked ? 'Quitar Me gusta' : 'Agregar Me gusta'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'ai',
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome, color: AppColors.secondary),
                              SizedBox(width: 8),
                              Text('Identificar con IA'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: songs.length,
        ),
      ),
    ];
  }

  Widget _buildEmptySliver(String message) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Text(
            message,
            style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ),
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
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      color: AppColors.surfaceVariant,
      child: const Center(
        child: Icon(Icons.music_note, color: AppColors.primary),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
