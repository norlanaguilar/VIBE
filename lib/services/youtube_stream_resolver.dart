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
  final String userAgent;
  StreamAudioResult({
    required this.streamUrl,
    required this.contentLength,
    required this.container,
    this.userAgent = YouTubeStreamResolver._userAgent,
  });
}

/// Obtiene y almacena en caché el audio de canciones de YouTube de forma ultra-rápida y confiable.
///
/// Resuelve el audio directamente mediante el cliente InnerTube `VISIONOS` (que no requiere
/// GVS PO-Token ni trunca pistas musicales al llegar a 1 MB) con respaldo en `youtube_explode_dart`
/// e Invidious.
class YouTubeStreamResolver {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const _visionUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  static String? _cachedVisitorData;
  static DateTime _visitorDataExpiry = DateTime.fromMillisecondsSinceEpoch(0);

  static final List<String> _invidiousInstances = [
    'https://inv.nadeko.net',
    'https://yt.chocolatemoo53.com',
  ];

  static final Map<String, Future<File>> _activeDownloads = {};

  static YoutubeExplode? _sharedYt;

  /// Instancia compartida de YoutubeExplode para evitar descargar y compilar base.js en cada canción
  static YoutubeExplode get sharedYt => _sharedYt ??= YoutubeExplode();

  static void resetSharedYt() {
    try {
      _sharedYt?.close();
    } catch (_) {}
    _sharedYt = null;
  }

  /// Obtiene y almacena en caché un visitorData válido de YouTube para evitar bloqueos en pistas musicales
  static Future<String?> getVisitorData({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh && _cachedVisitorData != null && now.isBefore(_visitorDataExpiry)) {
      return _cachedVisitorData;
    }
    try {
      final res = await http
          .get(
            Uri.parse('https://www.youtube.com/sw.js_data'),
            headers: {'User-Agent': _visionUserAgent},
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final match = RegExp(r'"(Cgt[A-Za-z0-9_\-%]+)"').firstMatch(res.body);
        if (match != null) {
          _cachedVisitorData = match.group(1);
          _visitorDataExpiry = now.add(const Duration(minutes: 30));
          return _cachedVisitorData;
        }
      }
    } catch (_) {}
    return _cachedVisitorData;
  }

  /// Resuelve la URL directa del audio de un video de YouTube.
  static Future<StreamAudioResult> resolveAudioStream(String videoId) async {
    // 1. Prioridad máxima: Cliente InnerTube VISIONOS (1.02)
    // No tiene restricción GVS PO-Token ni bloqueo HTTP 403 al pasar 1 MB en canciones oficiales.
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final visitorData = await getVisitorData(forceRefresh: attempt > 0);
        final res = await http
            .post(
              Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent': _visionUserAgent,
                'X-YouTube-Client-Name': '101',
                'X-YouTube-Client-Version': '1.02',
                if (visitorData != null) 'X-Goog-Visitor-Id': visitorData,
              },
              body: json.encode({
                'videoId': videoId,
                'context': {
                  'client': {
                    'clientName': 'VISIONOS',
                    'clientVersion': '1.02',
                    'deviceMake': 'Apple',
                    'deviceModel': 'RealityDevice17,1',
                    'userAgent': _visionUserAgent,
                    'osName': 'visionOS',
                    'osVersion': '26.5.23O471',
                    'hl': 'en',
                    'gl': 'US',
                    if (visitorData != null) 'visitorData': visitorData,
                  },
                },
                'contentCheckOk': true,
                'racyCheckOk': true,
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          final adaptive = (data['streamingData']?['adaptiveFormats'] as List?) ?? [];
          final audioFormats = adaptive.whereType<Map<String, dynamic>>().where((f) {
            final mime = (f['mimeType'] as String?) ?? '';
            final url = (f['url'] as String?) ?? '';
            return url.isNotEmpty && (mime.startsWith('audio/mp4') || mime.startsWith('audio/webm'));
          }).toList();

          if (audioFormats.isNotEmpty) {
            // Preferir formato ligero audio/mp4 (itag 139 HE-AAC ~48kbps ~1.2 MB por canción, o menor bitrate disponible)
            // para reducir drásticamente el peso de los archivos .m4a manteniendo compatibilidad nativa
            Map<String, dynamic>? selected;
            for (final f in audioFormats) {
              if (f['itag'] == 139) {
                selected = f;
                break;
              }
            }
            if (selected == null) {
              final mp4List = audioFormats.where((f) {
                final mime = (f['mimeType'] as String?) ?? '';
                return mime.startsWith('audio/mp4');
              }).toList();
              final pool = mp4List.isNotEmpty ? mp4List : audioFormats;
              pool.sort((a, b) {
                final brA = (a['bitrate'] as num?)?.toInt() ?? 999999;
                final brB = (b['bitrate'] as num?)?.toInt() ?? 999999;
                return brA.compareTo(brB);
              });
              selected = pool.first;
            }

            final streamUrl = selected['url'] as String;
            final clen = int.tryParse(selected['contentLength']?.toString() ?? '') ?? 0;
            final mime = (selected['mimeType'] as String?) ?? '';

            return StreamAudioResult(
              streamUrl: streamUrl,
              contentLength: clen,
              container: mime.contains('mp4') ? 'm4a' : 'webm',
              userAgent: _visionUserAgent,
            );
          }
        }
      } catch (e) {
        print('InnerTube VISIONOS error ($videoId, attempt $attempt): $e');
      }
    }

