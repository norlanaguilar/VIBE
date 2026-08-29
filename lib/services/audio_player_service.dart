import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/song_model.dart';
import 'ai_tagger_service.dart';

class AudioPlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

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

  LoopMode _loopMode = LoopMode.off;
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

  /// Playlists configuradas automáticamente
  Map<String, List<Song>> get playlists {
    return {
      'Mis Favoritas ❤️': likedSongs,
      'Agregadas Recientemente 🕒': _librarySongs.take(10).toList(),
      'Música Local 📁': _librarySongs,
    };
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

  AudioPlayerService() {
    scanLocalLibrary();
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });

    _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipNext();
      }
    });
  }

  /// Escanear directorio de documentos (iOS Archivos / Android) de forma recursiva
  Future<void> scanLocalLibrary() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Crear README.md directamente en el directorio principal
      final readmeFile = File(path.join(appDir.path, 'README.md'));
      if (!await readmeFile.exists()) {
        await readmeFile.writeAsString(
          '# Carpeta de Música VibeLocal\n\nColoca tus canciones (.mp3, .m4a, .wav, .flac) aquí desde la app Archivos de iOS o tu explorador.',
        );
      }

      List<Song> loadedSongs = [];
      Set<String> scannedPaths = {};

      if (await appDir.exists()) {
        final List<FileSystemEntity> entities = appDir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is File && !scannedPaths.contains(entity.path)) {
            scannedPaths.add(entity.path);
            final ext = path.extension(entity.path).toLowerCase();
            if (ext == '.m4a' || ext == '.mp3' || ext == '.webm' || ext == '.wav' || ext == '.aac' || ext == '.flac' || ext == '.ogg') {
              final fileName = path.basenameWithoutExtension(entity.path);

              Song song = Song(
                id: entity.path,
                title: fileName,
                artist: 'Artista Local',
                album: 'Biblioteca Local',
                localAudioPath: entity.path,
                isDownloaded: true,
              );

              loadedSongs.add(song);
            }
          }
        }
      }

      // Actualizar biblioteca de canciones al instante
      _librarySongs = loadedSongs;
      if (_librarySongs.isNotEmpty && _currentSong == null) {
        _currentSong = _librarySongs.first;
      }
      notifyListeners();

      // Leer la duración exacta de cada archivo local en segundo plano
      for (int i = 0; i < _librarySongs.length; i++) {
        if (_librarySongs[i].duration == Duration.zero && _librarySongs[i].localAudioPath != null) {
          try {
            final probe = AudioPlayer();
            final dur = await probe.setFilePath(_librarySongs[i].localAudioPath!);
            if (dur != null) {
              _librarySongs[i] = _librarySongs[i].copyWith(duration: dur);
              if (_currentSong?.id == _librarySongs[i].id) {
                _currentSong = _librarySongs[i];
              }
              notifyListeners();
            }
            await probe.dispose();
          } catch (_) {}
        }
      }

      // Procesar etiquetas de IA en segundo plano de forma no bloqueante
      if (_enableAiTagging) {
        for (int i = 0; i < _librarySongs.length; i++) {
          try {
            final enriched = await AITaggerService.identifyAndEnrich(_librarySongs[i]);
            _librarySongs[i] = enriched;
            if (_currentSong?.id == enriched.id) {
              _currentSong = enriched;
            }
            notifyListeners();
          } catch (e) {
            print('AI tagging skipped for ${_librarySongs[i].title}: $e');
          }
        }
      }
    } catch (e) {
      print('Error loading local music: $e');
    }
  }

  void addSong(Song song) {
    _librarySongs.removeWhere((s) => s.id == song.id || s.localAudioPath == song.localAudioPath);
    _librarySongs.insert(0, song);
    if (_currentSong == null) {
      _currentSong = song;
    }
    notifyListeners();
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
      notifyListeners();
    }
  }

  List<Song> get likedSongs => _librarySongs.where((s) => s.isLiked).toList();

  Future<void> playSong(Song song) async {
    _currentSong = song;
    notifyListeners();

    try {
      Uri? coverUri;
      if (song.localCoverPath != null && await File(song.localCoverPath!).exists()) {
        coverUri = Uri.file(song.localCoverPath!);
      } else if (song.coverUrl != null && song.coverUrl!.startsWith('http')) {
        coverUri = Uri.parse(song.coverUrl!);
      }

      final mediaItem = MediaItem(
        id: song.id,
        album: song.album,
        title: song.title,
        artist: song.artist,
        artUri: coverUri,
        duration: song.duration,
      );

      if (song.localAudioPath != null && await File(song.localAudioPath!).exists()) {
        final audioSource = AudioSource.uri(
          Uri.file(song.localAudioPath!),
          tag: mediaItem,
        );
        await _player.setAudioSource(audioSource);
        await _player.play();
      } else if (song.audioUrl != null) {
        final audioSource = AudioSource.uri(
          Uri.parse(song.audioUrl!),
          tag: mediaItem,
        );
        await _player.setAudioSource(audioSource);
        await _player.play();
      }
    } catch (e) {
      print('Play song error: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentSong == null && _librarySongs.isNotEmpty) {
      await playSong(_librarySongs.first);
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

  void skipNext() {
    if (_librarySongs.isEmpty) return;
    int currentIndex = _librarySongs.indexWhere((s) => s.id == _currentSong?.id);
    int nextIndex = (currentIndex + 1) % _librarySongs.length;
    playSong(_librarySongs[nextIndex]);
  }

  void skipPrevious() {
    if (_librarySongs.isEmpty) return;
    int currentIndex = _librarySongs.indexWhere((s) => s.id == _currentSong?.id);
    int prevIndex = (currentIndex - 1 + _librarySongs.length) % _librarySongs.length;
    playSong(_librarySongs[prevIndex]);
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  void toggleRepeat() {
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else {
      _loopMode = LoopMode.off;
    }
    _player.setLoopMode(_loopMode);
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
    // Ajustar volumen master proporcional a la ganancia de bandas del ecualizador
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
      notifyListeners();
    }
    return enriched;
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
      notifyListeners();
    }
    final enriched = await runAiIdentificationForSong(updated);
    return enriched ?? updated;
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
