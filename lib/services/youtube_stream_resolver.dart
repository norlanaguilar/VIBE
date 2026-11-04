import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class StreamAudioResult {
  final String streamUrl;
  final int contentLength;
  final String container;
  StreamAudioResult({
    required this.streamUrl,
    required this.contentLength,
    required this.container,
  });
}

/// Obtiene y almacena en caché el audio de canciones de YouTube de forma ultra-rápida y confiable.
///
/// Utiliza instancias de alta disponibilidad de Invidious (que incluyen tokens `pot` y descifrado de firmas)
/// y fallback a `youtube_explode_dart 3.1.0`.
/// Descarga en paralelo por bloques Range en ~1 segundo, evitando errores 403 Forbidden y permitiendo
/// reproducción offline inmediata.
class YouTubeStreamResolver {
  static final List<String> _invidiousInstances = [
    'https://inv.nadeko.net',
    'https://yt.chocolatemoo53.com',
    'https://invidious.nerdvpn.de',
  ];

  static final Map<String, Future<File>> _activeDownloads = {};

  /// Resuelve la URL directa del audio de un video de YouTube
  static Future<StreamAudioResult> resolveAudioStream(String videoId) async {
    // 1. Intentar con instancias optimizadas de Invidious (incluyen firmas válidas y pot)
    for (final inst in _invidiousInstances) {
      try {
        final res = await http.get(Uri.parse('$inst/api/v1/videos/$videoId')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final adaptive = data['adaptiveFormats'] as List?;
          if (adaptive != null && adaptive.isNotEmpty) {
            final audioList = adaptive.where((f) {
              final type = f['type'] as String? ?? '';
              return type.startsWith('audio/mp4') || type.startsWith('audio/webm');
            }).toList();

            if (audioList.isNotEmpty) {
              // Preferir audio/mp4 (m4a) de mayor bitrate
              audioList.sort((a, b) {
                final aIsMp4 = (a['type'] as String).contains('mp4') ? 1 : 0;
                final bIsMp4 = (b['type'] as String).contains('mp4') ? 1 : 0;
                if (aIsMp4 != bIsMp4) return bIsMp4.compareTo(aIsMp4);
                final aBitrate = int.tryParse(a['bitrate']?.toString() ?? '0') ?? 0;
                final bBitrate = int.tryParse(b['bitrate']?.toString() ?? '0') ?? 0;
                return bBitrate.compareTo(aBitrate);
              });

              final selected = audioList.first;
              final url = selected['url'] as String;
              final clen = int.tryParse(selected['clen']?.toString() ?? '') ?? 0;
              final isMp4 = (selected['type'] as String).contains('mp4');

              return StreamAudioResult(
                streamUrl: url,
                contentLength: clen,
                container: isMp4 ? 'm4a' : 'webm',
              );
            }
          }
        }
      } catch (e) {
        print('Invidious instance $inst error: $e');
      }
    }

    // 2. Respaldo: youtube_explode_dart
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 8));
      final audioStreams = manifest.audioOnly.toList();
      if (audioStreams.isEmpty) {
        throw Exception('Este video no tiene pistas de audio disponibles.');
      }
      final mp4Streams = audioStreams.where((s) => s.container == StreamContainer.mp4).toList();
      final stream = mp4Streams.isNotEmpty ? mp4Streams.withHighestBitrate() : audioStreams.withHighestBitrate();

      return StreamAudioResult(
        streamUrl: stream.url.toString(),
        contentLength: stream.size.totalBytes,
        container: stream.container.name,
      );
    } finally {
      yt.close();
    }
  }

  /// Retorna el archivo local de la canción, descargándolo en paralelo a la caché si aún no existe
  static Future<File> getOrDownloadStreamAudio(String videoId) async {
    if (_activeDownloads.containsKey(videoId)) {
      return await _activeDownloads[videoId]!;
    }

    final future = _getOrDownloadInternal(videoId);
    _activeDownloads[videoId] = future;
    try {
      return await future;
    } finally {
      _activeDownloads.remove(videoId);
    }
  }

  static Future<File> _getOrDownloadInternal(String videoId) async {
    final dir = await getApplicationDocumentsDirectory();
    final streamsDir = Directory(path.join(dir.path, 'vibe_streams'));
    if (!await streamsDir.exists()) {
      await streamsDir.create(recursive: true);
    }

    final file = File(path.join(streamsDir.path, 'stream_$videoId.m4a'));
    if (await file.exists()) {
      final len = await file.length();
      if (len > 50000) {
        return file;
      }
      try {
        await file.delete();
      } catch (_) {}
    }

    return await downloadToFile(videoId, file.path);
  }

  /// Descarga el audio a un archivo local de forma rápida mediante bloques en paralelo
  static Future<File> downloadToFile(String videoId, String targetPath) async {
    final meta = await resolveAudioStream(videoId);
    final file = File(targetPath);

    // Asegurar directorio contenedor
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final tempFile = File('$targetPath.part');
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    final clen = meta.contentLength > 0 ? meta.contentLength : await _probeContentLength(meta.streamUrl);

    if (clen > 0) {
      // Descarga acelerada en bloques concurrentes de 1 MB
      const chunkSize = 1024 * 1024;
      final numChunks = (clen / chunkSize).ceil();
      final futures = <Future<List<int>>>[];

      for (int i = 0; i < numChunks; i++) {
        final start = i * chunkSize;
        final end = (i + 1 == numChunks) ? (clen - 1) : (start + chunkSize - 1);
        futures.add(() async {
          final r = await http.get(
            Uri.parse(meta.streamUrl),
            headers: {'Range': 'bytes=$start-$end'},
          ).timeout(const Duration(seconds: 20));

          if (r.statusCode != 200 && r.statusCode != 206) {
            throw Exception('Error al descargar fragmento de audio (HTTP ${r.statusCode})');
          }
          return r.bodyBytes;
        }());
      }

      final chunks = await Future.wait(futures);
      final sink = tempFile.openWrite();
      for (final chunk in chunks) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } else {
      // Descarga secuencial si no se conoce el tamaño
      final req = await HttpClient().getUrl(Uri.parse(meta.streamUrl));
      final resp = await req.close();
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw Exception('Servidor rechazó la petición de audio (HTTP ${resp.statusCode})');
      }
      final sink = tempFile.openWrite();
      await resp.pipe(sink);
    }

    final len = await tempFile.length();
    if (len < 50000) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      throw Exception('La canción no se pudo descargar correctamente ($len bytes).');
    }

    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    await tempFile.rename(targetPath);

    return file;
  }

  static Future<int> _probeContentLength(String url) async {
    try {
      final res = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 4));
      return int.tryParse(res.headers['content-length'] ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
