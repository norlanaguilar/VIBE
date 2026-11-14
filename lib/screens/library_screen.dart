import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/glass_container.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedCategory = 'Canciones';
  final List<String> _categories = ['Canciones', 'Artistas'];
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
                      'Biblioteca',
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.primary,
                        fontSize: 26,
                      ),
                    ),
                    Row(
                      children: [
                        if (Platform.isAndroid)
                          IconButton(
                            icon: const Icon(Icons.file_open_outlined, color: AppColors.tertiary),
                            onPressed: () async {
                              final imported = await audioService.importCustomMusicFile();
                              if (imported.isNotEmpty && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('¡${imported.length} canciones importadas a la biblioteca!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                            tooltip: 'Importar archivos de música',
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
                      hintText: 'Buscar canciones o artistas...',
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

            // Bento Grid for Recently Added Tracks (Visible in Canciones)
            if (_selectedCategory == 'Canciones' && recentlyAdded.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agregadas Recientemente',
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
                  _selectedCategory == 'Canciones'
                      ? 'Todas las Canciones'
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
    if (_selectedCategory == 'Artistas') {
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
                      audioService.playPlaylist(artistSongs, artistSongs.first);
                    }
                  },
                  child: Row(
                    children: [
                      _ArtistAvatar(
                        artistName: artistName,
                        fallbackSong: artistSongs.isNotEmpty ? artistSongs.first : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              artistName,
                              style: AppTypography.headlineSm.copyWith(fontSize: 16, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${artistSongs.length} ${artistSongs.length == 1 ? 'canción' : 'canciones'}',
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.play_circle_fill, color: AppColors.secondary, size: 32),
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

    // Vista por defecto: 'Canciones'
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
                    'Guarda o copia tus archivos de música (.mp3, .m4a, .wav) en la carpeta de Vibe App o agrégala desde Explorar.',
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
                onTap: () => audioService.playPlaylist(songs, song),
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  song.title,
                                  style: AppTypography.bodyLg.copyWith(
                                    fontSize: 15,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                    color: isCurrent ? AppColors.primary : AppColors.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (song.isStreaming) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    song.source == 'spotify' ? 'SPOTIFY' : 'YOUTUBE',
                                    style: const TextStyle(
                                      color: AppColors.secondary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
                        if (val == 'playlist') {
                          showAddToPlaylistModal(context, audioService, song);
                        } else if (val == 'edit') {
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
                        } else if (val == 'download') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Descargando "${song.title}" para escuchar sin internet...'),
                              backgroundColor: AppColors.primaryContainer,
                            ),
                          );
                          audioService.downloadSongForOffline(song);
                        } else if (val == 'remove_stream') {
                          audioService.removeStreamingSong(song);
                        }
                      },
                      itemBuilder: (context) => [
                        if (!song.isDownloaded && (song.youtubeId != null || song.isStreaming))
                          const PopupMenuItem(
                            value: 'download',
                            child: Row(
                              children: [
                                Icon(Icons.download, color: AppColors.primary),
                                SizedBox(width: 8),
                                Text('Descargar para escuchar sin conexión'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'playlist',
                          child: Row(
                            children: [
                              Icon(Icons.playlist_add, color: AppColors.primary),
                              SizedBox(width: 8),
                              Text('Agregar a Playlist'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_note, color: AppColors.secondary),
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
                              Icon(Icons.manage_search, color: AppColors.secondary),
                              SizedBox(width: 8),
                              Text('Identificar'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'remove_stream',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('Quitar de biblioteca', style: TextStyle(color: Colors.redAccent)),
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

class _ArtistAvatar extends StatefulWidget {
  final String artistName;
  final Song? fallbackSong;

  const _ArtistAvatar({
    required this.artistName,
    this.fallbackSong,
  });

  @override
  State<_ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<_ArtistAvatar> {
  static final Map<String, String> _memoryPhotoCache = {};
  String? _localPhotoPath;
  String? _remotePhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadArtistPhoto();
  }

  @override
  void didUpdateWidget(covariant _ArtistAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistName != widget.artistName) {
      _localPhotoPath = null;
      _remotePhotoUrl = null;
      _loadArtistPhoto();
    }
  }

  String _extractPrimaryArtist(String raw) {
    final cleaned = raw
        .split(RegExp(r'\s*(?:&|,|feat\.?|ft\.?|x|\/|;)\s*', caseSensitive: false))
        .first
        .trim();
    return cleaned.isNotEmpty ? cleaned : raw.trim();
  }

  Future<void> _loadArtistPhoto() async {
    final primary = _extractPrimaryArtist(widget.artistName);
    if (primary.isEmpty ||
        primary.toLowerCase() == 'artista desconocido' ||
        primary.toLowerCase() == 'unknown artist') {
      return;
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory(path.join(docsDir.path, 'artist_photos'));
      if (!photosDir.existsSync()) {
        await photosDir.create(recursive: true);
      }

      final safeKey = primary.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      final cachedFile = File(path.join(photosDir.path, 'artist_$safeKey.jpg'));
      if (cachedFile.existsSync() && cachedFile.lengthSync() > 500) {
        if (mounted) {
          setState(() {
            _localPhotoPath = cachedFile.path;
          });
        }
        return;
      }

      if (_memoryPhotoCache.containsKey(primary)) {
        if (mounted) {
          setState(() {
            _remotePhotoUrl = _memoryPhotoCache[primary];
          });
        }
        return;
      }

      final uri = Uri.parse(
        'https://api.deezer.com/search/artist?q=${Uri.encodeComponent(primary)}&limit=1',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'] as List?;
        if (list != null && list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final picUrl = (first['picture_medium'] ?? first['picture_big'] ?? first['picture'])
              ?.toString();
          if (picUrl != null && picUrl.startsWith('http')) {
            _memoryPhotoCache[primary] = picUrl;
            if (mounted) {
              setState(() {
                _remotePhotoUrl = picUrl;
              });
            }
            // Guardar en caché local para uso sin conexión
            final imgResp = await http.get(Uri.parse(picUrl)).timeout(const Duration(seconds: 8));
            if (imgResp.statusCode == 200 && imgResp.bodyBytes.length > 500) {
              await cachedFile.writeAsBytes(imgResp.bodyBytes, flush: true);
              if (mounted) {
                setState(() {
                  _localPhotoPath = cachedFile.path;
                });
              }
            }
          }
        }
      }
    } catch (_) {
      // Usa la carátula de respaldo si no hay conexión
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.secondaryContainer, AppColors.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.14),
          width: 1.2,
        ),
      ),
      child: ClipOval(
        child: _buildImageContent(),
      ),
    );
  }

  Widget _buildImageContent() {
    if (_localPhotoPath != null && File(_localPhotoPath!).existsSync()) {
      return Image.file(
        File(_localPhotoPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildSongCoverFallback(),
      );
    }
    if (_remotePhotoUrl != null && _remotePhotoUrl!.startsWith('http')) {
      return Image.network(
        _remotePhotoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildSongCoverFallback(),
      );
    }
    return _buildSongCoverFallback();
  }

  Widget _buildSongCoverFallback() {
    final song = widget.fallbackSong;
    if (song != null) {
      if (song.localCoverPath != null && File(song.localCoverPath!).existsSync()) {
        return Image.file(
          File(song.localCoverPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 26),
        );
      }
      if (song.coverUrl != null && song.coverUrl!.startsWith('http')) {
        return Image.network(
          song.coverUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 26),
        );
      }
    }
    return const Center(
      child: Icon(Icons.person, color: Colors.white, size: 26),
    );
  }
}
