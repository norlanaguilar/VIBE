import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';
import '../services/link_import_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/glass_container.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = false;
  bool _isAddingPlaylist = false;
  bool _showAllPlaylistTracks = false;
  String? _errorMessage;
  ImportResult? _previewResult;
  ParsedLink? _detectedLink;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final text = _urlController.text.trim();
    final parsed = LinkImportService.parse(text);
    setState(() {
      _detectedLink = parsed;
      if (text.isEmpty) {
        _previewResult = null;
        _errorMessage = null;
        _showAllPlaylistTracks = false;
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
      _urlController.text = data.text!.trim();
      _fetchPreview();
    }
  }

  Future<void> _fetchPreview() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) return;

    _focusNode.unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _previewResult = null;
      _showAllPlaylistTracks = false;
    });

    try {
      final result = await LinkImportService.resolve(text);
      if (mounted) {
        setState(() {
          _previewResult = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('FormatException: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addSongToLibrary(
    AudioPlayerService audioService,
    ImportPreview preview, {
    bool playImmediately = false,
  }) async {
    try {
      final song = await LinkImportService.toSong(preview);
      audioService.addSong(song);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryContainer,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '"${song.title}" agregada a tu biblioteca',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      if (playImmediately) {
        await audioService.playSong(song);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Error al guardar: $e'),
          ),
        );
      }
    }
  }

  Future<void> _addPlaylistToLibrary(
    AudioPlayerService audioService,
    PlaylistPreview playlist, {
    bool playImmediately = false,
  }) async {
    setState(() {
      _isAddingPlaylist = true;
    });

    try {
      final songs = await LinkImportService.playlistToSongs(playlist);
      await audioService.addSongs(songs, targetPlaylist: playlist.title);

      if (mounted) {
        setState(() {
          _isAddingPlaylist = false;
        });
        final typeLabel = playlist.type == LinkType.album ? 'Álbum' : 'Playlist';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryContainer,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$typeLabel "${playlist.title}" agregado (${songs.length} canciones)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      if (playImmediately && songs.isNotEmpty) {
        await audioService.playPlaylist(songs, songs.first);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Error al guardar: $e'),
          ),
        );
      }
    } finally {
      if (mounted && _isAddingPlaylist) {
        setState(() {
          _isAddingPlaylist = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatPlaylistDuration(Duration duration) {
    if (duration == Duration.zero) return '';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '$hours h ${minutes > 0 ? '$minutes min' : ''}'.trim();
    }
    return '$minutes min';
  }

  @override
  void dispose() {
    _urlController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioService = Provider.of<AudioPlayerService>(context);
    final hasText = _urlController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Encabezado: Explorar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.explore, color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Explorar',
                              style: AppTypography.headlineSm.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Importa desde YouTube y Spotify',
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Barra de búsqueda de canciones o enlaces
                    GlassContainer(
                      borderRadius: BorderRadius.circular(16),
                      backgroundColor: AppColors.surfaceContainerLow.withOpacity(0.85),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _buildPlatformBadge(_detectedLink, hasText: hasText),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _urlController,
                                  focusNode: _focusNode,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _fetchPreview(),
                                  decoration: InputDecoration(
                                    hintText: 'Nombre de canción o enlace de YouTube / Spotify...',
                                    hintStyle: TextStyle(
                                      color: AppColors.onSurfaceVariant.withOpacity(0.7),
                                      fontSize: 13,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              if (hasText)
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20, color: AppColors.onSurfaceVariant),
                                  onPressed: () {
                                    _urlController.clear();
                                    setState(() {
                                      _previewResult = null;
                                      _errorMessage = null;
                                      _detectedLink = null;
                                      _showAllPlaylistTracks = false;
                                    });
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.content_paste, size: 20, color: AppColors.primary),
                                tooltip: 'Pegar portapapeles',
                                onPressed: _pasteFromClipboard,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryContainer,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _isLoading ? null : _fetchPreview,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.search, size: 20),
                              label: Text(
                                _isLoading
                                    ? 'Buscando...'
                                    : (_detectedLink != null ? 'Analizar Enlace' : 'Buscar Canción'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.15),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Resultados de enlace o de búsqueda por nombre
                    if (_previewResult != null) ...[
                      const SizedBox(height: 16),
                      if (_previewResult!.isPlaylist)
                        _buildPlaylistPreviewCard(context, audioService, _previewResult!.playlist!)
                      else if (_previewResult!.isSingleTrack)
                        _buildPreviewCard(context, audioService, _previewResult!.singleTrack!)
                      else if (_previewResult!.isSearchResults)
                        _buildSearchResultsSection(context, audioService, _previewResult!.searchResults!),
                    ] else if (!_isLoading && _errorMessage == null) ...[
                      const SizedBox(height: 48),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Column(
                            children: [
                              Icon(
                                Icons.travel_explore,
                                size: 54,
                                color: AppColors.onSurfaceVariant.withOpacity(0.35),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Busca cualquier canción o pega un enlace',
                                style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Escribe el nombre de una canción para buscar su audio oficial en YouTube o pega un enlace de YouTube o Spotify.',
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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

  Widget _buildSearchResultsSection(
    BuildContext context,
    AudioPlayerService audioService,
    List<ImportPreview> results,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.verified_outlined, color: AppColors.secondary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Opciones encontradas (${results.length})',
              style: AppTypography.headlineSm.copyWith(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...results.map((preview) => _buildSearchOptionCard(context, audioService, preview)),
      ],
    );
  }

  Widget _buildSearchOptionCard(
    BuildContext context,
    AudioPlayerService audioService,
    ImportPreview preview,
  ) {
    final isAlreadyAdded = audioService.containsSong(preview.songId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(16),
        backgroundColor: AppColors.surfaceContainerHigh.withOpacity(0.75),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 62,
                height: 62,
                child: preview.coverUrl != null
                    ? Image.network(
                        preview.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _coverPlaceholder(),
                      )
                    : _coverPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.title,
                    style: AppTypography.bodyLg.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview.artist,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${preview.album} • ${_formatDuration(preview.duration)}',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.play_circle_fill, color: AppColors.secondary, size: 32),
              tooltip: 'Reproducir y agregar',
              onPressed: () => _addSongToLibrary(audioService, preview, playImmediately: true),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isAlreadyAdded ? AppColors.surfaceContainerLow : AppColors.primary,
                foregroundColor: isAlreadyAdded ? AppColors.onSurfaceVariant : AppColors.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: Size.zero,
              ),
              onPressed: () => _addSongToLibrary(audioService, preview),
              icon: Icon(isAlreadyAdded ? Icons.check : Icons.add, size: 16),
              label: Text(
                isAlreadyAdded ? 'Agregada' : 'Agregar',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformBadge(ParsedLink? link, {bool hasText = false}) {
    if (link == null) {
      if (hasText) {
        const ytColor = Color(0xFFFF0000);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ytColor.withOpacity(0.18),
            border: Border.all(color: ytColor.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, size: 14, color: ytColor),
              SizedBox(width: 4),
              Text(
                'YouTube',
                style: TextStyle(color: ytColor, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.search, size: 16, color: AppColors.onSurfaceVariant),
      );
    }

    final isSpotify = link.platform == LinkPlatform.spotify;
    final color = isSpotify ? const Color(0xFF1DB954) : const Color(0xFFFF0000);

    String label = isSpotify ? 'Spotify' : 'YouTube';
    IconData icon = isSpotify ? Icons.graphic_eq : Icons.play_arrow;
    if (link.type == LinkType.playlist) {
      label = isSpotify ? 'Spotify Playlist' : 'YouTube Playlist';
      icon = Icons.playlist_play;
    } else if (link.type == LinkType.album) {
      label = 'Spotify Álbum';
      icon = Icons.album;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        border: Border.all(color: color.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context, AudioPlayerService audioService, ImportPreview preview) {
    final isAlreadyAdded = audioService.containsSong(preview.songId);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryContainer.withOpacity(0.3),
            AppColors.surfaceContainerHigh.withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Carátula
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: preview.coverUrl != null
                      ? Image.network(
                          preview.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coverPlaceholder(),
                        )
                      : _coverPlaceholder(),
                ),
              ),
              const SizedBox(width: 14),

              // Información de metadatos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildPlatformBadge(ParsedLink(preview.platform, preview.youtubeId, preview.sourceUrl)),
                        const Spacer(),
                        Text(
                          _formatDuration(preview.duration),
                          style: AppTypography.monoLabel.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preview.title,
                      style: AppTypography.headlineSm.copyWith(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview.artist,
                      style: AppTypography.bodyLg.copyWith(
                        color: AppColors.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview.album,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
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

          const SizedBox(height: 16),

          // Botones de acción (Agregar a biblioteca + Reproducir)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isAlreadyAdded ? Colors.grey.shade800 : AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 4,
                  ),
                  onPressed: () => _addSongToLibrary(audioService, preview),
                  icon: Icon(isAlreadyAdded ? Icons.check : Icons.add_circle_outline, size: 20),
                  label: Text(
                    isAlreadyAdded ? 'En Biblioteca' : 'Agregar a Biblioteca',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _addSongToLibrary(audioService, preview, playImmediately: true),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text(
                    'Reproducir',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistPreviewCard(
    BuildContext context,
    AudioPlayerService audioService,
    PlaylistPreview playlist,
  ) {
    final isAlbum = playlist.type == LinkType.album;
    final isSpotify = playlist.platform == LinkPlatform.spotify;
    final primaryColor = isSpotify ? const Color(0xFF1DB954) : const Color(0xFFFF0000);
    final count = playlist.tracks.length;
    final durationStr = _formatPlaylistDuration(playlist.totalDuration);
    final displayedTracks = _showAllPlaylistTracks ? playlist.tracks : playlist.tracks.take(6).toList();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withOpacity(0.18),
            AppColors.surfaceContainerHigh.withOpacity(0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.15),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: playlist.coverUrl != null
                      ? Image.network(
                          playlist.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _coverPlaceholder(),
                        )
                      : _coverPlaceholder(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPlatformBadge(
                      ParsedLink(
                        playlist.platform,
                        '',
                        playlist.sourceUrl,
                        type: playlist.type,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      playlist.title,
                      style: AppTypography.headlineSm.copyWith(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      playlist.author,
                      style: AppTypography.bodyLg.copyWith(
                        color: AppColors.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      durationStr.isNotEmpty ? '$count canciones • $durationStr' : '$count canciones',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: 12),
          Text(
            'Canciones (${playlist.tracks.length}):',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...displayedTracks.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final t = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$idx',
                      style: AppTypography.monoLabel.copyWith(
                        color: AppColors.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          t.artist,
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant.withOpacity(0.8),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(t.duration),
                    style: AppTypography.monoLabel.copyWith(
                      color: AppColors.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (playlist.tracks.length > 6) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () {
                setState(() {
                  _showAllPlaylistTracks = !_showAllPlaylistTracks;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _showAllPlaylistTracks
                          ? 'Mostrar menos'
                          : 'Ver las ${playlist.tracks.length} canciones',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _showAllPlaylistTracks ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16,
                      color: primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 4,
                  ),
                  onPressed: _isAddingPlaylist
                      ? null
                      : () => _addPlaylistToLibrary(audioService, playlist),
                  icon: _isAddingPlaylist
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.playlist_add, size: 20),
                  label: Text(
                    _isAddingPlaylist
                        ? 'Guardando...'
                        : (isAlbum ? 'Guardar Álbum' : 'Guardar Playlist'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _isAddingPlaylist
                      ? null
                      : () => _addPlaylistToLibrary(audioService, playlist, playImmediately: true),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text(
                    'Reproducir',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: const Center(
        child: Icon(Icons.music_note, color: AppColors.onSurfaceVariant, size: 28),
      ),
    );
  }
}
