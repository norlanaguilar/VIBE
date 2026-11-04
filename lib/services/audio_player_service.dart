import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_selector/file_selector.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song_model.dart';
import 'ai_tagger_service.dart';
import 'audio_duration_helper.dart';
import 'home_widget_bridge.dart';
import 'spectrum_service.dart';
import 'vibe_audio_handler.dart';
import 'youtube_stream_resolver.dart';
import 'link_import_service.dart';

class AudioPlayerService extends ChangeNotifier {
  final VibeAudioHandler _handler;
  AudioPlayer get _player => _handler.player;

  /// Espectro real de frecuencias de la canción en reproducción
  late final SpectrumService spectrum = SpectrumService(_handler.player);

  /// true mientras se obtiene el audio de una canción en streaming
  bool _isBuffering = false;
  bool get isBuffering => _isBuffering;

  /// Último error de reproducción para mostrarlo en la UI
  final ValueNotifier<String?> playbackError = ValueNotifier(null);

  /// Evita que una canción que tardó en cargar reemplace a otra elegida después
  int _playToken = 0;

  List<Song> _librarySongs = [];
  List<Song> get librarySongs => _librarySongs;

  Song? _currentSong;
  Song? get currentSong => _currentSong;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  bool _isShuffle = false;
  bool get isShuffle => _isShuffle;

  LoopMode _loopMode = LoopMode.all;
  LoopMode get loopMode => _loopMode;

  bool _enableAiTagging = true;
  bool get enableAiTagging => _enableAiTagging;

  bool _gaplessPlayback = true;
  bool get gaplessPlayback => _gaplessPlayback;

  void setGaplessPlayback(bool val) {
    _gaplessPlayback = val;
    notifyListeners();
  }

  /// Grupos de canciones por Artista
  Map<String, List<Song>> get songsByArtist {
    final Map<String, List<Song>> map = {};
    for (final song in _librarySongs) {
      final artistName = song.artist.isNotEmpty ? song.artist : 'Artista Desconocido';
      map.putIfAbsent(artistName, () => []).add(song);
    }
    return map;
  }

  /// Grupos de canciones por Álbum
  Map<String, List<Song>> get songsByAlbum {
    final Map<String, List<Song>> map = {};
    for (final song in _librarySongs) {
      final albumName = song.album.isNotEmpty ? song.album : 'Álbum Desconocido';
      map.putIfAbsent(albumName, () => []).add(song);
    }
    return map;
  }

  Map<String, List<String>> _userPlaylists = {};
  Map<String, List<String>> get userPlaylists => _userPlaylists;
  List<String> get playlistNames => _userPlaylists.keys.toList();

  /// Playlists combinadas (Automáticas + Personalizadas del usuario)
  Map<String, List<Song>> get playlists {
    final Map<String, List<Song>> result = {
      'Mis Favoritas': likedSongs,
      'Agregadas Recientemente': _librarySongs.take(10).toList(),
      'Música Local': _librarySongs,
    };

    _userPlaylists.forEach((name, songIds) {
      final songsInPlaylist = _librarySongs.where((s) => songIds.contains(s.id)).toList();
      result[name] = songsInPlaylist;
    });

    return result;
  }