    // 2. Respaldo: youtube_explode_dart sin requireWatchPage (evita rate-limit /sorry/ de Google)
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final manifest = await sharedYt.videos.streamsClient
            .getManifest(videoId, requireWatchPage: attempt > 0)
            .timeout(const Duration(seconds: 10));
        final audioStreams = manifest.audioOnly.toList();
        if (audioStreams.isNotEmpty) {
          final mp4Streams = audioStreams.where((s) => s.container == StreamContainer.mp4).toList();
          final pool = mp4Streams.isNotEmpty ? mp4Streams : audioStreams;
          pool.sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
          final stream = pool.first;

          return StreamAudioResult(
            streamUrl: stream.url.toString(),
            contentLength: stream.size.totalBytes,
            container: stream.container.name,
            userAgent: _userAgent,
          );
        }
      } catch (e) {
        print('YouTubeExplode manifest error ($videoId, attempt $attempt): $e');
        resetSharedYt();
      }
    }

    // 3. Respaldo final: instancias Invidious
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
                final aBitrate = int.tryParse(a['bitrate']?.toString() ?? '999999') ?? 999999;
                final bBitrate = int.tryParse(b['bitrate']?.toString() ?? '999999') ?? 999999;
                return aBitrate.compareTo(bBitrate);
              });

              final selected = audioList.first;
              final url = selected['url'] as String;
              final clen = int.tryParse(selected['clen']?.toString() ?? '') ?? 0;
              final isMp4 = (selected['type'] as String).contains('mp4');

              return StreamAudioResult(
                streamUrl: url,
                contentLength: clen,
                container: isMp4 ? 'm4a' : 'webm',
                userAgent: _userAgent,
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

  /// Obtiene el archivo de reproducción temporal en caché (o de vibe_offline si ya fue descargado)
  static Future<File> getOrDownloadStreamAudio(String videoId) async {
    if (_activeDownloads.containsKey(videoId)) {
      return await _activeDownloads[videoId]!;
    }

    final future = _getOrDownloadInternal(videoId).timeout(const Duration(seconds: 35));
    _activeDownloads[videoId] = future;
    try {
      return await future;
    } finally {
      _activeDownloads.remove(videoId);
    }
  }

  static Future<File> _getOrDownloadInternal(String videoId) async {
    // 1. Si ya fue descargada en vibe_offline, usar ese archivo directamente
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final offlineDir = Directory(path.join(docDir.path, 'vibe_offline'));
      if (await offlineDir.exists()) {
        final entities = offlineDir.listSync(recursive: false);
        for (final entity in entities) {
          if (entity is File && path.basename(entity.path).contains(videoId)) {
            if (await entity.length() > 25000) {
              return entity;
            }
          }
        }
      }
    } catch (_) {}

    // 2. Para reproducción en streaming sin descargar a la biblioteca, usar directorio temporal
    // del sistema y limpiar buffers anteriores para no acumular peso en la app
    final tempDir = await getTemporaryDirectory();
    final streamsDir = Directory(path.join(tempDir.path, 'vibe_stream_temp'));
    if (!await streamsDir.exists()) {
      await streamsDir.create(recursive: true);
    }

    final file = File(path.join(streamsDir.path, 'stream_$videoId.m4a'));
    if (await file.exists()) {
      final len = await file.length();
      if (len > 25000) {
        return file;
      }
      try {
        await file.delete();
      } catch (_) {}
    }

    // Limpiar buffers temporales viejos dejando máximo 2 pistas recientes en caché temporal
    try {
      final existing = streamsDir
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path != file.path)
          .toList();
      if (existing.length >= 2) {
        existing.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        for (int i = 0; i <= existing.length - 2; i++) {
          try {
            await existing[i].delete();
          } catch (_) {}
        }
      }
    } catch (_) {}

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
    final clen = meta.contentLength > 0
        ? meta.contentLength
        : await _probeContentLength(meta.streamUrl, meta.userAgent);

    // Intento 1: Descarga directa completa en una sola petición (ideal para VISIONOS hasta 15 MB)
    if (clen > 0 && clen <= 15 * 1024 * 1024) {
      try {
        final r = await http.get(
          Uri.parse(meta.streamUrl),
          headers: {
            'User-Agent': meta.userAgent,
            'Range': 'bytes=0-${clen - 1}',
            'Accept': '*/*',
          },
        ).timeout(const Duration(seconds: 20));

        if ((r.statusCode == 200 || r.statusCode == 206) && r.bodyBytes.length >= 50000) {
          await tempFile.writeAsBytes(r.bodyBytes, flush: true);
          success = true;
        }
      } catch (e) {
        print('Single-request download fallback ($e)');
      }
    }

    // Intento 2: Descarga por bloques controlados
    if (!success && clen > 0) {
      try {
        const chunkSize = 512 * 1024; // 512 KB
        final numChunks = (clen / chunkSize).ceil();
        final chunks = List<List<int>?>.filled(numChunks, null);

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
                'User-Agent': meta.userAgent,
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

    // Intento 3 (Fallback): Descarga continua vía HttpClient
    if (!success) {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      client.userAgent = meta.userAgent;
      try {
        final req = await client.getUrl(Uri.parse(meta.streamUrl)).timeout(const Duration(seconds: 10));
        if (clen > 0) {
          req.headers.set('Range', 'bytes=0-${clen - 1}');
        }
        final resp = await req.close().timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200 || resp.statusCode == 206) {
          final sink = tempFile.openWrite();
          try {
            await resp.pipe(sink).timeout(const Duration(seconds: 25));
            success = true;
          } finally {
            try {
              await sink.close();
            } catch (_) {}
          }
        } else {
          throw Exception('HTTP ${resp.statusCode}');
        }
      } catch (e) {
        print('Sequential stream error: $e');
      } finally {
        client.close(force: true);
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

  static Future<int> _probeContentLength(String url, String userAgent) async {
    try {
      final res = await http.head(
        Uri.parse(url),
        headers: {'User-Agent': userAgent},
      ).timeout(const Duration(seconds: 4));
      return int.tryParse(res.headers['content-length'] ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
