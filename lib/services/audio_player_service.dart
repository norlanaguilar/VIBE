import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
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

  // Equalizer gains for 5 bands: 60Hz, 230Hz, 910Hz, 4kHz, 14kHz (range 0.0 - 1.0)
  List<double> _equalizerGains = [0.70, 0.45, 0.50, 0.65, 0.80];
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

  /// Escanear directorio de documentos (iOS Archivos / Android) y subcarpeta de música
  Future<void> scanLocalLibrary() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory(path.join(appDir.path, 'vibe_music'));

      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
        final readmeFile = File(path.join(musicDir.path, 'README.md'));
        if (!await readmeFile.exists()) {
          await readmeFile.writeAsString(
            '# Carpeta de Música VibeLocal\n\nColoca aquí tus canciones (.mp3, .m4a, .wav, .flac) desde la app Archivos de iOS.',
          );
        }
      }

      List<Directory> dirsToScan = [appDir, musicDir];

      List<Song> loadedSongs = [];
      Set<String> scannedPaths = {};

      for (final dir in dirsToScan) {
        if (await dir.exists()) {
          final List<FileSystemEntity> files = dir.listSync();
          for (final entity in files) {
            if (entity is File && !scannedPaths.contains(entity.path)) {
              scannedPaths.add(entity.path);
              final ext = path.extension(entity.path).toLowerCase();
              if (ext == '.m4a' || ext == '.mp3' || ext == '.webm' || ext == '.wav' || ext == '.aac' || ext == '.flac') {
                final fileName = path.basenameWithoutExtension(entity.path);

                Song song = Song(
                  id: entity.path,
                  title: fileName,
                  artist: 'Artista Local',
                  album: 'Biblioteca Local',
                  localAudioPath: entity.path,
                  isDownloaded: true,
                );

                // Identificación IA automática opcional
                if (_enableAiTagging) {
                  song = await AITaggerService.identifyAndEnrich(song);
                }

                loadedSongs.add(song);
              }
            }
          }
        }
      }

      _librarySongs = loadedSongs;
      if (_librarySongs.isNotEmpty && _currentSong == null) {
        _currentSong = _librarySongs.first;
      }
      notifyListeners();
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
      if (song.localAudioPath != null && await File(song.localAudioPath!).exists()) {
        await _player.setFilePath(song.localAudioPath!);
        await _player.play();
      } else if (song.audioUrl != null) {
        await _player.setUrl(song.audioUrl!);
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
      notifyListeners();
    }
  }

  void resetEqualizer() {
    _equalizerGains = [0.70, 0.45, 0.50, 0.65, 0.80];
    notifyListeners();
  }

  void setAiTagging(bool value) {
    _enableAiTagging = value;
    notifyListeners();
  }

  Future<void> runAiIdentificationForSong(Song song) async {
    final enriched = await AITaggerService.identifyAndEnrich(song);
    final index = _librarySongs.indexWhere((s) => s.id == song.id);
    if (index != -1) {
      _librarySongs[index] = enriched;
      if (_currentSong?.id == song.id) {
        _currentSong = enriched;
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
