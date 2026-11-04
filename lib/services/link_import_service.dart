import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song_model.dart';
import 'ai_tagger_service.dart';

enum LinkPlatform { youtube, spotify }

class ParsedLink {
  final LinkPlatform platform;
  final String id;
  final String url;
  const ParsedLink(this.platform, this.id, this.url);
}

/// Vista previa de la canción antes de agregarla a la biblioteca
class ImportPreview {
  final String title;
  final String artist;
  final String album;
  final String? coverUrl;
  final Duration duration;
  final String youtubeId;
  final String sourceUrl;
  final LinkPlatform platform;
  final String? genre;
  final String? year;

  const ImportPreview({
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.duration,
    required this.youtubeId,
    required this.sourceUrl,
    required this.platform,
    this.genre,
    this.year,
  });

  String get songId => 'yt_$youtubeId';
}

/// Convierte un enlace de YouTube o Spotify en una canción en streaming con todos sus metadatos.
///
/// Spotify no permite transmitir su audio fuera de su app, así que de Spotify se toman
/// los metadatos (título, artista, carátula, duración) y el audio se busca en YouTube.
class LinkImportService {
  static const _userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static final _spotifyTrack = RegExp(r'(?:open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?track/|spotify:track:)([A-Za-z0-9]{22})');
  static final _spotifyShort = RegExp(r'(?:spotify\.link|spotify\.app\.link)/[A-Za-z0-9]+');
  static final _spotifyOther = RegExp(r'open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?(album|playlist|artist|episode|show)/');

  /// Detecta la plataforma y el ID dentro del texto pegado
  static ParsedLink? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final sp = _spotifyTrack.firstMatch(text);
    if (sp != null) {
      return ParsedLink(LinkPlatform.spotify, sp.group(1)!, 'https://open.spotify.com/track/${sp.group(1)}');
    }

