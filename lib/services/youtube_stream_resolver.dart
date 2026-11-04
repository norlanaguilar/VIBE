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
/// Resuelve el audio directamente con `youtube_explode_dart` (generando tokens vinculados a la IP del dispositivo)
/// y descarga en bloques controlados con encabezados de navegador para evitar errores HTTP 403 Forbidden.
class YouTubeStreamResolver {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static final List<String> _invidiousInstances = [
    'https://inv.nadeko.net',
    'https://yt.chocolatemoo53.com',
  ];

  static final Map<String, Future<File>> _activeDownloads = {};

  /// Resuelve la URL directa del audio de un video de YouTube.
  /// Prioriza youtube_explode_dart para garantizar que la URL pertenezca a la IP de este dispositivo.
  static Future<StreamAudioResult> resolveAudioStream(String videoId) async {
    // 1. Prioridad: youtube_explode_dart (vinculado a la IP local)
    try {
      final yt = YoutubeExplode();
      try {
        final manifest = await yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 10));
        final audioStreams = manifest.audioOnly.toList();
        if (audioStreams.isNotEmpty) {
          final mp4Streams = audioStreams.where((s) => s.container == StreamContainer.mp4).toList();
          final stream = mp4Streams.isNotEmpty ? mp4Streams.withHighestBitrate() : audioStreams.withHighestBitrate();

          return StreamAudioResult(
            streamUrl: stream.url.toString(),
            contentLength: stream.size.totalBytes,
            container: stream.container.name,
          );
        }
      } finally {
        yt.close();
      }
    } catch (e) {
      print('YouTubeExplode manifest error ($videoId): $e');
    }

    // 2. Respaldo: instancias Invidious
    for (final inst in _invidiousInstances) {
      try {
        final res = await http.get(
          Uri.parse('$inst/api/v1/videos/$videoId'),
          headers: {'User-Agent': _userAgent},
        ).timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final adaptive = data['adaptiveFormats'] as List?;
          if (adaptive != null && adaptive.isNotEmpty) {
            final audioList = adaptive.where((f) {
              final type = f['type'] as String? ?? '';
              return type.startsWith('audio/mp4') || type.startsWith('audio/webm');
            }).toList();

            if (audioList.isNotEmpty) {
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
        print('Invidious fallback $inst error: $e');
      }
    }

    throw Exception('No se pudo obtener la pista de audio de este video.');
  }

  /// Retorna el archivo local de la canción, descargándolo a la caché si aún no existe
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

  /// Descarga el audio a un archivo local de forma rápida y robusta
  static Future<File> downloadToFile(String videoId, String targetPath) async {
    final meta = await resolveAudioStream(videoId);
    final file = File(targetPath);

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

    bool success = false;

    // Intento 1: Descarga por bloques con User-Agent de navegador
    final clen = meta.contentLength > 0 ? meta.contentLength : await _probeContentLength(meta.streamUrl);
    if (clen > 0) {
      try {
        const chunkSize = 1024 * 1024; // 1 MB
        final numChunks = (clen / chunkSize).ceil();
        final chunks = List<List<int>?>.filled(numChunks, null);

        // Limitar concurrencia a 3 descargas simultáneas para evitar throttling de Google
        int index = 0;
        Future<void> worker() async {
          while (true) {
            final i = index++;
            if (i >= numChunks) break;

            final start = i * chunkSize;
            final end = (i + 1 == numChunks) ? (clen - 1) : (start + chunkSize - 1);

            final r = await http.get(
              Uri.parse(meta.streamUrl),
              headers: {
                'User-Agent': _userAgent,
                'Range': 'bytes=$start-$end',
                'Accept': '*/*',
              },
            ).timeout(const Duration(seconds: 15));

            if (r.statusCode != 200 && r.statusCode != 206) {
              throw Exception('HTTP ${r.statusCode}');
            }
            chunks[i] = r.bodyBytes;
          }
        }

        final workers = List.generate(3, (_) => worker());
        await Future.wait(workers);

        if (!chunks.any((c) => c == null)) {
          final sink = tempFile.openWrite();
          for (final chunk in chunks) {
            sink.add(chunk!);
          }
          await sink.flush();
          await sink.close();
          success = true;
        }
      } catch (e) {
        print('Chunked download failed ($e), falling back to sequential stream...');
        if (await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }
    }

    // Intento 2 (Fallback): Descarga continua vía HttpClient con User-Agent
    if (!success) {
      try {
        final client = HttpClient();
        client.userAgent = _userAgent;
        final req = await client.getUrl(Uri.parse(meta.streamUrl));
        final resp = await req.close();
        if (resp.statusCode == 200 || resp.statusCode == 206) {
          final sink = tempFile.openWrite();
          await resp.pipe(sink);
          success = true;
        } else {
          throw Exception('HTTP ${resp.statusCode}');
        }
      } catch (e) {
        print('Sequential stream error: $e');
      }
    }

    // Verificación final del archivo generado
    if (await tempFile.exists()) {
      final len = await tempFile.length();
      if (len >= 50000) {
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
        await tempFile.rename(targetPath);
        return file;
      } else {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }

    throw Exception('No se pudo descargar el audio completo de la canción.');
  }

  static Future<int> _probeContentLength(String url) async {
    try {
      final res = await http.head(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 4));
      return int.tryParse(res.headers['content-length'] ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
