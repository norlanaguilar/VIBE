import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song_model.dart';
import 'youtube_stream_resolver.dart';

/// Espectro de frecuencias real de lo que se está reproduciendo.
///
/// - Android: el sistema entrega el espectro en vivo (android.media.audiofx.Visualizer)
///   enganchado a la sesión de audio del reproductor.
/// - iOS: el reproductor no permite leer el audio en vivo, así que la canción se analiza
///   por adelantado (FFT nativa con Accelerate) y las barras se sincronizan con la posición.
///   El análisis se guarda en disco para que la segunda vez sea instantáneo.
class SpectrumService {
  static const int bandCount = 48;
  static const int analysisFps = 30;

  static const MethodChannel _method = MethodChannel('vibe/spectrum');
  static const EventChannel _live = EventChannel('vibe/spectrum/live');

  final AudioPlayer player;

  // Android (en vivo)
  StreamSubscription<dynamic>? _liveSub;
  StreamSubscription<int?>? _sessionSub;
  Float32List? _liveFrame;
  DateTime _liveFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  int? _sessionId;
  bool _liveRequested = false;
  bool _liveDenied = false;

  // iOS (pre-analizado)
  Float32List? _frames;
  int _framesFps = analysisFps;
  String? _framesSongId;
  String? _pendingSongId;
  final Map<String, Future<void>> _inFlight = {};

  SpectrumService(this.player);

  bool get _supportsLive => Platform.isAndroid;
  bool get _supportsOffline => Platform.isIOS;

  /// true cuando hay datos reales disponibles (si no, la UI usa una animación de respaldo)
  bool get hasRealData {
    if (_supportsLive) {
      return _liveFrame != null && DateTime.now().difference(_liveFrameAt) < const Duration(milliseconds: 600);
    }
    return _frames != null && _framesSongId == _pendingSongId;
  }

  // ---------------------------------------------------------------------------
  // Android: espectro en vivo
  // ---------------------------------------------------------------------------

  /// Se llama cuando el visualizador aparece en pantalla. Pide el permiso de
  /// "Grabar audio" (Android lo exige para leer el espectro, no se graba nada).
  Future<void> ensureLive() async {
    if (!_supportsLive || _liveRequested || _liveDenied) return;
    _liveRequested = true;

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _liveDenied = true;
      _liveRequested = false;
      return;
    }

    _liveSub ??= _live.receiveBroadcastStream().listen((event) {
      if (event is Float32List) {
        _liveFrame = event;
      } else if (event is List) {
        _liveFrame = Float32List.fromList(event.map((e) => (e as num).toDouble()).toList());
      }
      _liveFrameAt = DateTime.now();
    }, onError: (_) {});

    _sessionSub ??= player.androidAudioSessionIdStream.listen((id) => _attachSession(id));
    _attachSession(player.androidAudioSessionId);
  }

  Future<void> _attachSession(int? id) async {
    if (id == null || id == _sessionId) return;
    _sessionId = id;
    try {
      await _method.invokeMethod('startLive', {'sessionId': id, 'bands': bandCount});
    } catch (e) {
      print('Spectrum live error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // iOS: análisis por adelantado
  // ---------------------------------------------------------------------------

  /// Se llama cada vez que empieza una canción nueva
  Future<void> onTrackChanged(Song song) async {
    if (!_supportsOffline) return;
    _pendingSongId = song.id;
    if (_framesSongId == song.id) return;

    final cacheFile = await _cacheFileFor(song.id);
    if (await cacheFile.exists()) {
      _loadFromBytes(song.id, await cacheFile.readAsBytes());
      return;
    }

    // Evitar analizar dos veces la misma canción si el usuario salta rápido
    final job = _inFlight[song.id] ??= _analyze(song, cacheFile).whenComplete(() => _inFlight.remove(song.id));
    await job;
    if (_pendingSongId == song.id && await cacheFile.exists()) {
      _loadFromBytes(song.id, await cacheFile.readAsBytes());
    }
  }

  Future<void> _analyze(Song song, File cacheFile) async {
    File? tempFile;
    try {
      String? sourcePath;
      if (song.localAudioPath != null && await File(song.localAudioPath!).exists()) {
        sourcePath = song.localAudioPath;
      } else if (song.youtubeId != null) {
        final tmp = await getTemporaryDirectory();
        tempFile = await YouTubeStreamResolver.downloadToFile(
          song.youtubeId!,
          path.join(tmp.path, 'spectrum_${song.youtubeId}.m4a'),
        );
        sourcePath = tempFile.path;
      }
      if (sourcePath == null) return;

      final result = await _method.invokeMethod<Uint8List>('analyze', {
        'path': sourcePath,
        'bands': bandCount,
        'fps': analysisFps,
      });
      if (result == null || result.isEmpty) return;

      // Formato del archivo: [fps:int32][bands:int32][frames float32...]
      final header = ByteData(8)
        ..setInt32(0, analysisFps, Endian.little)
        ..setInt32(4, bandCount, Endian.little);
      final builder = BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(result);
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(builder.takeBytes(), flush: true);
    } catch (e) {
      print('Spectrum analysis error: $e');
    } finally {
      if (tempFile != null) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  void _loadFromBytes(String songId, Uint8List bytes) {
    if (bytes.length < 8) return;
    final header = ByteData.sublistView(bytes, 0, 8);
    final fps = header.getInt32(0, Endian.little);
    final bands = header.getInt32(4, Endian.little);
    if (bands != bandCount || fps <= 0) return;
    final payload = Uint8List.fromList(bytes.sublist(8));
    _frames = payload.buffer.asFloat32List(0, payload.lengthInBytes ~/ 4);
    _framesFps = fps;
    _framesSongId = songId;
  }

  Future<File> _cacheFileFor(String songId) async {
    final dir = await getApplicationSupportDirectory();
    return File(path.join(dir.path, 'spectrum_cache', '${_fnv1a(songId)}.spec'));
  }

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // ---------------------------------------------------------------------------
  // Lectura para la UI
  // ---------------------------------------------------------------------------

  /// Niveles actuales (0..1) por banda, o null si no hay datos reales
  Float32List? currentLevels() {
    if (_supportsLive) {
      return hasRealData ? _liveFrame : null;
    }
    final frames = _frames;
    if (frames == null || _framesSongId != _pendingSongId) return null;

    final totalFrames = frames.length ~/ bandCount;
    if (totalFrames == 0) return null;

    // Interpolación entre los dos cuadros más cercanos a la posición exacta
    final t = player.position.inMicroseconds / 1e6 * _framesFps;
    final i0 = t.floor().clamp(0, totalFrames - 1);
    final i1 = (i0 + 1).clamp(0, totalFrames - 1);
    final frac = (t - t.floor()).clamp(0.0, 1.0);

    final out = Float32List(bandCount);
    final o0 = i0 * bandCount;
    final o1 = i1 * bandCount;
    for (var b = 0; b < bandCount; b++) {
      out[b] = frames[o0 + b] * (1 - frac) + frames[o1 + b] * frac;
    }
    return out;
  }

  void dispose() {
    _liveSub?.cancel();
    _sessionSub?.cancel();
    if (_supportsLive) {
      _method.invokeMethod('stopLive').catchError((_) {});
    }
  }
}
