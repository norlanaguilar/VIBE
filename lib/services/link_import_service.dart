import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song_model.dart';
import 'ai_tagger_service.dart';
import 'youtube_stream_resolver.dart';

enum LinkPlatform { youtube, spotify }

enum LinkType { track, playlist, album }

class ParsedLink {
  final LinkPlatform platform;
  final LinkType type;
  final String id;
  final String url;

  const ParsedLink(
    this.platform,
    this.id,
    this.url, {
    this.type = LinkType.track,
  });

  bool get isPlaylist => type == LinkType.playlist || type == LinkType.album;
}

/// Vista previa de la canción individual antes de agregarla a la biblioteca
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

/// Elemento de una pista dentro de una playlist o álbum
class PlaylistTrackPreview {
  final String title;
  final String artist;
  final String? album;
  final Duration duration;
  final String? youtubeId;
  final String? coverUrl;
  final String? sourceUrl;

  const PlaylistTrackPreview({
    required this.title,
    required this.artist,
    this.album,
    this.duration = Duration.zero,
    this.youtubeId,
    this.coverUrl,
    this.sourceUrl,
  });

  String get songId => youtubeId != null
      ? 'yt_$youtubeId'
      : 'sp_${title.hashCode.abs()}_${artist.hashCode.abs()}';
}

/// Vista previa de una playlist o álbum completo
class PlaylistPreview {
  final String title;
  final String author;
  final String? coverUrl;
  final LinkPlatform platform;
  final LinkType type;
  final String sourceUrl;
  final List<PlaylistTrackPreview> tracks;

  const PlaylistPreview({
    required this.title,
    required this.author,
    this.coverUrl,
    required this.platform,
    required this.type,
    required this.sourceUrl,
    required this.tracks,
  });

  Duration get totalDuration =>
      tracks.fold(Duration.zero, (prev, t) => prev + t.duration);
}

/// Resultado unificado de resolución de un enlace o búsqueda de canciones
class ImportResult {
  final ImportPreview? singleTrack;
  final PlaylistPreview? playlist;
  final List<ImportPreview>? searchResults;

  const ImportResult.track(ImportPreview this.singleTrack)
      : playlist = null,
        searchResults = null;
  const ImportResult.playlist(PlaylistPreview this.playlist)
      : singleTrack = null,
        searchResults = null;
  const ImportResult.searchResults(List<ImportPreview> this.searchResults)
      : singleTrack = null,
        playlist = null;

  bool get isPlaylist => playlist != null;
  bool get isSingleTrack => singleTrack != null;
  bool get isSearchResults => searchResults != null;
}

/// Convierte un enlace de YouTube o Spotify (canción individual o playlist/álbum)
/// en canciones en streaming con todos sus metadatos.
class LinkImportService {
  static const _userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

