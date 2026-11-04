import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/song_model.dart';

/// Envía la canción actual a los widgets de la pantalla de inicio (Android e iOS)
/// y recibe los comandos de sus botones en iOS (en Android los botones van directo
/// al servicio de audio como si fueran botones multimedia).
class HomeWidgetBridge {
  static const MethodChannel _channel = MethodChannel('vibe/widget');

  static String? _lastKey;
  static String? _lastCoverSource;
  static String? _lastCoverPath;

  /// Registra el manejador de comandos ('next', 'previous', 'toggle') que llegan del widget de iOS
  static void listen(Future<void> Function(String command) onCommand) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'command' && call.arguments is String) {
        await onCommand(call.arguments as String);
      }
      return null;
    });
    // Avisar al lado nativo que Dart ya está listo para recibir comandos pendientes
    _channel.invokeMethod('ready').catchError((_) {});
  }

  static Future<void> update(Song? song, {required bool isPlaying}) async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    final key = '${song?.id}|${song?.title}|${song?.artist}|$isPlaying|${song?.localCoverPath}';
    if (key == _lastKey) return;
    _lastKey = key;

    try {
      final coverPath = song == null ? null : await _resolveCover(song);
      await _channel.invokeMethod('update', {
        'title': song?.title ?? 'Vibe',
        'artist': song?.artist ?? 'Nada en reproducción',
        'isPlaying': isPlaying,
        'coverPath': coverPath,
      });
    } catch (e) {
      print('Widget update error: $e');
    }
  }

  /// Los widgets necesitan la carátula como archivo local
  static Future<String?> _resolveCover(Song song) async {
    if (song.localCoverPath != null && await File(song.localCoverPath!).exists()) {
      return song.localCoverPath;
    }
    final url = song.coverUrl;
    if (url == null || !url.startsWith('http')) return null;
    if (url == _lastCoverSource) return _lastCoverPath;

    try {
      final dir = await getTemporaryDirectory();
      final file = File(path.join(dir.path, 'widget_cover.jpg'));
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
        _lastCoverSource = url;
        _lastCoverPath = file.path;
        return file.path;
      }
    } catch (_) {}
    return null;
  }
}
