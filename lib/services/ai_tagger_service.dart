import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/song_model.dart';

class AITaggerService {
  /// Clean up common filename noise, underscores, and extension for accurate AI matching
  static String cleanTitle(String rawTitle) {
    String cleaned = rawTitle;
    cleaned = cleaned.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), ''); // Remove extension
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), ''); // Remove (Official Audio)
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), ''); // Remove [MV]
    cleaned = cleaned.replaceAll(RegExp(r'[_]+'), ' '); // Replace underscores with spaces
    cleaned = cleaned.replaceAll(RegExp(r'[-]+'), ' '); // Replace hyphens with spaces
    cleaned = cleaned.replaceAll(
      RegExp(r'(official video|official audio|lyric video|hd|4k|remastered|audio|video|mp3|m4a|wav)', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  /// AI Auto-Identify Song & Fetch Metadata + High-Res Album Cover Art
  static Future<Song> identifyAndEnrich(Song song) async {
    try {
      final query = cleanTitle(song.title.isNotEmpty ? song.title : song.artist);
      if (query.isEmpty) return song;

      final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=song&limit=1');
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List<dynamic>?;

        if (results != null && results.isNotEmpty) {
          final first = results[0];
          final trackName = first['trackName'] as String? ?? song.title;
          final artistName = first['artistName'] as String? ?? song.artist;
          final collectionName = first['collectionName'] as String? ?? song.album;
          final primaryGenreName = first['primaryGenreName'] as String?;
          final releaseDateStr = first['releaseDate'] as String?;

          String? yearStr;
          if (releaseDateStr != null && releaseDateStr.length >= 4) {
            yearStr = releaseDateStr.substring(0, 4);
          }

          // Get High Resolution Album Art (600x600bb)
          String? rawCoverUrl = first['artworkUrl100'] as String?;
          String? highResCoverUrl;
          String? localCoverPath;

          if (rawCoverUrl != null) {
            highResCoverUrl = rawCoverUrl.replaceAll('100x100bb', '600x600bb');
            localCoverPath = await downloadAndSaveCover(highResCoverUrl, song.id);
          }

          return song.copyWith(
            title: trackName,
            artist: artistName,
            album: collectionName,
            coverUrl: highResCoverUrl,
            localCoverPath: localCoverPath,
            genre: primaryGenreName,
            year: yearStr,
          );
        }
      }
    } catch (e) {
      print('AI Tagger identification error: $e');
    }
    return song;
  }

  /// Download and save album cover art to persistent local storage
  static Future<String?> downloadAndSaveCover(String coverUrl, String songId) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(path.join(docDir.path, 'album_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final sanitizedId = songId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filePath = path.join(coversDir.path, 'cover_$sanitizedId.jpg');
      final file = File(filePath);

      final res = await http.get(Uri.parse(coverUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        await file.writeAsBytes(res.bodyBytes);
        return filePath;
      }
    } catch (e) {
      print('Failed to save cover art: $e');
    }
    return null;
  }
}