  static final _spotifyTrack = RegExp(r'(?:open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?track/|spotify:track:)([A-Za-z0-9]{22})');
  static final _spotifyPlaylist = RegExp(r'(?:open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?playlist/|spotify:playlist:)([A-Za-z0-9]{22})');
  static final _spotifyAlbum = RegExp(r'(?:open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?album/|spotify:album:)([A-Za-z0-9]{22})');
  static final _spotifyShort = RegExp(r'(?:spotify\.link|spotify\.app\.link)/[A-Za-z0-9]+');
  static final _youtubePlaylist = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)');

  /// Detecta la plataforma, el tipo y el ID dentro del texto pegado
  static ParsedLink? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    // Spotify playlist
    final spPlaylist = _spotifyPlaylist.firstMatch(text);
    if (spPlaylist != null) {
      return ParsedLink(
        LinkPlatform.spotify,
        spPlaylist.group(1)!,
        'https://open.spotify.com/playlist/${spPlaylist.group(1)}',
        type: LinkType.playlist,
      );
    }

    // Spotify álbum
    final spAlbum = _spotifyAlbum.firstMatch(text);
    if (spAlbum != null) {
      return ParsedLink(
        LinkPlatform.spotify,
        spAlbum.group(1)!,
        'https://open.spotify.com/album/${spAlbum.group(1)}',
        type: LinkType.album,
      );
    }

    // Spotify canción individual
    final spTrack = _spotifyTrack.firstMatch(text);
    if (spTrack != null) {
      return ParsedLink(
        LinkPlatform.spotify,
        spTrack.group(1)!,
        'https://open.spotify.com/track/${spTrack.group(1)}',
        type: LinkType.track,
      );
    }

    final urlMatch = RegExp(r'(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com|youtu\.be|open\.spotify\.com|spotify\.link)\S+', caseSensitive: false).firstMatch(text);
    final candidate = urlMatch?.group(0) ?? text;

    final isYouTubeUrl = RegExp(r'(?:youtube\.com|youtu\.be)', caseSensitive: false).hasMatch(candidate);
    if (isYouTubeUrl) {
      String? ytVideoId;
      final vParam = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})').firstMatch(candidate);
      final shortPath = RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})').firstMatch(candidate);
      final embedPath = RegExp(r'youtube\.com/(?:shorts|embed|live|v)/([A-Za-z0-9_-]{11})').firstMatch(candidate);
      ytVideoId = vParam?.group(1) ?? shortPath?.group(1) ?? embedPath?.group(1);
      if (ytVideoId == null && !candidate.contains('/playlist')) {
        ytVideoId = VideoId.parseVideoId(candidate);
      }

      final ytListMatch = _youtubePlaylist.firstMatch(candidate);
      final listId = ytListMatch?.group(1);

      // Es playlist únicamente si es un enlace /playlist explícito o no apunta a un video individual
      if (listId != null &&
          !listId.startsWith('RD') &&
          (candidate.contains('/playlist') || ytVideoId == null)) {
        return ParsedLink(
          LinkPlatform.youtube,
          listId,
          'https://www.youtube.com/playlist?list=$listId',
          type: LinkType.playlist,
        );
      }

      if (ytVideoId != null && ytVideoId.isNotEmpty) {
        return ParsedLink(
          LinkPlatform.youtube,
          ytVideoId,
          'https://www.youtube.com/watch?v=$ytVideoId',
          type: LinkType.track,
        );
      }
    }

    return null;
  }

  /// Resuelve el enlace (canción o playlist de YouTube/Spotify) o busca por nombre de canción en YouTube
  static Future<ImportResult> resolve(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Escribe el nombre de una canción o pega un enlace.');
    }

    var parsed = parse(trimmed);

    // Enlaces cortos de compartir de Spotify (spotify.link/xxxx)
    if (parsed == null && _spotifyShort.hasMatch(trimmed)) {
      final expanded = await _expandShortLink('https://${_spotifyShort.firstMatch(trimmed)!.group(0)}');
      if (expanded != null) parsed = parse(expanded);
    }

    // Si no es una URL, buscar directamente opciones de la canción oficial en YouTube
    if (parsed == null) {
      final looksLikeUnsupportedUrl = RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed);
      if (looksLikeUnsupportedUrl) {
        throw const FormatException('El enlace no es válido. Usa un enlace de YouTube o Spotify.');
      }
      final results = await searchYouTubeSongs(trimmed);
      if (results.isEmpty) {
        throw Exception('No se encontraron canciones oficiales para "$trimmed".');
      }
      return ImportResult.searchResults(results);
    }

    if (parsed.isPlaylist) {
      final playlist = parsed.platform == LinkPlatform.youtube
          ? await _resolveYouTubePlaylist(parsed)
          : await _resolveSpotifyPlaylistOrAlbum(parsed);
      return ImportResult.playlist(playlist);
    } else {
      final track = parsed.platform == LinkPlatform.youtube
          ? await _resolveYouTube(parsed)
          : await _resolveSpotify(parsed);
      return ImportResult.track(track);
    }
  }

  /// Convierte la vista previa individual en una canción de la biblioteca
  static Future<Song> toSong(ImportPreview p) async {
    String? localCover;
    if (p.coverUrl != null && p.coverUrl!.isNotEmpty) {
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

  /// Convierte una playlist completa en canciones de la biblioteca
  static Future<List<Song>> playlistToSongs(PlaylistPreview p) async {
    final List<Song> result = [];
    String? sharedCover;
    // Únicamente los álbumes comparten la misma carátula para todas las pistas
    if (p.type == LinkType.album && p.coverUrl != null && p.coverUrl!.isNotEmpty) {
      try {
        sharedCover = await AITaggerService.downloadAndSaveCover(
          p.coverUrl!,
          'pl_${p.title.hashCode.abs()}',
        );
      } catch (e) {
        print('Error downloading album cover: $e');
      }
    }

    final baseTime = DateTime.now();
    for (int i = 0; i < p.tracks.length; i++) {
      final t = p.tracks[i];
      result.add(
        Song(
          id: t.songId,
          title: t.title,
          artist: t.artist,
          album: t.album ?? p.title,
          coverUrl: t.coverUrl,
          localCoverPath: p.type == LinkType.album ? sharedCover : null,
          duration: t.duration,
          youtubeId: t.youtubeId,
          sourceUrl: t.sourceUrl ?? p.sourceUrl,
          source: p.platform == LinkPlatform.spotify ? 'spotify' : 'youtube',
          isDownloaded: false,
          addedAt: baseTime.subtract(Duration(milliseconds: i)),
        ),
      );
    }
    return result;
  }

  /// Obtiene la carátula oficial individual de una canción de Spotify o mediante iTunes
  static Future<String?> fetchTrackCover({
    required String artist,
    required String title,
    String? spotifyTrackId,
  }) async {
    if (spotifyTrackId != null && spotifyTrackId.isNotEmpty) {
      try {
        final res = await http.get(
          Uri.parse('https://open.spotify.com/oembed?url=${Uri.encodeComponent('https://open.spotify.com/track/$spotifyTrackId')}'),
          headers: {'User-Agent': _userAgent},
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final thumb = data['thumbnail_url'] as String?;
          if (thumb != null && thumb.isNotEmpty) {
            return thumb.replaceAll('ab67616d00001e02', 'ab67616d0000b273');
          }
        }
      } catch (_) {}
    }

    // Respaldo iTunes
    try {
      final meta = await _lookupItunes(artist, title, Duration.zero);
      if (meta?.coverUrl != null) return meta!.coverUrl;
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // YouTube Video Individual
  // ---------------------------------------------------------------------------

  static Future<ImportPreview> _resolveYouTube(ParsedLink link) async {
    String rawTitle = '';
    String rawAuthor = '';
    Duration duration = Duration.zero;
    String? uploadYear;

    // 1. Obtener detalles directamente desde InnerTube player API (rápido y sin bloqueos)
    try {
      final visitorData = await YouTubeStreamResolver.getVisitorData();
      final res = await http
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent':
                  'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
              'X-YouTube-Client-Name': '101',
              'X-YouTube-Client-Version': '1.02',
              if (visitorData != null) 'X-Goog-Visitor-Id': visitorData,
            },
            body: json.encode({
              'videoId': link.id,
              'context': {
                'client': {
                  'clientName': 'VISIONOS',
                  'clientVersion': '1.02',
                  'deviceMake': 'Apple',
                  'deviceModel': 'RealityDevice17,1',
                  'osName': 'visionOS',
                  'osVersion': '26.5.23O471',
                  'hl': 'es',
                  'gl': 'MX',
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
        final details = data['videoDetails'] as Map<String, dynamic>?;
        if (details != null) {
          rawTitle = (details['title'] as String?)?.trim() ?? '';
          rawAuthor = (details['author'] as String?)?.trim() ?? '';
          final lenSec = int.tryParse(details['lengthSeconds']?.toString() ?? '0') ?? 0;
          if (lenSec > 0) {
            duration = Duration(seconds: lenSec);
          }
        }
        final micro = data['microformat']?['playerMicroformatRenderer'] as Map<String, dynamic>?;
        final publishDate = micro?['publishDate'] as String?;
        if (publishDate != null && publishDate.length >= 4) {
          uploadYear = publishDate.substring(0, 4);
        }
      }
    } catch (_) {}

    // 2. Respaldo con YouTube oEmbed oficial si faltó el título
    if (rawTitle.isEmpty) {
      try {
        final oembedUrl = Uri.parse(
          'https://www.youtube.com/oembed?url=${Uri.encodeComponent('https://www.youtube.com/watch?v=${link.id}')}&format=json',
        );
        final res = await http.get(oembedUrl).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          rawTitle = (data['title'] as String?)?.trim() ?? '';
          rawAuthor = (data['author_name'] as String?)?.trim() ?? '';
        }
      } catch (_) {}
    }

    // 3. Respaldo final con YoutubeExplode
    if (rawTitle.isEmpty) {
      try {
        final video = await YouTubeStreamResolver.sharedYt.videos.get(link.id).timeout(const Duration(seconds: 12));
        rawTitle = video.title;
        rawAuthor = video.author;
        duration = video.duration ?? Duration.zero;
        uploadYear = video.uploadDate?.year.toString();
      } catch (e) {
        YouTubeStreamResolver.resetSharedYt();
        throw Exception('No se pudo obtener la información del enlace de YouTube.');
      }
    }

    final guess = _splitArtistTitle(rawTitle, rawAuthor);
    final meta = await _lookupItunes(guess.artist, guess.title, duration);

    return ImportPreview(
      title: meta?.title ?? guess.title,
      artist: meta?.artist ?? (guess.artist.isNotEmpty ? guess.artist : 'YouTube'),
      album: meta?.album ?? 'YouTube',
      coverUrl: meta?.coverUrl ?? 'https://i.ytimg.com/vi/${link.id}/hqdefault.jpg',
      duration: duration > Duration.zero ? duration : (meta?.duration ?? Duration.zero),
      youtubeId: link.id,
      sourceUrl: link.url,
      platform: LinkPlatform.youtube,
      genre: meta?.genre,
      year: meta?.year ?? uploadYear,
    );
  }

  // ---------------------------------------------------------------------------
  // YouTube Playlist
  // ---------------------------------------------------------------------------

  static Future<PlaylistPreview> _resolveYouTubePlaylist(ParsedLink link) async {
    final playlistUrl = 'https://www.youtube.com/playlist?list=${link.id}';
    final res = await http.get(
      Uri.parse(playlistUrl),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'es-MX,es;q=0.9,en;q=0.8',
      },
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw Exception('No se pudo acceder a la playlist de YouTube (código ${res.statusCode}).');
    }

    final m = RegExp(r'var ytInitialData = ({.+?});</script>', dotAll: true).firstMatch(res.body);
    if (m == null) {
      throw Exception('No se pudo leer la información de la playlist de YouTube.');
    }

    final data = json.decode(m.group(1)!);
    final meta = data['metadata']?['playlistMetadataRenderer'];
    final title = (meta?['title'] as String?) ?? 'Playlist de YouTube';

    final header = data['header']?['playlistHeaderRenderer'];
    String author = '';
    if (header?['ownerText']?['runs'] is List && (header['ownerText']['runs'] as List).isNotEmpty) {
      author = (header['ownerText']['runs'][0]['text'] as String?) ?? '';
    }

    String? coverUrl;
    final twoCol = data['contents']?['twoColumnBrowseResultsRenderer'];
    final tabs = twoCol?['tabs'] as List?;
    final sectionList = tabs?[0]?['tabRenderer']?['content']?['sectionListRenderer'];
    final itemSection = (sectionList?['contents'] as List?)?[0]?['itemSectionRenderer'];
    final contents = (itemSection?['contents'] as List?) ?? [];

    final List<PlaylistTrackPreview> tracks = [];

    for (final item in contents) {
      if (item is! Map) continue;

      // Estructura 1: lockupViewModel
      final lockup = item['lockupViewModel'];
      if (lockup != null) {
        final videoId = lockup['contentId'] as String?;
        if (videoId == null || videoId.isEmpty) continue;

        final metadata = lockup['metadata']?['lockupMetadataViewModel'];
        final rawTitle = (metadata?['title']?['content'] as String?) ?? '';
        if (rawTitle.isEmpty) continue;

        final snippet = metadata?['metadata']?['contentMetadataViewModel'];
        final metadataRows = snippet?['metadataRows'] as List?;
        String videoArtist = '';
        if (metadataRows != null && metadataRows.isNotEmpty) {
          final parts = metadataRows[0]?['metadataParts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            videoArtist = (parts[0]?['text']?['content'] as String?) ?? '';
          }
        }

        final guess = _splitArtistTitle(rawTitle, videoArtist.isNotEmpty ? videoArtist : author);

        String? durText;
        final overlays = lockup['contentImage']?['thumbnailViewModel']?['overlays'] as List?;
        if (overlays != null) {
          for (final o in overlays) {
            final badges = o['thumbnailBottomOverlayViewModel']?['badges'] as List?;
            if (badges != null && badges.isNotEmpty) {
              durText = badges[0]?['thumbnailBadgeViewModel']?['text'] as String?;
              if (durText != null) break;
            }
          }
        }

        final duration = _parseClockDuration(durText);
        final trackCover = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        coverUrl ??= trackCover;

        tracks.add(
          PlaylistTrackPreview(
            title: guess.title,
            artist: guess.artist,
            album: title,
            duration: duration,
            youtubeId: videoId,
            coverUrl: trackCover,
            sourceUrl: 'https://www.youtube.com/watch?v=$videoId',
          ),
        );
        continue;
      }

      // Estructura 2: playlistVideoRenderer
      final pvr = item['playlistVideoRenderer'];
      if (pvr != null) {
        final videoId = pvr['videoId'] as String?;
        if (videoId == null || videoId.isEmpty) continue;

        String rawTitle = '';
        if (pvr['title']?['runs'] is List && (pvr['title']['runs'] as List).isNotEmpty) {
          rawTitle = pvr['title']['runs'][0]['text'] ?? '';
        } else if (pvr['title']?['simpleText'] != null) {
          rawTitle = pvr['title']['simpleText'];
        }
        if (rawTitle.isEmpty || rawTitle == '[Deleted video]' || rawTitle == '[Private video]') continue;

        String videoArtist = '';
        if (pvr['shortBylineText']?['runs'] is List && (pvr['shortBylineText']['runs'] as List).isNotEmpty) {
          videoArtist = pvr['shortBylineText']['runs'][0]['text'] ?? '';
        }

        final guess = _splitArtistTitle(rawTitle, videoArtist.isNotEmpty ? videoArtist : author);
        final durText = pvr['lengthText']?['simpleText'] as String?;
        final duration = _parseClockDuration(durText);
        final trackCover = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        coverUrl ??= trackCover;

        tracks.add(
          PlaylistTrackPreview(
            title: guess.title,
            artist: guess.artist,
            album: title,
            duration: duration,
            youtubeId: videoId,
            coverUrl: trackCover,
            sourceUrl: 'https://www.youtube.com/watch?v=$videoId',
          ),
        );
      }
    }

    if (tracks.isEmpty) {
      throw Exception('No se encontraron canciones disponibles en la playlist de YouTube.');
    }

    return PlaylistPreview(
      title: title,
      author: author.isNotEmpty ? author : 'YouTube',
      coverUrl: coverUrl,
      platform: LinkPlatform.youtube,
      type: LinkType.playlist,
      sourceUrl: link.url,
      tracks: tracks,
    );
  }

  // ---------------------------------------------------------------------------
  // Spotify Canción Individual
  // ---------------------------------------------------------------------------

  static Future<ImportPreview> _resolveSpotify(ParsedLink link) async {
    final track = await _fetchSpotifyTrack(link.id);
    if (track == null) {
      throw Exception('No se pudo leer la información de la canción en Spotify.');
    }

    final videoId = await findOnYouTube(track.artist, track.title, track.duration);
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

  // ---------------------------------------------------------------------------
  // Spotify Playlist o Álbum
  // ---------------------------------------------------------------------------

  static Future<PlaylistPreview> _resolveSpotifyPlaylistOrAlbum(ParsedLink link) async {
    final isAlbum = link.type == LinkType.album;
    final url = 'https://open.spotify.com/embed/${isAlbum ? 'album' : 'playlist'}/${link.id}';
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'es-MX,es;q=0.9,en;q=0.8',
      },
    ).timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) {
      throw Exception('No se pudo cargar el ${isAlbum ? 'álbum' : 'playlist'} de Spotify.');
    }

    final m = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.+?)</script>', dotAll: true).firstMatch(res.body);
    if (m == null) {
      throw Exception('Formato no reconocido en Spotify.');
    }

    final data = json.decode(m.group(1)!);
    final entity = data['props']?['pageProps']?['state']?['data']?['entity'] ??
        data['props']?['pageProps']?['state']?['data']?['playlist'] ??
        data['props']?['pageProps']?['state']?['data']?['album'];

    if (entity == null) {
      throw Exception('No se encontraron canciones en el enlace de Spotify.');
    }

    final title = (entity['name'] ?? entity['title'] ?? (isAlbum ? 'Álbum de Spotify' : 'Playlist de Spotify')) as String;

    String author = '';
    if (entity['owner'] != null && entity['owner']['name'] != null) {
      author = entity['owner']['name'] as String;
    } else if (entity['subtitle'] != null) {
      author = entity['subtitle'] as String;
    } else if (entity['artists'] is List && (entity['artists'] as List).isNotEmpty) {
      author = (entity['artists'] as List).map((a) => a['name']).whereType<String>().join(', ');
    }

    String? coverUrl;
    final coverArtSources = entity['coverArt']?['sources'] as List?;
    if (coverArtSources != null && coverArtSources.isNotEmpty) {
      coverUrl = coverArtSources[0]['url'] as String?;
    } else {
      final viImages = entity['visualIdentity']?['image'] as List?;
      if (viImages != null && viImages.isNotEmpty) {
        coverUrl = (viImages.last['url'] ?? viImages.first['url']) as String?;
      }
    }

    final rawTracks = (entity['trackList'] as List?) ?? [];
    final List<PlaylistTrackPreview> tracks = [];

    for (final t in rawTracks) {
      if (t is! Map) continue;
      final tTitle = (t['title'] ?? t['name']) as String?;
      if (tTitle == null || tTitle.isEmpty) continue;

      String tArtist = '';
      if (t['subtitle'] != null) {
        tArtist = t['subtitle'] as String;
      } else if (t['artists'] is List && (t['artists'] as List).isNotEmpty) {
        tArtist = (t['artists'] as List).map((a) => a['name']).whereType<String>().join(', ');
      }
      if (tArtist.isEmpty) tArtist = author;

      final ms = (t['duration'] is int)
          ? t['duration'] as int
          : (t['duration'] is Map ? (t['duration']['totalMilliseconds'] as int? ?? 0) : 0);

      final uri = t['uri'] as String? ?? '';
      final spotifyTrackId = uri.startsWith('spotify:track:') ? uri.replaceFirst('spotify:track:', '') : null;

      tracks.add(
        PlaylistTrackPreview(
          title: tTitle,
          artist: tArtist,
          album: isAlbum ? title : null,
          duration: Duration(milliseconds: ms),
          coverUrl: isAlbum ? coverUrl : null,
          sourceUrl: spotifyTrackId != null ? 'https://open.spotify.com/track/$spotifyTrackId' : link.url,
        ),
      );
    }

    if (tracks.isEmpty) {
      throw Exception('La playlist o álbum no contiene canciones disponibles.');
    }

    return PlaylistPreview(
      title: title,
      author: author.isNotEmpty ? author : (isAlbum ? 'Varios artistas' : 'Spotify'),
      coverUrl: coverUrl,
      platform: LinkPlatform.spotify,
      type: link.type,
      sourceUrl: link.url,
      tracks: tracks,
    );
  }

  static Future<_TrackMeta?> _fetchSpotifyTrack(String id) async {
    // 1) Página pública del reproductor embebido
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

    // 2) Respaldo: oEmbed oficial + búsqueda en iTunes
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
          if (parse(current.toString()) != null) return current.toString();
          continue;
        }
        final body = await res.transform(utf8.decoder).join();
        final m = _spotifyTrack.firstMatch(body) ??
            _spotifyPlaylist.firstMatch(body) ??
            _spotifyAlbum.firstMatch(body);
        return m != null ? m.group(0) : null;
      }
    } catch (e) {
      print('Short link error: $e');
    } finally {
      client.close();
    }
    return null;
  }

  /// Busca en YouTube el video que mejor coincide con la pista
  /// Utiliza la API JSON nativa InnerTube (`youtubei/v1/search`) para evitar parseo HTML pesado en el hilo principal
  /// y prevenir fallos del parser de `youtube_explode_dart`.
  static Future<String?> findOnYouTube(String artist, String title, Duration duration) async {
    final cleanTitle = title
        .replaceAll(RegExp(r'\s*-\s*\d{4}\s*Remaster(?:ed)?.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\((?:[^)]*Remaster[^)]*)\)', caseSensitive: false), '')
        .trim();
    final effectiveTitle = cleanTitle.isNotEmpty ? cleanTitle : title;

    final wantTitle = _normalize(effectiveTitle);
    final wantArtist = _normalize(artist.split(',').first);
    final penalized = [
      'live',
      'en vivo',
      'cover',
      'karaoke',
      'remix',
      'sped up',
      'slowed',
      '8d',
      'instrumental',
      'reaction',
      'tutorial',
      'nightcore'
    ].where((w) => !wantTitle.contains(w)).toList();

    double scoreCandidate(String rawTitle, String rawAuthor, Duration vd) {
      final vt = _normalize(rawTitle);
      final va = _normalize(rawAuthor);
      var score = 0.0;

      if (vt.contains(wantTitle)) score += 40;
      for (final w in wantTitle.split(' ')) {
        if (w.length > 2 && vt.contains(w)) score += 4;
      }
      if (wantArtist.isNotEmpty && (va.contains(wantArtist) || vt.contains(wantArtist))) score += 25;
      if (rawAuthor.endsWith(' - Topic')) score += 20;
      if (vt.contains('official audio') || vt.contains('audio oficial')) score += 10;
      for (final w in penalized) {
        if (vt.contains(w)) score -= 35;
      }

      if (duration > Duration.zero && vd > Duration.zero) {
        final diff = (vd.inSeconds - duration.inSeconds).abs();
        if (diff <= 3) {
          score += 30;
        } else if (diff <= 10) {
          score += 15;
        } else {
          score -= diff.clamp(0, 120) / 2;
        }
      }
      return score;
    }

    // 1. Prioridad máxima: Búsqueda JSON directa en InnerTube (rápida, ligera y sin errores de parser HTML)
    final queries = <String>[
      '$artist $effectiveTitle Official Audio',
      if (effectiveTitle != title) '$artist $title audio',
    ];

    for (final query in queries) {
      try {
        final visitorData = await YouTubeStreamResolver.getVisitorData();
        final res = await http
            .post(
              Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                if (visitorData != null) 'X-Goog-Visitor-Id': visitorData,
              },
              body: json.encode({
                'query': query,
                'context': {
                  'client': {
                    'clientName': 'WEB',
                    'clientVersion': '2.20250312.04.00',
                    'hl': 'en',
                    'gl': 'US',
                    if (visitorData != null) 'visitorData': visitorData,
                  },
                },
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final renderers = <Map<String, dynamic>>[];

          void extractVideoRenderers(dynamic node) {
            if (node is Map<String, dynamic>) {
              if (node.containsKey('videoRenderer') && node['videoRenderer'] is Map<String, dynamic>) {
                renderers.add(node['videoRenderer'] as Map<String, dynamic>);
              } else {
                for (final v in node.values) {
                  extractVideoRenderers(v);
                }
              }
            } else if (node is List) {
              for (final item in node) {
                extractVideoRenderers(item);
              }
            }
          }

          extractVideoRenderers(data);

          if (renderers.isNotEmpty) {
            String? bestId;
            var bestScore = -1e9;

            for (final r in renderers.take(15)) {
              final videoId = r['videoId'] as String?;
              if (videoId == null || videoId.isEmpty) continue;

              String vTitle = '';
              final titleRuns = r['title']?['runs'] as List?;
              if (titleRuns != null && titleRuns.isNotEmpty) {
                vTitle = titleRuns.map((e) => e['text']?.toString() ?? '').join();
              } else if (r['title']?['simpleText'] != null) {
                vTitle = r['title']['simpleText'].toString();
              }
              if (vTitle.isEmpty) continue;

              String vAuthor = '';
              final ownerRuns = (r['ownerText']?['runs'] ?? r['longBylineText']?['runs'] ?? r['shortBylineText']?['runs']) as List?;
              if (ownerRuns != null && ownerRuns.isNotEmpty) {
                vAuthor = ownerRuns.first['text']?.toString() ?? '';
              }

              final lengthStr = (r['lengthText']?['simpleText'] as String?) ??
                  ((r['lengthText']?['runs'] as List?)?.isNotEmpty == true
                      ? r['lengthText']['runs'][0]['text']?.toString()
                      : null);
              final vd = _parseClockDuration(lengthStr);

              final score = scoreCandidate(vTitle, vAuthor, vd);
              if (score > bestScore) {
                bestScore = score;
                bestId = videoId;
              }
            }

            if (bestId != null) {
              return bestId;
            }
          }
        }
      } catch (e) {
        print('InnerTube search error ($query): $e');
      }
    }

    // 2. Respaldo: youtube_explode_dart
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final results = await YouTubeStreamResolver.sharedYt.search
            .search('$artist $effectiveTitle audio')
            .timeout(const Duration(seconds: 12));
        if (results.isEmpty) return null;

        Video? best;
        var bestScore = -1e9;
        for (final v in results.take(12)) {
          final score = scoreCandidate(v.title, v.author, v.duration ?? Duration.zero);
          if (score > bestScore) {
            bestScore = score;
            best = v;
          }
        }
        return best?.id.value;
      } catch (e) {
        print('YouTube match error (attempt $attempt): $e');
        YouTubeStreamResolver.resetSharedYt();
      }
    }
    return null;
  }

  /// Busca en YouTube opciones de canciones por nombre, priorizando canciones oficiales
  /// con carátula (Art Tracks / "- Topic" / Visualizer / Audio Oficial) y descartando
  /// covers y videos musicales salvo que el usuario escriba explícitamente el canal del cover.
  static Future<List<ImportPreview>> searchYouTubeSongs(String rawQuery) async {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) return [];

    final wantQuery = _normalize(trimmed);
    final userWantsCover = wantQuery.contains('cover') ||
        wantQuery.contains('tributo') ||
        wantQuery.contains('karaoke');
    final userWantsLive = wantQuery.contains('en vivo') ||
        wantQuery.contains('live') ||
        wantQuery.contains('concierto');

    final visitorData = await YouTubeStreamResolver.getVisitorData();

    Future<List<Map<String, dynamic>>> runInnerTubeQuery(String q) async {
      try {
        final res = await http
            .post(
              Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                if (visitorData != null) 'X-Goog-Visitor-Id': visitorData,
              },
              body: json.encode({
                'query': q,
                'context': {
                  'client': {
                    'clientName': 'WEB',
                    'clientVersion': '2.20250312.04.00',
                    'hl': 'es',
                    'gl': 'MX',
                    if (visitorData != null) 'visitorData': visitorData,
                  },
                },
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final renderers = <Map<String, dynamic>>[];

          void extract(dynamic node) {
            if (node is Map<String, dynamic>) {
              if (node.containsKey('videoRenderer') && node['videoRenderer'] is Map<String, dynamic>) {
                renderers.add(node['videoRenderer'] as Map<String, dynamic>);
              } else {
                for (final v in node.values) {
                  extract(v);
                }
              }
            } else if (node is List) {
              for (final item in node) {
                extract(item);
              }
            }
          }

          extract(data);
          return renderers;
        }
      } catch (e) {
        print('searchYouTubeSongs InnerTube error ($q): $e');
      }
      return [];
    }

    Future<List<_TrackMeta>> fetchItunesCandidates() async {
      try {
        final res = await http
            .get(Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(trimmed)}&entity=song&limit=10'))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final results = (json.decode(res.body)['results'] as List?) ?? [];
          return results.whereType<Map<String, dynamic>>().map((r) {
            final ms = r['trackTimeMillis'] as int? ?? 0;
            final release = r['releaseDate'] as String?;
            return _TrackMeta(
              title: (r['trackName'] as String?) ?? '',
              artist: (r['artistName'] as String?) ?? '',
              album: r['collectionName'] as String?,
              coverUrl: (r['artworkUrl100'] as String?)?.replaceAll('100x100bb', '600x600bb'),
              duration: Duration(milliseconds: ms),
              genre: r['primaryGenreName'] as String?,
              year: (release != null && release.length >= 4) ? release.substring(0, 4) : null,
            );
          }).toList();
        }
      } catch (_) {}
      return [];
    }

    final queries = (userWantsCover || userWantsLive)
        ? <String>[trimmed]
        : <String>[
            '$trimmed "Provided to YouTube"',
            '$trimmed Visualizer OR "Official Audio" OR "Audio Oficial"',
            trimmed,
          ];

    final searchFutures = queries.map(runInnerTubeQuery).toList();
    final itunesFuture = fetchItunesCandidates();

    final rawLists = await Future.wait(searchFutures);
    final itunesTracks = await itunesFuture;

    final coverWords = [
      'cover',
      'karaoke',
      'tributo',
      'tribute',
      'parodia',
      'imitador',
      'reaccion',
      'reaction',
      'tutorial',
      'como tocar',
      'pista',
      'instrumental',
      '8d',
      'nightcore',
      'sped up',
      'slowed',
    ];

    final liveWords = [
      'en vivo',
      'live',
      'concierto',
      'festival',
      'auditorio',
    ];

    final musicVideoWords = [
      'video oficial',
      'official video',
      'official music video',
      'videoclip',
      'video musical',
    ];

    final seenIds = <String>{};
    final scored = <({ImportPreview preview, double score, bool isMusicVideo})>[];

    for (final list in rawLists) {
      for (final r in list) {
        final videoId = r['videoId'] as String?;
        if (videoId == null || videoId.isEmpty || seenIds.contains(videoId)) continue;

        String vTitle = '';
        final titleRuns = r['title']?['runs'] as List?;
        if (titleRuns != null && titleRuns.isNotEmpty) {
          vTitle = titleRuns.map((e) => e['text']?.toString() ?? '').join();
        } else if (r['title']?['simpleText'] != null) {
          vTitle = r['title']['simpleText'].toString();
        }
        if (vTitle.isEmpty) continue;

        String vAuthor = '';
        final ownerRuns =
            (r['ownerText']?['runs'] ?? r['longBylineText']?['runs'] ?? r['shortBylineText']?['runs']) as List?;
        if (ownerRuns != null && ownerRuns.isNotEmpty) {
          vAuthor = ownerRuns.first['text']?.toString() ?? '';
        }

        String desc = '';
        final snippets = r['detailedMetadataSnippets'] as List?;
        if (snippets != null && snippets.isNotEmpty) {
          final runs = snippets.first['snippetText']?['runs'] as List?;
          if (runs != null) {
            desc = runs.map((e) => e['text']?.toString() ?? '').join();
          }
        }
        if (desc.isEmpty && r['descriptionSnippet']?['runs'] is List) {
          desc = (r['descriptionSnippet']['runs'] as List).map((e) => e['text']?.toString() ?? '').join();
        }

        final lengthStr = (r['lengthText']?['simpleText'] as String?) ??
            ((r['lengthText']?['runs'] as List?)?.isNotEmpty == true
                ? r['lengthText']['runs'][0]['text']?.toString()
                : null);
        final vd = _parseClockDuration(lengthStr);
        if (vd.inSeconds > 0 && (vd.inSeconds < 45 || vd.inSeconds > 900)) continue;

        final normTitle = _normalize(vTitle);
        final cleanAuthor = vAuthor
            .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
            .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
            .trim();
        final normAuthor = _normalize(cleanAuthor);

        // Permitir un canal de cover únicamente si el usuario escribió el nombre de ese canal en la búsqueda
        final userTypedChannel = normAuthor.length >= 4 &&
            wantQuery.contains(normAuthor) &&
            !itunesTracks.any((it) => _normalize(it.artist) == normAuthor);

        final hasCoverWord = coverWords.any((w) => normTitle.contains(w) || normAuthor.contains(w));
        if (hasCoverWord && !userWantsCover && !userTypedChannel) {
          continue;
        }

        final hasLiveWord = liveWords.any((w) => normTitle.contains(w));
        if (hasLiveWord && !userWantsLive && !userTypedChannel) {
          continue;
        }

        final isArtTrack = vAuthor.endsWith(' - Topic') ||
            desc.contains('Provided to YouTube') ||
            desc.contains('Auto-generated by YouTube');
        final isVisualizerOrAudio = normTitle.contains('visualizer') ||
            normTitle.contains('official audio') ||
            normTitle.contains('audio oficial') ||
            normTitle.contains('lyric') ||
            normTitle.contains('letra');
        final isMusicVideo = !isArtTrack &&
            !isVisualizerOrAudio &&
            musicVideoWords.any((w) => normTitle.contains(w));

        var score = 0.0;
        if (isArtTrack) score += 85; // Canción oficial + carátula cuadrada ("- Topic")
        if (isVisualizerOrAudio) score += 45; // Visualizer / Audio Oficial
        if (userTypedChannel) score += 70; // Canal específico pedido por el usuario
        if (isMusicVideo) score -= 65; // Descartar/penalizar video oficial teatral

        for (final w in wantQuery.split(' ')) {
          if (w.length > 2 && (normTitle.contains(w) || normAuthor.contains(w))) {
            score += 10;
          }
        }

        final guess = _splitArtistTitle(vTitle, cleanAuthor);

        // Vincular con metadatos de estudio de iTunes para carátula cuadrada HD y nombre de álbum oficial
        _TrackMeta? matchedItunes;
        for (final it in itunesTracks) {
          final itTitle = _normalize(it.title);
          final itArtist = _normalize(it.artist);
          final guessTitle = _normalize(guess.title);
          final guessArtist = _normalize(guess.artist);

          final titleMatches = itTitle.isNotEmpty &&
              (guessTitle.contains(itTitle) || itTitle.contains(guessTitle) || normTitle.contains(itTitle));
          final artistMatches = itArtist.isNotEmpty &&
              (guessArtist.contains(itArtist) || itArtist.contains(guessArtist) || normAuthor.contains(itArtist));
          if (titleMatches && artistMatches) {
            matchedItunes = it;
            score += 30;
            break;
          }
        }

        // Si no es un canal pedido por el usuario, ni Art Track, ni Visualizer/Audio, ni artista oficial de iTunes,
        // descartar canales desconocidos para no mostrar covers sin etiqueta
        if (!userWantsCover &&
            !userTypedChannel &&
            !isArtTrack &&
            !isVisualizerOrAudio &&
            matchedItunes == null) {
          continue;
        }

        seenIds.add(videoId);

        final displayTitle = (isArtTrack && matchedItunes != null) ? matchedItunes.title : guess.title;
        final displayArtist = (matchedItunes != null && !userTypedChannel) ? matchedItunes.artist : guess.artist;
        final displayAlbum = isArtTrack
            ? (matchedItunes?.album ?? 'Canción Oficial • Carátula')
            : (isVisualizerOrAudio
                ? (matchedItunes?.album != null ? '${matchedItunes!.album} • Visualizer' : 'Visualizer / Audio Oficial')
                : (matchedItunes?.album ?? cleanAuthor));
        final coverUrl = (matchedItunes?.coverUrl != null && !userTypedChannel)
            ? matchedItunes!.coverUrl
            : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

        scored.add((
          preview: ImportPreview(
            title: displayTitle,
            artist: displayArtist,
            album: displayAlbum,
            coverUrl: coverUrl,
            duration: vd > Duration.zero ? vd : (matchedItunes?.duration ?? Duration.zero),
            youtubeId: videoId,
            sourceUrl: 'https://www.youtube.com/watch?v=$videoId',
            platform: LinkPlatform.youtube,
            genre: matchedItunes?.genre,
            year: matchedItunes?.year,
          ),
          score: score,
          isMusicVideo: isMusicVideo,
        ));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    // Si hay opciones de Audio Oficial / Carátula / Visualizer, excluir por completo los videos musicales oficiales
    final nonMusicVideos = scored.where((item) => !item.isMusicVideo).toList();
    final finalPool = nonMusicVideos.isNotEmpty ? nonMusicVideos : scored;

    return finalPool.take(6).map((e) => e.preview).toList();
  }

  // ---------------------------------------------------------------------------
  // Metadatos (iTunes Search API)
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

  static Duration _parseClockDuration(String? text) {
    if (text == null || text.trim().isEmpty) return Duration.zero;
    final parts = text.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return Duration(minutes: m, seconds: s);
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return Duration(hours: h, minutes: m, seconds: s);
    }
    return Duration.zero;
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
