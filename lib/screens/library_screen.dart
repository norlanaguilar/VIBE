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

            // Quick Filters (Categories)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 42,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = cat == _selectedCategory;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryContainer.withOpacity(0.4)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.outlineVariant.withOpacity(0.4),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            cat,
                            style: AppTypography.bodySm.copyWith(
                              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Recently Added Bento Grid Section
            if (_searchQuery.isEmpty && recentlyAdded.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Text(
                    'Recently Added',
                    style: AppTypography.headlineSm.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  height: 220,
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      // Featured Large Bento Card
                      Expanded(
                        flex: 5,
                        child: GestureDetector(
                          onTap: () => audioService.playSong(recentlyAdded.first),
                          child: GlassContainer(
                            borderRadius: BorderRadius.circular(16),
                            padding: const EdgeInsets.all(0),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _buildCoverImage(recentlyAdded.first),
                                ),
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          AppColors.background.withOpacity(0.85),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  left: 12,
                                  right: 12,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    song.title,
                                                    style: AppTypography.bodyLg.copyWith(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    song.artist,
                                                    style: AppTypography.monoLabel.copyWith(
                                                      fontSize: 11,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
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
              ),
            ],

            // All Local Tracks Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All Local Tracks',
                      style: AppTypography.headlineSm.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      'SORT BY',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.primary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Local Tracks List
            songs.isEmpty
                ? SliverFillRemaining(
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
                  )
                : SliverList(
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
                              if (val == 'ai') {
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
                                    Icon(Icons.auto_awesome, color: AppColors.primary),
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
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
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
