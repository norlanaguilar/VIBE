import 'dart:convert';
import 'package:http/http.dart' as http;

class LrcLine {
  final Duration timestamp;
  final String text;

  LrcLine({required this.timestamp, required this.text});
}

class LyricsResult {
  final bool hasLyrics;
  final bool isSynced;
  final List<LrcLine> syncedLines;
  final String plainLyrics;

  LyricsResult({
    required this.hasLyrics,
    required this.isSynced,
    this.syncedLines = const [],
    this.plainLyrics = '',
  });

  factory LyricsResult.empty() => LyricsResult(hasLyrics: false, isSynced: false);
}

class LyricsService {
  /// Buscar y obtener letras reales (sincronizadas LRC o texto plano) de LRCLIB API
  static Future<LyricsResult> fetchLyrics(String artist, String title) async {
    try {
      final cleanedArtist = _cleanQuery(artist);
      final cleanedTitle = _cleanQuery(title);

      if (cleanedTitle.isEmpty) return LyricsResult.empty();

      // 1. Consulta directa en LRCLIB API
      final uri = Uri.parse(
        'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(cleanedArtist)}&track_name=${Uri.encodeComponent(cleanedTitle)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseApiResponse(data);
      }

      // 2. Búsqueda secundaria si la coincidencia directa no devuelve resultado
      final searchUri = Uri.parse(
        'https://lrclib.net/api/search?q=${Uri.encodeComponent('$cleanedArtist $cleanedTitle')}',
      );
      final searchResponse = await http.get(searchUri).timeout(const Duration(seconds: 5));

      if (searchResponse.statusCode == 200) {
        final List<dynamic> results = json.decode(searchResponse.body);
        if (results.isNotEmpty) {
          final first = results.firstWhere(
            (r) => r['syncedLyrics'] != null || r['plainLyrics'] != null,
            orElse: () => results.first,
          );
          return _parseApiResponse(first);
        }
      }
    } catch (e) {
      print('Lyrics fetch error: $e');
    }
    return LyricsResult.empty();
  }

  static LyricsResult _parseApiResponse(Map<String, dynamic> data) {
    final syncedLyricsStr = data['syncedLyrics'] as String?;
    final plainLyricsStr = data['plainLyrics'] as String?;

    if (syncedLyricsStr != null && syncedLyricsStr.isNotEmpty) {
      final lines = parseLrc(syncedLyricsStr);
      if (lines.isNotEmpty) {
        return LyricsResult(
          hasLyrics: true,
          isSynced: true,
          syncedLines: lines,
        );
      }
    }

    if (plainLyricsStr != null && plainLyricsStr.isNotEmpty) {
      return LyricsResult(
        hasLyrics: true,
        isSynced: false,
        plainLyrics: plainLyricsStr,
      );
    }

    return LyricsResult.empty();
  }

  /// Parser de formato LRC con marcas de tiempo [mm:ss.xx]
  static List<LrcLine> parseLrc(String lrcContent) {
    final List<LrcLine> lines = [];
    final regExp = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\](.*)');

    for (final rawLine in lrcContent.split('\n')) {
      final match = regExp.firstMatch(rawLine.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3) ?? '0';
        final millis = int.parse(millisStr.padRight(3, '0').substring(0, 3));
        final text = match.group(4)!.trim();

        if (text.isNotEmpty) {
          lines.add(LrcLine(
            timestamp: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
            text: text,
          ));
        }
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  static String _cleanQuery(String input) {
    String cleaned = input;
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[_]+'), ' ');
    return cleaned.trim();
  }
}