    final urlMatch = RegExp(r'https?://\S+').firstMatch(text);
    final candidate = urlMatch?.group(0) ?? text;
    final ytId = VideoId.parseVideoId(candidate);
    if (ytId != null) {
      return ParsedLink(LinkPlatform.youtube, ytId, 'https://www.youtube.com/watch?v=$ytId');
    }
    return null;
  }

  /// Resuelve el enlace a una vista previa con metadatos completos
  static Future<ImportPreview> resolve(String input) async {
    var parsed = parse(input);

    // Enlaces cortos de compartir de Spotify (spotify.link/xxxx)
    if (parsed == null && _spotifyShort.hasMatch(input)) {
      final expanded = await _expandShortLink('https://${_spotifyShort.firstMatch(input)!.group(0)}');
      if (expanded != null) parsed = parse(expanded);
    }

    if (parsed == null) {
      if (_spotifyOther.hasMatch(input)) {
        throw const FormatException('Por ahora solo se pueden agregar canciones individuales de Spotify (no álbumes ni playlists).');
      }
      throw const FormatException('El enlace no es de YouTube ni de Spotify.');
    }

    return parsed.platform == LinkPlatform.youtube ? _resolveYouTube(parsed) : _resolveSpotify(parsed);
  }

  /// Convierte la vista previa en una canción de la biblioteca (descarga la carátula para uso sin conexión)
  static Future<Song> toSong(ImportPreview p) async {
    String? localCover;
    if (p.coverUrl != null) {
      localCover = await AITaggerService.downloadAndSaveCover(p.coverUrl!, p.songId);
    }
    return Song(
      id: p.songId,
      title: p.title,
      artist: p.artist,
      album: p.album,
      coverUrl: p.coverUrl,
      localCoverPath: localCover,
      duration: p.duration,
      genre: p.genre,
      year: p.year,
      youtubeId: p.youtubeId,
      sourceUrl: p.sourceUrl,
      source: p.platform == LinkPlatform.spotify ? 'spotify' : 'youtube',
      isDownloaded: false,
    );
  }

  // ---------------------------------------------------------------------------
  // YouTube
  // ---------------------------------------------------------------------------

  static Future<ImportPreview> _resolveYouTube(ParsedLink link) async {
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(link.id).timeout(const Duration(seconds: 15));
      final guess = _splitArtistTitle(video.title, video.author);
      final duration = video.duration ?? Duration.zero;

      // Completar álbum, género, año y carátula cuadrada en alta resolución
      final meta = await _lookupItunes(guess.artist, guess.title, duration);

      return ImportPreview(
        title: meta?.title ?? guess.title,
        artist: meta?.artist ?? guess.artist,
        album: meta?.album ?? 'YouTube',
        coverUrl: meta?.coverUrl ?? video.thumbnails.highResUrl,
        duration: (meta != null && meta.duration > Duration.zero) ? meta.duration : duration,
        youtubeId: video.id.value,
        sourceUrl: link.url,
        platform: LinkPlatform.youtube,
        genre: meta?.genre,
        year: meta?.year ?? video.uploadDate?.year.toString(),
      );
    } finally {
      yt.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Spotify
  // ---------------------------------------------------------------------------

  static Future<ImportPreview> _resolveSpotify(ParsedLink link) async {
    final track = await _fetchSpotifyTrack(link.id);
    if (track == null) {
      throw Exception('No se pudo leer la información de la canción en Spotify.');
    }

    final videoId = await _findOnYouTube(track.artist, track.title, track.duration);
    if (videoId == null) {
      throw Exception('No se encontró el audio de "${track.title}" en YouTube.');
    }

    final meta = await _lookupItunes(track.artist, track.title, track.duration);

    return ImportPreview(
      title: track.title,
      artist: track.artist,
      album: track.album ?? meta?.album ?? 'Spotify',
      coverUrl: track.coverUrl ?? meta?.coverUrl,
      duration: track.duration > Duration.zero ? track.duration : (meta?.duration ?? Duration.zero),
      youtubeId: videoId,
      sourceUrl: link.url,
      platform: LinkPlatform.spotify,
      genre: meta?.genre,
      year: track.year ?? meta?.year,
    );
  }

  static Future<_TrackMeta?> _fetchSpotifyTrack(String id) async {
    // 1) Página pública del reproductor embebido: trae título, artistas, duración y carátula
    try {
      final res = await http.get(
        Uri.parse('https://open.spotify.com/embed/track/$id'),
        headers: {'User-Agent': _userAgent, 'Accept-Language': 'es-MX,es;q=0.9,en;q=0.8'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final m = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.+?)</script>', dotAll: true).firstMatch(res.body);
        if (m != null) {
          final data = json.decode(m.group(1)!);
          final entity = _findTrackEntity(data);
          if (entity != null) {
            final title = (entity['name'] ?? entity['title']) as String?;
            final artists = (entity['artists'] as List?)
                    ?.map((a) => (a is Map ? a['name'] : null) as String?)
                    .whereType<String>()
                    .toList() ??
                [];
            final subtitle = entity['subtitle'] as String?;
            final artist = artists.isNotEmpty ? artists.join(', ') : (subtitle ?? '');

            final durationMs = (entity['duration'] is int)
                ? entity['duration'] as int
                : (entity['duration'] is Map ? (entity['duration']['totalMilliseconds'] as int? ?? 0) : 0);

            String? cover;
            final sources = (entity['coverArt']?['sources'] ?? entity['visualIdentity']?['image']) as List?;
            if (sources != null && sources.isNotEmpty) {
              final sorted = sources.whereType<Map>().toList()
                ..sort((a, b) => ((b['width'] ?? b['maxWidth'] ?? 0) as num).compareTo((a['width'] ?? a['maxWidth'] ?? 0) as num));
              cover = sorted.first['url'] as String?;
            }

            final release = entity['releaseDate']?['isoString'] as String?;

            if (title != null && title.isNotEmpty) {
              return _TrackMeta(
                title: title,
                artist: artist,
                album: null,
                coverUrl: cover,
                duration: Duration(milliseconds: durationMs),
                year: (release != null && release.length >= 4) ? release.substring(0, 4) : null,
              );
            }
          }
        }
      }
    } catch (e) {
      print('Spotify embed error: $e');
    }

    // 2) Respaldo: oEmbed oficial (solo título y carátula) + búsqueda en iTunes para el artista
    try {
      final res = await http.get(
        Uri.parse('https://open.spotify.com/oembed?url=${Uri.encodeComponent('https://open.spotify.com/track/$id')}'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final title = data['title'] as String?;
        if (title != null) {
          final meta = await _lookupItunes('', title, Duration.zero);
          return _TrackMeta(
            title: title,
            artist: meta?.artist ?? '',
            album: meta?.album,
            coverUrl: data['thumbnail_url'] as String? ?? meta?.coverUrl,
            duration: meta?.duration ?? Duration.zero,
            year: meta?.year,
          );
        }
      }
    } catch (e) {
      print('Spotify oEmbed error: $e');
    }
    return null;
  }

  /// Busca recursivamente el objeto de la pista dentro del JSON de la página
  static Map<String, dynamic>? _findTrackEntity(dynamic node) {
    if (node is Map<String, dynamic>) {
      if ((node['type'] == 'track' || node['uri']?.toString().startsWith('spotify:track:') == true) &&
          (node['name'] != null || node['title'] != null) &&
          (node['artists'] != null || node['subtitle'] != null)) {
        return node;
      }
      for (final v in node.values) {
        final found = _findTrackEntity(v);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final v in node) {
        final found = _findTrackEntity(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Future<String?> _expandShortLink(String url) async {
    final client = HttpClient();
    try {
      var current = Uri.parse(url);
      for (var i = 0; i < 5; i++) {
        final req = await client.getUrl(current);
        req.followRedirects = false;
        req.headers.set('User-Agent', _userAgent);
        final res = await req.close();
        final location = res.headers.value(HttpHeaders.locationHeader);
        if (location != null) {
          await res.drain<void>();
          current = current.resolve(location);
          if (_spotifyTrack.hasMatch(current.toString())) return current.toString();
          continue;
        }
        final body = await res.transform(utf8.decoder).join();
        final m = _spotifyTrack.firstMatch(body);
        return m != null ? 'https://open.spotify.com/track/${m.group(1)}' : null;
      }
    } catch (e) {
      print('Short link error: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// Busca en YouTube el audio que mejor coincide con la pista (por título, artista y duración)
  static Future<String?> _findOnYouTube(String artist, String title, Duration duration) async {
    final yt = YoutubeExplode();
    try {
      final results = await yt.search.search('$artist $title audio').timeout(const Duration(seconds: 15));
      if (results.isEmpty) return null;

      final wantTitle = _normalize(title);
      final wantArtist = _normalize(artist.split(',').first);
      final penalized = ['live', 'en vivo', 'cover', 'karaoke', 'remix', 'sped up', 'slowed', '8d', 'instrumental', 'reaction', 'tutorial', 'nightcore']
          .where((w) => !wantTitle.contains(w))
          .toList();

      Video? best;
      var bestScore = -1e9;
      for (final v in results.take(12)) {
        final vt = _normalize(v.title);
        final va = _normalize(v.author);
        var score = 0.0;

        if (vt.contains(wantTitle)) score += 40;
        for (final w in wantTitle.split(' ')) {
          if (w.length > 2 && vt.contains(w)) score += 4;
        }
        if (wantArtist.isNotEmpty && (va.contains(wantArtist) || vt.contains(wantArtist))) score += 25;
        if (v.author.endsWith(' - Topic')) score += 20;
        if (vt.contains('official audio') || vt.contains('audio oficial')) score += 10;
        for (final w in penalized) {
          if (vt.contains(w)) score -= 35;
        }

        final vd = v.duration;
        if (duration > Duration.zero && vd != null) {
          final diff = (vd.inSeconds - duration.inSeconds).abs();
          if (diff <= 3) {
            score += 30;
          } else if (diff <= 10) {
            score += 15;
          } else {
            score -= diff.clamp(0, 120) / 2;
          }
        }

        if (score > bestScore) {
          bestScore = score;
          best = v;
        }
      }
      return best?.id.value;
    } catch (e) {
      print('YouTube match error: $e');
      return null;
    } finally {
      yt.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Metadatos (iTunes Search API, pública y sin clave)
  // ---------------------------------------------------------------------------

  static Future<_TrackMeta?> _lookupItunes(String artist, String title, Duration duration) async {
    try {
      final term = [artist, title].where((s) => s.trim().isNotEmpty).join(' ');
      if (term.isEmpty) return null;
      final res = await http
          .get(Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(term)}&entity=song&limit=10'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final results = (json.decode(res.body)['results'] as List?) ?? [];
      final wantTitle = _normalize(title);
      final wantArtist = _normalize(artist);

      for (final r in results) {
        final rt = _normalize(r['trackName'] as String? ?? '');
        final ra = _normalize(r['artistName'] as String? ?? '');
        final titleOk = rt.isNotEmpty && (wantTitle.contains(rt) || rt.contains(wantTitle));
        final artistOk = wantArtist.isEmpty || ra.contains(wantArtist) || wantArtist.contains(ra);
        final ms = r['trackTimeMillis'] as int?;
        final durationOk = duration == Duration.zero || ms == null || (ms ~/ 1000 - duration.inSeconds).abs() <= 30;

        if (titleOk && artistOk && durationOk) {
          final release = r['releaseDate'] as String?;
          return _TrackMeta(
            title: r['trackName'] as String,
            artist: r['artistName'] as String,
            album: r['collectionName'] as String?,
            coverUrl: (r['artworkUrl100'] as String?)?.replaceAll('100x100bb', '600x600bb'),
            duration: Duration(milliseconds: ms ?? 0),
            genre: r['primaryGenreName'] as String?,
            year: (release != null && release.length >= 4) ? release.substring(0, 4) : null,
          );
        }
      }
    } catch (e) {
      print('iTunes lookup error: $e');
    }
    return null;
  }

  /// Separa "Artista - Canción (Official Video)" en artista y título limpios
  static ({String artist, String title}) _splitArtistTitle(String rawTitle, String author) {
    var title = rawTitle
        .replaceAll(RegExp(r'\((?:[^)]*(?:official|oficial|video|audio|lyric|letra|visualizer|hd|4k|mv)[^)]*)\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[(?:[^\]]*(?:official|oficial|video|audio|lyric|letra|visualizer|hd|4k|mv)[^\]]*)\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    var artist = author.replaceAll(RegExp(r'\s*-\s*Topic$'), '').replaceAll(RegExp(r'VEVO$', caseSensitive: false), '').trim();

    final dash = RegExp(r'\s[-–—|]\s').firstMatch(title);
    if (dash != null) {
      artist = title.substring(0, dash.start).trim();
      title = title.substring(dash.end).trim();
    }
    return (artist: artist, title: title);
  }

  static String _normalize(String s) {
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    var out = s.toLowerCase();
    accents.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAll(RegExp(r'\((feat|ft)[^)]*\)'), '');
    out = out.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _TrackMeta {
  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final Duration duration;
  final String? genre;
  final String? year;

  _TrackMeta({
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.duration,
    this.genre,
    this.year,
  });
}
