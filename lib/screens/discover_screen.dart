import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
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
  bool _isSelectionMode = false;
  final Set<String> _selectedSongIds = {};
  String? _errorMessage;
  ImportResult? _previewResult;
  ParsedLink? _detectedLink;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    final text = _urlController.text.trim();
    final parsed = LinkImportService.parse(text);
    if (parsed?.url != _detectedLink?.url) {
      setState(() {
        _detectedLink = parsed;
        if (text.isEmpty) {
          _previewResult = null;
          _errorMessage = null;
          _showAllPlaylistTracks = false;
        }
      });
    }
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

  Future<void> _addSongToLibrary(AudioPlayerService audioService, ImportPreview preview, {bool playImmediately = false}) async {
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

  Future<void> _confirmDeleteSelected(BuildContext context, AudioPlayerService audioService) async {
    final count = _selectedSongIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: const Text('Eliminar canciones', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '¿Deseas eliminar las $count canciones seleccionadas de tu biblioteca y del almacenamiento?',
          style: const TextStyle(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await audioService.deleteSongs(_selectedSongIds.toList());
      setState(() {
        _selectedSongIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count canciones eliminadas de la biblioteca'),
            backgroundColor: AppColors.primaryContainer,
          ),
        );
      }
    }
  }

  Future<void> _showDeletePlaylistDialog(BuildContext context, AudioPlayerService audioService) async {
    final playlists = audioService.userPlaylists.keys.toList();
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay playlists importadas en la biblioteca.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
                'Selecciona una playlist para eliminarla:',
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (c, i) {
                    final name = playlists[i];
                    final songCount = audioService.userPlaylists[name]?.length ?? 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.queue_music, color: AppColors.secondary, size: 20),
                      ),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text('$songCount canciones', style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
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
      ),
    );
  }

  Future<void> _confirmDeletePlaylist(BuildContext context, AudioPlayerService audioService, String playlistName) async {
    final songCount = audioService.userPlaylists[playlistName]?.length ?? 0;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerHigh,
        title: Text('Eliminar "$playlistName"', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '¿Qué deseas hacer con la playlist "$playlistName" ($songCount canciones)?',
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist "$playlistName" y sus canciones eliminadas')),
        );
      }
    } else if (action == 'only_playlist') {
      await audioService.deletePlaylistWithSongs(playlistName, deleteSongsFromLibrary: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist "$playlistName" eliminada')),
        );
      }
    }
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
    final streamingSongs = audioService.librarySongs.where((s) => s.isImported).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
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
                          child: const Icon(Icons.cloud_download, color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Descubrir',
                              style: AppTypography.headlineSm.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Importa desde YouTube y Spotify sin límites',
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Input Card
                    GlassContainer(
                      borderRadius: BorderRadius.circular(16),
                      backgroundColor: AppColors.surfaceContainerLow.withOpacity(0.85),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _buildPlatformBadge(_detectedLink),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _urlController,
                                  focusNode: _focusNode,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _fetchPreview(),
                                  decoration: InputDecoration(
                                    hintText: 'Pega enlace de YouTube o Spotify...',
                                    hintStyle: TextStyle(color: AppColors.onSurfaceVariant.withOpacity(0.7), fontSize: 13),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              if (_urlController.text.isNotEmpty)
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
                              label: Text(_isLoading ? 'Obteniendo metadatos...' : 'Analizar Enlace'),
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

                    // Preview Card
                    if (_previewResult != null) ...[
                      const SizedBox(height: 16),
                      if (_previewResult!.isPlaylist)
                        _buildPlaylistPreviewCard(context, audioService, _previewResult!.playlist!)
                      else if (_previewResult!.isSingleTrack)
                        _buildPreviewCard(context, audioService, _previewResult!.singleTrack!),
                    ],
                  ],
                ),
              ),
            ),

            // Section Header: Canciones en tu Biblioteca
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _isSelectionMode
                    ? GlassContainer(
                        borderRadius: BorderRadius.circular(12),
                        backgroundColor: AppColors.primaryContainer.withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                (_selectedSongIds.length == streamingSongs.length && streamingSongs.isNotEmpty)
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                color: AppColors.primary,
                                size: 22,
                              ),
                              tooltip: _selectedSongIds.length == streamingSongs.length
                                  ? 'Deseleccionar todas'
                                  : 'Seleccionar todas',
                              onPressed: () {
                                setState(() {
                                  if (_selectedSongIds.length == streamingSongs.length) {
                                    _selectedSongIds.clear();
                                  } else {
                                    _selectedSongIds.addAll(streamingSongs.map((s) => s.id));
                                  }
                                });
                              },
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_selectedSongIds.length} seleccionadas',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Spacer(),
                            if (_selectedSongIds.isNotEmpty)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.delete, size: 16),
                                label: Text(
                                  'Eliminar (${_selectedSongIds.length})',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                onPressed: () => _confirmDeleteSelected(context, audioService),
                              ),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white, size: 20),
                              tooltip: 'Cancelar selección',
                              onPressed: () {
                                setState(() {
                                  _isSelectionMode = false;
                                  _selectedSongIds.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          const Icon(Icons.library_music, color: AppColors.secondary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'En tu Biblioteca',
                            style: AppTypography.headlineSm.copyWith(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${streamingSongs.length}',
                            style: AppTypography.monoLabel.copyWith(color: AppColors.secondary),
                          ),
                          const Spacer(),
                          if (audioService.userPlaylists.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.playlist_remove, color: Colors.redAccent, size: 20),
                              tooltip: 'Eliminar una playlist',
                              onPressed: () => _showDeletePlaylistDialog(context, audioService),
                            ),
                          if (streamingSongs.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.checklist, color: AppColors.primary, size: 20),
                              tooltip: 'Seleccionar canciones',
                              onPressed: () {
                                setState(() {
                                  _isSelectionMode = true;
                                  _selectedSongIds.clear();
                                });
                              },
                            ),
                        ],
                      ),
              ),
            ),

            // Lista de canciones en streaming
            if (streamingSongs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.queue_music, size: 48, color: AppColors.onSurfaceVariant.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'Aún no has agregado canciones en streaming',
                          style: AppTypography.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Copia un link de YouTube o Spotify y presiona "Agregar a la Biblioteca". Se reproducirá directo sin ocupar almacenamiento.',
                          style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant.withOpacity(0.7)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final song = streamingSongs[index];
                    final isCurrent = audioService.currentSong?.id == song.id;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                      child: GlassContainer(
                        borderRadius: BorderRadius.circular(12),
                        backgroundColor: isCurrent
                            ? AppColors.primaryContainer.withOpacity(0.2)
                            : AppColors.surfaceContainerLow.withOpacity(0.6),
                        padding: const EdgeInsets.all(8.0),
                        onTap: _isSelectionMode
                            ? () {
                                setState(() {
                                  if (_selectedSongIds.contains(song.id)) {
                                    _selectedSongIds.remove(song.id);
                                  } else {
                                    _selectedSongIds.add(song.id);
                                  }
                                });
                              }
                            : () => audioService.playPlaylist(streamingSongs, song),
                        child: Row(
                          children: [
                            if (_isSelectionMode) ...[
                              Checkbox(
                                value: _selectedSongIds.contains(song.id),
                                activeColor: AppColors.primary,
                                checkColor: Colors.black,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedSongIds.add(song.id);
                                    } else {
                                      _selectedSongIds.remove(song.id);
                                    }
                                  });
                                },
                              ),
                              const SizedBox(width: 4),
                            ],
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Stack(
                                  children: [
                                    Positioned.fill(child: _buildCoverImage(song)),
                                    if (isCurrent && audioService.isBuffering)
                                      Container(
                                        color: Colors.black.withOpacity(0.5),
                                        child: const Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      )
                                    else if (isCurrent && audioService.isPlaying)
                                      Container(
                                        color: Colors.black.withOpacity(0.4),
                                        child: const Center(
                                          child: Icon(Icons.equalizer, color: AppColors.primary, size: 24),
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
                                      const SizedBox(width: 4),
                                      _buildPlatformPill(song.source),
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
                            if (!_isSelectionMode) ...[
                              if (song.isDownloaded) ...[
                                IconButton(
                                  icon: const Icon(Icons.download_done_rounded, color: AppColors.secondary, size: 20),
                                  tooltip: 'Disponible sin conexión',
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Esta canción ya está descargada en tu dispositivo.'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                              ] else if (audioService.isSongDownloading(song.id)) ...[
                                const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                  ),
                                ),
                              ] else ...[
                                IconButton(
                                  icon: const Icon(Icons.arrow_circle_down_rounded, color: AppColors.onSurfaceVariant, size: 22),
                                  tooltip: 'Descargar para reproducir sin internet',
                                  onPressed: () async {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Descargando "${song.title}" para escuchar sin internet...'),
                                        backgroundColor: AppColors.primaryContainer,
                                      ),
                                    );
                                    try {
                                      await audioService.downloadSongForOffline(song);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('¡"${song.title}" descargada para escuchar offline!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Error al descargar: $e'),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: AppColors.onSurfaceVariant, size: 20),
                                color: AppColors.surfaceContainerHigh,
                                onSelected: (val) async {
                                  if (val == 'download') {
                                    await audioService.downloadSongForOffline(song);
                                  } else if (val == 'delete') {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: AppColors.surfaceContainerHigh,
                                        title: const Text('Quitar de biblioteca'),
                                        content: Text('¿Deseas quitar "${song.title}" de tu biblioteca?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Quitar', style: TextStyle(color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await audioService.removeStreamingSong(song);
                                    }
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  if (!song.isDownloaded)
                                    const PopupMenuItem(
                                      value: 'download',
                                      child: Row(
                                        children: [
                                          Icon(Icons.download, color: AppColors.primary, size: 18),
                                          SizedBox(width: 8),
                                          Text('Descargar para escuchar offline'),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                        SizedBox(width: 8),
                                        Text('Quitar de biblioteca', style: TextStyle(color: Colors.redAccent)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: streamingSongs.length,
                ),
              ),

            // Espacio final para que el miniplayer no tape la última canción
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformBadge(ParsedLink? link) {
    if (link == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.link, size: 16, color: AppColors.onSurfaceVariant),
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

  Widget _buildPlatformPill(String source) {
    final isSpotify = source == 'spotify';
    final color = isSpotify ? const Color(0xFF1DB954) : const Color(0xFFFF4E45);
    final label = isSpotify ? 'SPOTIFY' : 'YOUTUBE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
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
        child: Icon(Icons.music_note, color: AppColors.onSurfaceVariant, size: 36),
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
        errorBuilder: (_, __, ___) => _coverPlaceholder(),
      );
    }
    return _coverPlaceholder();
  }
}