  Future<void> createPlaylist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && !_userPlaylists.containsKey(trimmed)) {
      _userPlaylists[trimmed] = [];
      await _savePlaylistsCache();
      notifyListeners();
    }
  }

  Future<void> addSongToPlaylist(String playlistName, Song song) async {
    if (_userPlaylists.containsKey(playlistName)) {
      if (!_userPlaylists[playlistName]!.contains(song.id)) {
        _userPlaylists[playlistName]!.add(song.id);
        await _savePlaylistsCache();
        notifyListeners();
      }
    }
  }

  Future<void> removeSongFromPlaylist(String playlistName, Song song) async {
    if (_userPlaylists.containsKey(playlistName)) {
      _userPlaylists[playlistName]!.remove(song.id);
      await _savePlaylistsCache();
      notifyListeners();
    }
  }

  Future<void> deletePlaylist(String playlistName) async {
    if (_userPlaylists.containsKey(playlistName)) {
      _userPlaylists.remove(playlistName);
      await _savePlaylistsCache();
      notifyListeners();
    }
  }

  Future<Map<String, List<String>>> _loadPlaylistsCache() async {
    final Map<String, List<String>> cache = {};
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheFile = File(path.join(docDir.path, 'user_playlists.json'));
      if (await cacheFile.exists()) {
        final content = await cacheFile.readAsString();
        final Map<String, dynamic> rawMap = json.decode(content);
        rawMap.forEach((key, val) {
          if (val is List) {
            cache[key] = val.map((e) => e.toString()).toList();
          }
        });
      }
    } catch (e) {
      print('Error loading user playlists: $e');
    }
    return cache;
  }

  Future<void> _savePlaylistsCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheFile = File(path.join(docDir.path, 'user_playlists.json'));
      await cacheFile.writeAsString(json.encode(_userPlaylists));
    } catch (e) {
      print('Error saving user playlists: $e');
    }
  }

  // Equalizer Presets & Bands: 60Hz, 230Hz, 910Hz, 4kHz, 14kHz (range 0.0 - 1.0)
  String _activePreset = 'Normal';
  String get activePreset => _activePreset;

  final Map<String, List<double>> _presets = {
    'Normal': [0.50, 0.50, 0.50, 0.50, 0.50],
    'Bajos Potentes': [0.90, 0.80, 0.55, 0.50, 0.45],
    'Pop / Vocal': [0.45, 0.60, 0.85, 0.70, 0.55],
    'Rock / Electrónica': [0.85, 0.65, 0.45, 0.75, 0.90],
    'Acústico': [0.55, 0.55, 0.65, 0.60, 0.50],
  };

  List<String> get availablePresets => _presets.keys.toList();

  List<double> _equalizerGains = [0.50, 0.50, 0.50, 0.50, 0.50];
  List<double> get equalizerGains => _equalizerGains;

  AudioPlayerService(this._handler) {
    // Botones Anterior / Siguiente de la pantalla bloqueada, Centro de Control,
    // notificación, auriculares y widget de Android
    _handler.onSkipToNext = () async => skipNext();
    _handler.onSkipToPrevious = () async => skipPrevious();
    _handler.onPlaybackCompleted = () async => skipNext(fromCompletion: true);

    // Botones del widget de iOS (llegan por canal nativo)
    HomeWidgetBridge.listen((command) async {
      switch (command) {
        case 'next':
          skipNext();
          break;
        case 'previous':
          skipPrevious();
          break;
        case 'toggle':
          await togglePlayPause();
          break;
      }
    });

    scanLocalLibrary();
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      HomeWidgetBridge.update(_currentSong, isPlaying: _isPlaying);
      notifyListeners();
    });

    _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _player.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        // Protección contra el bug de decodificación SBR / AAC-HE en ExoPlayer y AVPlayer
        // donde la duración reportada es aproximadamente el doble (1.8x - 2.2x) de la real:
        if (_currentSong != null && _currentSong!.duration > Duration.zero) {
          final realSec = _currentSong!.duration.inSeconds;
          final reportedSec = dur.inSeconds;
          if (reportedSec >= (realSec * 1.8).round() && reportedSec <= (realSec * 2.2).round()) {
            _duration = _currentSong!.duration;
            notifyListeners();
            return;
          }
        }
        _duration = dur;
        if (_currentSong != null && _currentSong!.duration == Duration.zero) {
          _currentSong = _currentSong!.copyWith(duration: dur);
          _saveMetadataCache();
        }
        notifyListeners();
      }
    });

    // El avance automático de canciones al completarse lo coordina VibeAudioHandler
    // para mantener la sesión de audio activa y el widget de iOS intacto.
  }

  /// Escanear directorio de documentos e integrar caché guardado en disco
  Future<void> scanLocalLibrary() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      final readmeFile = File(path.join(appDir.path, 'README.md'));
      if (!await readmeFile.exists()) {
        await readmeFile.writeAsString(
          '# Carpeta de Música VibeLocal\n\nColoca tus canciones (.mp3, .m4a, .wav, .flac) aquí desde la app Archivos de iOS o tu explorador.',
        );
      }

      // Solicitar permisos de almacenamiento/audio en Android
      if (Platform.isAndroid) {
        try {
          await Permission.audio.request();
          await Permission.storage.request();
        } catch (_) {}
      }

      // Cargar caché guardado en disco para preservar cambios manuales y carátulas
      final metadataCache = await _loadMetadataCache();
      _userPlaylists = await _loadPlaylistsCache();

      List<Song> loadedSongs = [];
      Set<String> scannedPaths = {};

      final List<Directory> dirsToScan = [
        appDir,
      ];

      if (Platform.isAndroid) {
        final List<String> publicRoots = [
          '/storage/emulated/0/Music'
        ];

        for (final root in publicRoots) {
          final rootDir = Directory(root);
          if (await rootDir.exists()) {
            // Crear carpeta 'Vibe' adentro para que el usuario sepa dónde meter su música
            final vibeFolder = Directory(path.join(root, 'Vibe'));
            try {
              if (!await vibeFolder.exists()) {
                await vibeFolder.create();
              }
              // Solo añadimos la carpeta Vibe para escanear, evitando duplicados
              dirsToScan.add(vibeFolder);
            } catch (_) {}
          }
        }
      }

      for (final dir in dirsToScan) {
        if (await dir.exists()) {
          try {
            // recursive: false previene excepciones fatales en Android al tocar carpetas bloqueadas por el sistema
            final List<FileSystemEntity> entities = dir.listSync(recursive: false, followLinks: false);
            for (final entity in entities) {
              if (entity is File && !scannedPaths.contains(entity.path)) {
                scannedPaths.add(entity.path);

                // Evitar archivos vacíos o de 0 bytes
                try {
                  if (entity.lengthSync() < 1024) continue;
                } catch (_) {
                  continue;
                }

                // Evitar duplicar archivos que pertenecen a canciones en streaming guardadas
                final isAssociatedWithStreaming = metadataCache.values.any((s) =>
                    (s.isStreaming || s.youtubeId != null) &&
                    s.localAudioPath != null &&
                    path.normalize(s.localAudioPath!) == path.normalize(entity.path));
                if (isAssociatedWithStreaming) continue;

                final ext = path.extension(entity.path).toLowerCase();
                if (ext == '.m4a' || ext == '.mp3' || ext == '.webm' || ext == '.wav' || ext == '.aac' || ext == '.flac' || ext == '.ogg') {
                  final fileName = path.basenameWithoutExtension(entity.path);

                  Song song;
                  if (metadataCache.containsKey(entity.path)) {
                    song = metadataCache[entity.path]!;
                  } else {
                    song = Song(
                      id: entity.path,
                      title: fileName,
                      artist: 'Artista Local',
                      album: 'Biblioteca Local',
                      localAudioPath: entity.path,
                      isDownloaded: true,
                    );
                  }

                  loadedSongs.add(song);
                }
              }
            }
          } catch (_) {}
        }
      }

      // Eliminar canciones locales fantasmas cuyo archivo en disco ya no exista
      loadedSongs.removeWhere((s) =>
          !s.isStreaming && s.youtubeId == null && s.localAudioPath != null && !File(s.localAudioPath!).existsSync());

      // Canciones en streaming o importadas (YouTube / Spotify): no tienen archivo o se descargaron,
      // así que aseguramos que NUNCA se pierdan ni se eliminen
      for (final cached in metadataCache.values) {
        if (cached.youtubeId != null || cached.isStreaming) {
          Song s = cached;
          if (s.localAudioPath != null) {
            final f = File(s.localAudioPath!);
            if (!f.existsSync() || f.lengthSync() < 50000) {
              s = s.copyWith(localAudioPath: null, isDownloaded: false);
            }
          }
          if (!loadedSongs.any((item) => item.id == s.id)) {
            loadedSongs.add(s);
          }
        }
      }
      for (final existing in _librarySongs) {
        if ((existing.youtubeId != null || existing.isStreaming) && !loadedSongs.any((s) => s.id == existing.id)) {
          loadedSongs.add(existing);
        }
      }
      loadedSongs.sort((a, b) => b.addedAt.compareTo(a.addedAt));

      _librarySongs = loadedSongs;
      if (_librarySongs.isNotEmpty && _currentSong == null) {
        _currentSong = _librarySongs.first;
      }
      notifyListeners();

      // Probar duración exacta en segundo plano y corregir duraciones duplicadas por bug SBR
      for (int i = 0; i < _librarySongs.length; i++) {
        final localPath = _librarySongs[i].localAudioPath;
        if (localPath != null) {
          final file = File(localPath);
          if (file.existsSync()) {
            Duration? exactDur;
            if (localPath.toLowerCase().endsWith('.m4a') || localPath.toLowerCase().endsWith('.mp4')) {
              exactDur = await AudioDurationHelper.readM4aDuration(file);
            }

            if (exactDur != null && exactDur > Duration.zero) {
              final currentDur = _librarySongs[i].duration;
              if (currentDur == Duration.zero ||
                  (currentDur.inSeconds >= (exactDur.inSeconds * 1.8).round() &&
                   currentDur.inSeconds <= (exactDur.inSeconds * 2.2).round())) {
                _librarySongs[i] = _librarySongs[i].copyWith(duration: exactDur);
                if (_currentSong?.id == _librarySongs[i].id) {
                  _currentSong = _librarySongs[i];
                  _duration = exactDur;
                }
                notifyListeners();
              }
            } else if (_librarySongs[i].duration == Duration.zero) {
              try {
                final probe = AudioPlayer();
                final dur = await probe.setFilePath(localPath);
                if (dur != null) {
                  _librarySongs[i] = _librarySongs[i].copyWith(duration: dur);
                  if (_currentSong?.id == _librarySongs[i].id) {
                    _currentSong = _librarySongs[i];
                    _duration = dur;
                  }
                  notifyListeners();
                }
                await probe.dispose();
              } catch (_) {}
            }
          }
        }
      }

      // Guardar caché persistente
      await _saveMetadataCache();
    } catch (e) {
      print('Error loading local music: $e');
    }
  }

  /// Cargar caché persistente en disco (metadata_store.json + copia de seguridad)
  Future<Map<String, Song>> _loadMetadataCache() async {
    final Map<String, Song> cache = {};
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheFile = File(path.join(docDir.path, 'metadata_store.json'));
      final backupFile = File(path.join(docDir.path, 'streaming_backup.json'));

      if (await cacheFile.exists()) {
        final content = await cacheFile.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        for (final item in jsonList) {
          final song = Song.fromJson(item as Map<String, dynamic>);
          cache[song.id] = song;
        }
      }

      // Cargar también la copia de seguridad para garantizar que ninguna canción streaming se pierda
      if (await backupFile.exists()) {
        final content = await backupFile.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        for (final item in jsonList) {
          final song = Song.fromJson(item as Map<String, dynamic>);
          if (!cache.containsKey(song.id)) {
            cache[song.id] = song;
          }
        }
      }
    } catch (e) {
      print('Error loading metadata cache: $e');
    }
    return cache;
  }

  /// Guardar de forma permanente la biblioteca en disco (metadata_store.json y streaming_backup.json)
  Future<void> _saveMetadataCache() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final cacheFile = File(path.join(docDir.path, 'metadata_store.json'));
      final backupFile = File(path.join(docDir.path, 'streaming_backup.json'));

      final jsonList = _librarySongs.map((s) => s.toJson()).toList();
      final content = json.encode(jsonList);
      await cacheFile.writeAsString(content);

      // Copia de seguridad exclusiva de canciones streaming e importadas
      final streamingOnly = _librarySongs.where((s) => s.youtubeId != null || s.isStreaming).map((s) => s.toJson()).toList();
      await backupFile.writeAsString(json.encode(streamingOnly));
    } catch (e) {
      print('Error saving metadata cache: $e');
    }
  }

  final Set<String> _downloadingSongIds = {};
  bool isSongDownloading(String songId) => _downloadingSongIds.contains(songId);

  /// Descargar una canción de streaming para escucharla 100% offline sin conexión
  Future<void> downloadSongForOffline(Song song) async {
    if (song.localAudioPath != null && await File(song.localAudioPath!).exists() && await File(song.localAudioPath!).length() > 50000) {
      return;
    }
    if (song.youtubeId == null) return;

    _downloadingSongIds.add(song.id);
    notifyListeners();

    try {
      final docDir = await getApplicationDocumentsDirectory();
      // Guardar en vibe_offline dentro de documentos privados de la app para no generar duplicados en el escáner
      final targetDir = Directory(path.join(docDir.path, 'vibe_offline'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final safeName = '${song.artist} - ${song.title}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final targetPath = path.join(targetDir.path, '${song.id}_$safeName.m4a');

      await YouTubeStreamResolver.downloadToFile(song.youtubeId!, targetPath);

      final updated = song.copyWith(
        localAudioPath: targetPath,
        isDownloaded: true,
      );

      final index = _librarySongs.indexWhere((s) => s.id == song.id);
      if (index != -1) {
        _librarySongs[index] = updated;
      } else {
        _librarySongs.insert(0, updated);
      }

      if (_currentSong?.id == song.id) {
        _currentSong = updated;
      }

      await _saveMetadataCache();
      notifyListeners();
    } catch (e) {
      print('Download offline error: $e');
      rethrow;
    } finally {
      _downloadingSongIds.remove(song.id);
      notifyListeners();
    }
  }

  final List<Song> _backgroundQueue = [];
  bool _isProcessingBackgroundQueue = false;

  /// Encola canciones para resolver su enlace de YouTube, su carátula real y descargarlas en segundo plano
  void enqueueForBackgroundProcessing(List<Song> songs) {
    for (final song in songs) {
      if (!_backgroundQueue.any((s) => s.id == song.id)) {
        if (song.localAudioPath == null ||
            !File(song.localAudioPath!).existsSync() ||
            File(song.localAudioPath!).lengthSync() < 50000 ||
            song.youtubeId == null ||
            song.localCoverPath == null) {
          _backgroundQueue.add(song);
        }
      }
    }
    _processBackgroundQueue();
  }

  Future<void> _processBackgroundQueue() async {
    if (_isProcessingBackgroundQueue) return;
    _isProcessingBackgroundQueue = true;

    while (_backgroundQueue.isNotEmpty) {
      final currentBatch = _backgroundQueue.take(2).toList();
      _backgroundQueue.removeRange(0, currentBatch.length);

      await Future.wait(currentBatch.map((song) async {
        try {
          await _preloadSongInBackground(song);
        } catch (e) {
          print('Background preloader error for ${song.title}: $e');
        }
      }));

      await Future.delayed(const Duration(milliseconds: 300));
    }

    _isProcessingBackgroundQueue = false;
  }

  void addSong(Song song) {
    _librarySongs.removeWhere((s) =>
        s.id == song.id || (song.localAudioPath != null && s.localAudioPath == song.localAudioPath));
    _librarySongs.insert(0, song);
    if (_currentSong == null) {
      _currentSong = song;
      if (song.duration > Duration.zero) {
        _duration = song.duration;
      }
    }
    _saveMetadataCache();
    notifyListeners();

    // Iniciar descarga y resolución en segundo plano inmediatamente
    enqueueForBackgroundProcessing([song]);
  }

  /// Agrega múltiples canciones en lote a la biblioteca y opcionalmente a una playlist
  Future<void> addSongs(List<Song> songs, {String? targetPlaylist}) async {
    for (final song in songs) {
      _librarySongs.removeWhere((s) =>
          s.id == song.id || (song.localAudioPath != null && s.localAudioPath == song.localAudioPath));
      _librarySongs.insert(0, song);
    }
    if (_currentSong == null && songs.isNotEmpty) {
      _currentSong = songs.first;
      if (songs.first.duration > Duration.zero) {
        _duration = songs.first.duration;
      }
    }
    if (targetPlaylist != null && targetPlaylist.trim().isNotEmpty) {
      final name = targetPlaylist.trim();
      _userPlaylists.putIfAbsent(name, () => []);
      for (final song in songs) {
        if (!_userPlaylists[name]!.contains(song.id)) {
          _userPlaylists[name]!.add(song.id);
        }
      }
      await _savePlaylistsCache();
    }
    await _saveMetadataCache();
    notifyListeners();

    // Iniciar descarga y enriquecimiento de carátulas en segundo plano
    enqueueForBackgroundProcessing(songs);
  }

  /// Descarga el audio en segundo plano de forma silenciosa e instantánea, resolviendo metadatos si faltan
  Future<void> _preloadSongInBackground(Song song) async {
    _downloadingSongIds.add(song.id);
    notifyListeners();

    try {
      // 1. Resolver enlace de YouTube si aún no está asignado
      if (song.youtubeId == null || song.youtubeId!.isEmpty) {
        final ytId = await LinkImportService.findOnYouTube(song.artist, song.title, song.duration);
        if (ytId != null && ytId.isNotEmpty) {
          song = song.copyWith(youtubeId: ytId);
          final idx = _librarySongs.indexWhere((s) => s.id == song.id);
          if (idx != -1) _librarySongs[idx] = song;
          if (_currentSong?.id == song.id) _currentSong = song;
          await _saveMetadataCache();
        } else {
          return;
        }
      }

      // 2. Resolver carátula real del álbum/canción si aún no tiene carátula local
      if (song.localCoverPath == null || !File(song.localCoverPath!).existsSync()) {
        String? spotifyId;
        if (song.sourceUrl != null) {
          final m = RegExp(r'track/([A-Za-z0-9]{22})').firstMatch(song.sourceUrl!);
          spotifyId = m?.group(1);
        }
        final coverUrl = await LinkImportService.fetchTrackCover(
          artist: song.artist,
          title: song.title,
          spotifyTrackId: spotifyId,
        );
        if (coverUrl != null && coverUrl.isNotEmpty) {
          final localPath = await AITaggerService.downloadAndSaveCover(coverUrl, song.id);
          song = song.copyWith(coverUrl: coverUrl, localCoverPath: localPath);
          final idx = _librarySongs.indexWhere((s) => s.id == song.id);
          if (idx != -1) _librarySongs[idx] = song;
          if (_currentSong?.id == song.id) _currentSong = song;
          await _saveMetadataCache();
        }
      }

      // 3. Descargar el archivo de audio a la caché local
      final cachedFile = await YouTubeStreamResolver.getOrDownloadStreamAudio(song.youtubeId!);
      if (await cachedFile.exists() && await cachedFile.length() > 50000) {
        Duration songDuration = song.duration;
        final exactM4aDur = await AudioDurationHelper.readM4aDuration(cachedFile);
        if (exactM4aDur != null && exactM4aDur > Duration.zero) {
          if (songDuration == Duration.zero ||
              (songDuration.inSeconds >= (exactM4aDur.inSeconds * 1.8).round() &&
               songDuration.inSeconds <= (exactM4aDur.inSeconds * 2.2).round())) {
            songDuration = exactM4aDur;
          }
        }

        final updated = song.copyWith(
          localAudioPath: cachedFile.path,
          duration: songDuration,
          isDownloaded: true,
        );
        final idx = _librarySongs.indexWhere((s) => s.id == song.id);
        if (idx != -1) {
          _librarySongs[idx] = updated;
        }
        if (_currentSong?.id == song.id) {
          _currentSong = updated;
          if (songDuration > Duration.zero) {
            _duration = songDuration;
          }
        }
        await _saveMetadataCache();
      }
    } catch (e) {
      print('Error precargando canción en segundo plano (${song.title}): $e');
    } finally {
      _downloadingSongIds.remove(song.id);
      notifyListeners();
    }
  }

  bool containsSong(String id) => _librarySongs.any((s) => s.id == id);

  /// Quitar una canción importada (streaming/offline) de la biblioteca
  Future<void> removeStreamingSong(Song song) async {
    await deleteSongs([song.id]);
  }

  /// Elimina múltiples canciones seleccionadas de la biblioteca y del almacenamiento
  Future<void> deleteSongs(List<String> songIds) async {
    final toDelete = _librarySongs.where((s) => songIds.contains(s.id)).toList();
    for (final song in toDelete) {
      _librarySongs.removeWhere((s) => s.id == song.id);
      _activeQueue.removeWhere((s) => s.id == song.id);
      if (_currentSong?.id == song.id) {
        await _player.stop();
        _isPlaying = false;
        _currentSong = null;
      }
      if (song.localAudioPath != null) {
        try {
          final f = File(song.localAudioPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      for (final ids in _userPlaylists.values) {
        ids.remove(song.id);
      }
    }
    await _savePlaylistsCache();
    await _saveMetadataCache();
    notifyListeners();
  }

  /// Elimina una playlist completa con opción de borrar también sus canciones de la biblioteca
  Future<void> deletePlaylistWithSongs(String playlistName, {bool deleteSongsFromLibrary = true}) async {
    final songIds = _userPlaylists[playlistName] != null
        ? List<String>.from(_userPlaylists[playlistName]!)
        : <String>[];
    _userPlaylists.remove(playlistName);
    await _savePlaylistsCache();

    if (deleteSongsFromLibrary && songIds.isNotEmpty) {
      await deleteSongs(songIds);
    } else {
      notifyListeners();
    }
  }

  void toggleLike(Song song) {
    final index = _librarySongs.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _librarySongs[index] = _librarySongs[index].copyWith(
        isLiked: !_librarySongs[index].isLiked,
      );
      if (_currentSong?.id == song.id) {
        _currentSong = _librarySongs[index];
      }
      _saveMetadataCache();
      notifyListeners();
    }
  }

  List<Song> get likedSongs => _librarySongs.where((s) => s.isLiked).toList();

  List<Song> _activeQueue = [];
  List<Song> get activeQueue => _activeQueue.isNotEmpty ? _activeQueue : _librarySongs;

  /// Reproducir una lista o cola específica de canciones
  Future<void> playPlaylist(List<Song> playlistSongs, Song startSong) async {
    _activeQueue = List.from(playlistSongs);
    await playSong(startSong);
  }

  MediaItem _mediaItemFor(Song song) {
    Uri? coverUri;
    if (song.localCoverPath != null && File(song.localCoverPath!).existsSync()) {
      coverUri = Uri.file(song.localCoverPath!);
    } else if (song.coverUrl != null && song.coverUrl!.startsWith('http')) {
      coverUri = Uri.parse(song.coverUrl!);
    }
    return MediaItem(
      id: song.id,
      album: song.album,
      title: song.title,
      artist: song.artist,
      genre: song.genre,
      artUri: coverUri,
      duration: song.duration == Duration.zero ? null : song.duration,
    );
  }

  Future<void> playSong(Song song) async {
    final token = ++_playToken;
    _currentSong = song;
    if (song.duration > Duration.zero) {
      _duration = song.duration;
    }
    _position = Duration.zero;
    if (_activeQueue.isEmpty || !_activeQueue.any((s) => s.id == song.id)) {
      _activeQueue = List.from(_librarySongs);
    }
    playbackError.value = null;
    notifyListeners();

    final mediaItem = _mediaItemFor(song);
    HomeWidgetBridge.update(song, isPlaying: true);

    // Actualizar cola y controles en la pantalla de bloqueo (iOS/Android)
    final queueItems = _activeQueue.map((s) => _mediaItemFor(s)).toList();
    final currentIdx = _activeQueue.indexWhere((s) => s.id == song.id);
    _handler.updateQueueState(queueItems, currentIdx >= 0 ? currentIdx : 0);

    // Precargar automáticamente la SIGUIENTE canción en segundo plano para transición inmediata
    if (_activeQueue.length > 1 && currentIdx != -1) {
      final nextSong = _activeQueue[(currentIdx + 1) % _activeQueue.length];
      if (nextSong.youtubeId != null &&
          (nextSong.localAudioPath == null ||
              !File(nextSong.localAudioPath!).existsSync() ||
              File(nextSong.localAudioPath!).lengthSync() < 50000)) {
        unawaited(_preloadSongInBackground(nextSong));
      }
    }

    // Pausar inmediatamente la canción anterior para evitar que continúe sonando
    // mientras la nueva canción se resuelve o descarga
    if (_player.playing) {
      await _player.pause();
    }

    try {
      bool playedFromLocal = false;
      if (song.localAudioPath != null && await File(song.localAudioPath!).exists()) {
        final f = File(song.localAudioPath!);
        if (await f.length() > 50000) {
          await _handler.loadAndPlay(mediaItem, AudioSource.uri(Uri.file(song.localAudioPath!), tag: mediaItem));
          playedFromLocal = true;
        } else {
          try {
            await f.delete();
          } catch (_) {}
        }
      }

      if (!playedFromLocal) {
        if (song.youtubeId != null || song.source == 'spotify' || song.isImported) {
          await _playStreaming(song, mediaItem, token);
        } else if (song.audioUrl != null) {
          await _handler.loadAndPlay(mediaItem, AudioSource.uri(Uri.parse(song.audioUrl!), tag: mediaItem));
        }
      }
    } catch (e) {
      print('Play song error: $e');
      if (token == _playToken) {
        await _player.stop();
        _isPlaying = false;
        playbackError.value = 'No se pudo reproducir "${song.title}"';
        notifyListeners();
      }
    } finally {
      if (token == _playToken && _isBuffering) {
        _isBuffering = false;
        notifyListeners();
      }
    }

    // Analizar el espectro en segundo plano (iOS); en Android es en vivo
    if (token == _playToken) {
      unawaited(spectrum.onTrackChanged(song));
    }
  }

  /// Reproduce una canción en streaming desde YouTube.
  /// Obtiene o descarga el audio de forma transparente a la caché local
  /// evitando el error 403 de ExoPlayer y permitiendo reproducción offline inmediata.
  Future<void> _playStreaming(Song song, MediaItem mediaItem, int token) async {
    _isBuffering = true;
    notifyListeners();

    try {
      String? ytId = song.youtubeId;
      if (ytId == null || ytId.isEmpty) {
        ytId = await LinkImportService.findOnYouTube(song.artist, song.title, song.duration);
        if (token != _playToken) return;
        if (ytId == null || ytId.isEmpty) {
          throw Exception('No se encontró el audio de "${song.title}" en YouTube');
        }
        final withYt = song.copyWith(youtubeId: ytId);
        final idx = _librarySongs.indexWhere((s) => s.id == song.id);
        if (idx != -1) {
          _librarySongs[idx] = withYt;
        }
        if (_currentSong?.id == song.id) {
          _currentSong = withYt;
        }
        unawaited(_saveMetadataCache());
        song = withYt;
      }

      final cachedFile = await YouTubeStreamResolver.getOrDownloadStreamAudio(ytId);
      if (token != _playToken) return; // El usuario ya cambió de canción

      // Actualizar automáticamente la ruta local para que quede guardada y funcione sin internet
      final updated = song.copyWith(
        localAudioPath: cachedFile.path,
        isDownloaded: true,
      );
      final idx = _librarySongs.indexWhere((s) => s.id == song.id);
      if (idx != -1) {
        _librarySongs[idx] = updated;
      }
      if (_currentSong?.id == song.id) {
        _currentSong = updated;
      }
      unawaited(_saveMetadataCache());

      final updatedMediaItem = _mediaItemFor(updated);
      await _handler.loadAndPlay(
        updatedMediaItem,
        AudioSource.uri(Uri.file(cachedFile.path), tag: updatedMediaItem),
      );
    } catch (e) {
      print('Streaming playback error: $e');
      rethrow;
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentSong == null && activeQueue.isNotEmpty) {
      await playSong(activeQueue.first);
      return;
    }

    // Al abrir la app hay una canción seleccionada pero todavía no cargada en el reproductor
    if (_player.processingState == ProcessingState.idle && _currentSong != null) {
      await playSong(_currentSong!);
      return;
    }

    if (_isPlaying) {
      await _player.pause();
      _isPlaying = false;
    } else {
      await _player.play();
      _isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    _position = pos;
    await _player.seek(pos);
    notifyListeners();
  }

  final _shuffleRandom = Random();

  void skipNext({bool fromCompletion = false}) {
    final queue = activeQueue;
    if (queue.isEmpty) return;
    int currentIndex = queue.indexWhere((s) => s.id == _currentSong?.id);
    if (currentIndex == -1) currentIndex = 0;

    if (_isShuffle && queue.length > 1) {
      int randomIndex;
      do {
        randomIndex = _shuffleRandom.nextInt(queue.length);
      } while (randomIndex == currentIndex);
      playSong(queue[randomIndex]);
    } else {
      // Sin repetición, la reproducción se detiene al terminar la última canción de la cola
      if (fromCompletion && _loopMode == LoopMode.off && currentIndex == queue.length - 1) {
        _handler.stop();
        return;
      }
      int nextIndex = (currentIndex + 1) % queue.length;
      playSong(queue[nextIndex]);
    }
  }

  void skipPrevious() {
    // Como en cualquier reproductor: si ya avanzó más de 3 segundos, vuelve al inicio
    if (_player.position > const Duration(seconds: 3)) {
      seek(Duration.zero);
      return;
    }

    final queue = activeQueue;
    if (queue.isEmpty) return;
    int currentIndex = queue.indexWhere((s) => s.id == _currentSong?.id);
    if (currentIndex == -1) currentIndex = 0;

    int prevIndex = (currentIndex - 1 + queue.length) % queue.length;
    playSong(queue[prevIndex]);
  }

  Future<void> toggleShuffle() async {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else {
      _loopMode = LoopMode.off;
    }
    // El reproductor solo tiene una pista cargada: "repetir una" se hace nativamente
    // y "repetir todo" lo maneja la cola en skipNext
    await _player.setLoopMode(_loopMode == LoopMode.one ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  void setEqualizerGain(int index, double gain) {
    if (index >= 0 && index < _equalizerGains.length) {
      _equalizerGains[index] = gain;
      _activePreset = 'Personalizado';
      _applyAudioGains();
      notifyListeners();
    }
  }

  void applyEqualizerPreset(String presetName) {
    if (_presets.containsKey(presetName)) {
      _activePreset = presetName;
      _equalizerGains = List.from(_presets[presetName]!);
      _applyAudioGains();
      notifyListeners();
    }
  }

  void resetEqualizer() {
    applyEqualizerPreset('Normal');
  }

  void _applyAudioGains() {
    double avgGain = _equalizerGains.reduce((a, b) => a + b) / _equalizerGains.length;
    double volume = (avgGain * 1.2).clamp(0.1, 1.0);
    _player.setVolume(volume);
  }

  void setAiTagging(bool value) {
    _enableAiTagging = value;
    notifyListeners();
  }

  Future<Song?> runAiIdentificationForSong(Song song) async {
    final enriched = await AITaggerService.identifyAndEnrich(song);
    final index = _librarySongs.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _librarySongs[index] = enriched;
      if (_currentSong?.id == song.id) {
        _currentSong = enriched;
      }
      await _saveMetadataCache();
      notifyListeners();
    }
    return enriched;
  }

  /// Seleccionar y asignar un Video de la Galería como Carátula (sin audio, en bucle infinito)
  Future<Song?> setVideoCoverForSong(Song song) async {
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickVideo(source: ImageSource.gallery);

      if (pickedFile != null) {
        final docDir = await getApplicationDocumentsDirectory();
        final videoDir = Directory(path.join(docDir.path, 'video_covers'));
        if (!await videoDir.exists()) {
          await videoDir.create(recursive: true);
        }

        final sanitizedId = song.id.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final targetPath = path.join(videoDir.path, 'video_$sanitizedId.mp4');
        await File(pickedFile.path).copy(targetPath);

        final updated = song.copyWith(videoCoverPath: targetPath);
        final index = _librarySongs.indexWhere((s) => s.id == song.id);
        if (index != -1) {
          _librarySongs[index] = updated;
          if (_currentSong?.id == song.id) {
            _currentSong = updated;
          }
          await _saveMetadataCache();
          notifyListeners();
        }
        return updated;
      }
    } catch (e) {
      print('Error picking video cover: $e');
    }
    return null;
  }

  /// Editar manualmente Título y Artista y re-identificar carátula oficial automáticamente
  Future<Song> updateSongMetadata(Song song, String newTitle, String newArtist) async {
    final updated = song.copyWith(
      title: newTitle.trim(),
      artist: newArtist.trim(),
    );
    final index = _librarySongs.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _librarySongs[index] = updated;
      if (_currentSong?.id == song.id) {
        _currentSong = updated;
      }
      await _saveMetadataCache();
      notifyListeners();
    }
    final enriched = await runAiIdentificationForSong(updated);
    return enriched ?? updated;
  }


  /// Importar canciones manualmente usando file_selector
  Future<List<Song>> importCustomMusicFile() async {
    List<Song> importedSongs = [];
    try {
      const XTypeGroup audioTypeGroup = XTypeGroup(
        label: 'Audio files',
        extensions: <String>['mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg', 'webm'],
      );

      final List<XFile> files = await openFiles(acceptedTypeGroups: <XTypeGroup>[audioTypeGroup]);

      if (files.isNotEmpty) {
        final docDir = await getApplicationDocumentsDirectory();
        final musicDir = Directory(path.join(docDir.path, 'imported_music'));
        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
        }

        for (final file in files) {
          final fileName = path.basename(file.path);
          final targetPath = path.join(musicDir.path, fileName);
          await File(file.path).copy(targetPath);

          Duration songDuration = Duration.zero;
          if (fileName.toLowerCase().endsWith('.m4a') || fileName.toLowerCase().endsWith('.mp4')) {
            songDuration = (await AudioDurationHelper.readM4aDuration(File(targetPath))) ?? Duration.zero;
          }
          if (songDuration == Duration.zero) {
            try {
              final probe = AudioPlayer();
              final dur = await probe.setFilePath(targetPath);
              if (dur != null) songDuration = dur;
              await probe.dispose();
            } catch (_) {}
          }

          Song song = Song(
            id: targetPath,
            title: path.basenameWithoutExtension(fileName),
            artist: 'Artista Local',
            album: 'Música Importada',
            localAudioPath: targetPath,
            duration: songDuration,
            isDownloaded: true,
          );

          if (_enableAiTagging) {
            final enriched = await AITaggerService.identifyAndEnrich(song);
            song = enriched;
          }

          addSong(song);
          importedSongs.add(song);
        }
      }
    } catch (e) {
      print('Error importing music file: $e');
    }
    return importedSongs;
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
