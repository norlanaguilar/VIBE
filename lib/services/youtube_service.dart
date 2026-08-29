import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song_model.dart';
import 'ai_tagger_service.dart';

class YouTubeSearchResult {
  final String id;
  final String title;
  final String author;
  final String durationStr;
  final String thumbnailUrl;

  YouTubeSearchResult({
    required this.id,
    required this.title,
    required this.author,
    required this.durationStr,
    required this.thumbnailUrl,
  });
}

class YouTubeService {
  /// Base URL del servidor local backend con yt-dlp y FFmpeg
  static List<String> get candidateBackendUrls {
    if (Platform.isAndroid) {
      return [
        'http://10.0.2.2:3000/download',
        'http://127.0.0.1:3000/download',
        'http://localhost:3000/download',
      ];
    }
    return [
      'http://localhost:3000/download',
      'http://127.0.0.1:3000/download',
    ];
  }

  /// Descarga MP3 realizando petición POST al backend local
  Future<Song?> downloadFromLocalBackend(
    String youtubeUrl, {
    required Function(double progress, String status) onProgress,
    bool enableAiTagging = true,
  }) async {

    // Intentar conectar con las URLs candidatas del servidor local
    for (final urlString in candidateBackendUrls) {
      try {
        onProgress(0.10, 'Conectando con servidor local ($urlString)...');

        final uri = Uri.parse(urlString);
        final client = http.Client();

        final request = http.Request('POST', uri)
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({'url': youtubeUrl});

        onProgress(0.25, 'Servidor procesando audio con yt-dlp...');

        final streamedResponse = await client.send(request).timeout(
          const Duration(seconds: 45),
        );

        if (streamedResponse.statusCode != 200) {
          throw Exception('El servidor respondió con código ${streamedResponse.statusCode}');
        }

        onProgress(0.55, 'Recibiendo archivo MP3...');

        final List<int> bytes = [];
        final totalLength = streamedResponse.contentLength ?? 0;

        await for (final chunk in streamedResponse.stream) {
          bytes.addAll(chunk);
          if (totalLength > 0) {
            final progress = 0.55 + (bytes.length / totalLength) * 0.30;
            onProgress(
              progress.clamp(0.55, 0.85),
              'Guardando audio... (${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB)',
            );
          }
        }

        onProgress(0.88, 'Guardando en almacenamiento local...');

        final appDir = await getApplicationDocumentsDirectory();
        final musicDir = Directory(path.join(appDir.path, 'vibe_music'));
        if (!await musicDir.exists()) {
          await musicDir.create(recursive: true);
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = path.join(musicDir.path, 'Track_$timestamp.mp3');
        final file = File(filePath);

        await file.writeAsBytes(bytes);

        Song song = Song(
          id: timestamp.toString(),
          title: 'Canción Descargada',
          artist: 'YouTube MP3',
          album: 'Descargas Backend',
          localAudioPath: filePath,
          isDownloaded: true,
        );

        if (enableAiTagging) {
          onProgress(0.92, 'Identificando con IA y generando carátula...');
          song = await AITaggerService.identifyAndEnrich(song);
        }

        onProgress(1.0, '¡Descarga completada!');
        return song;
      } catch (e) {
        print('Error intentando $urlString: $e');
      }
    }

    // Si el servidor local no responde, fallback directo con YoutubeExplode
    onProgress(0.15, 'Servidor local no disponible. Usando descarga directa...');
    return await downloadDirect(
      youtubeUrl,
      onProgress: onProgress,
      enableAiTagging: enableAiTagging,
    );
  }

  /// Fallback de descarga directa de audio de YouTube
  Future<Song?> downloadDirect(
    String youtubeUrl, {
    required Function(double progress, String status) onProgress,
    bool enableAiTagging = true,
  }) async {
    final yt = YoutubeExplode();
    try {
      onProgress(0.20, 'Obteniendo stream directo de YouTube...');
      
      final video = await yt.videos.get(youtubeUrl).timeout(const Duration(seconds: 15));
      final manifest = await yt.videos.streamsClient.getManifest(video.id).timeout(const Duration(seconds: 25));
      
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isEmpty) {
        throw Exception('No se encontró pista de audio en el vídeo.');
      }

      final audioInfo = audioStreams.withHighestBitrate();
      final audioStream = yt.videos.streamsClient.get(audioInfo);

      final appDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory(path.join(appDir.path, 'vibe_music'));
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final ext = audioInfo.container.name == 'webm' ? 'webm' : 'm4a';
      final filePath = path.join(musicDir.path, '$safeTitle.$ext');
      final file = File(filePath);

      final outputStream = file.openWrite();
      final totalSize = audioInfo.size.totalBytes;
      int downloaded = 0;

      await for (final chunk in audioStream) {
        downloaded += chunk.length;
        outputStream.add(chunk);
        if (totalSize > 0) {
          final progress = 0.35 + (downloaded / totalSize) * 0.50;
          onProgress(progress.clamp(0.35, 0.85), 'Descargando: ${((downloaded / totalSize) * 100).toInt()}%');
        }
      }

      await outputStream.flush();
      await outputStream.close();

      Song song = Song(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: video.title,
        artist: video.author,
        album: 'YouTube Direct Downloads',
        coverUrl: video.thumbnails.highResUrl,
        localAudioPath: filePath,
        duration: video.duration ?? Duration.zero,
        isDownloaded: true,
      );

      if (enableAiTagging) {
        onProgress(0.90, 'Identificando con IA y descargando portada...');
        song = await AITaggerService.identifyAndEnrich(song);
      }

      onProgress(1.0, '¡Descarga completada!');
      yt.close();
      return song;
    } catch (e) {
      yt.close();
      onProgress(0.0, 'Error: $e');
      rethrow;
    }
  }

  /// Search YouTube for music videos / audio tracks
  Future<List<YouTubeSearchResult>> search(String query) async {
    final yt = YoutubeExplode();
    try {
      final searchResults = await yt.search.search(query);
      final list = searchResults.map((video) {
        final duration = video.duration ?? Duration.zero;
        final minutes = duration.inMinutes;
        final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

        return YouTubeSearchResult(
          id: video.id.value,
          title: video.title,
          author: video.author,
          durationStr: '$minutes:$seconds',
          thumbnailUrl: video.thumbnails.highResUrl,
        );
      }).toList();
      yt.close();
      return list;
    } catch (e) {
      print('YouTube Search Error: $e');
      yt.close();
      return [];
    }
  }

  void dispose() {}
}
