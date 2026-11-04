import 'dart:io';
import 'dart:typed_data';

class AudioDurationHelper {
  /// Lee la duración exacta directamente desde la caja 'mvhd' en archivos MP4 / M4A.
  /// Esto previene el problema donde decodificadores con SBR (Spectral Band Replication)
  /// en ExoPlayer y AVPlayer dividen los samples de audio por la frecuencia base (ej. 22050Hz
  /// en vez de 44100Hz), duplicando artificialmente la duración de la canción.
  static Future<Duration?> readM4aDuration(File file) async {
    try {
      if (!await file.exists()) return null;
      final length = await file.length();
      if (length < 32) return null;

      final raf = await file.open(mode: FileMode.read);
      try {
        final bytesToRead = length < 8192 ? length : 8192;
        final bytes = await raf.read(bytesToRead);

        for (int i = 0; i < bytes.length - 32; i++) {
          // 'm' = 0x6d, 'v' = 0x76, 'h' = 0x68, 'd' = 0x64
          if (bytes[i] == 0x6d && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x68 && bytes[i + 3] == 0x64) {
            final version = bytes[i + 4];
            final bd = ByteData.sublistView(Uint8List.fromList(bytes.sublist(i + 4, i + 36)));
            int timeScale = 0;
            int durationUnits = 0;

            if (version == 0) {
              timeScale = bd.getUint32(12);
              durationUnits = bd.getUint32(16);
            } else if (version == 1) {
              timeScale = bd.getUint32(20);
              durationUnits = bd.getUint64(24);
            }

            if (timeScale > 0 && durationUnits > 0) {
              final seconds = durationUnits / timeScale;
              return Duration(milliseconds: (seconds * 1000).round());
            }
          }
        }
      } finally {
        await raf.close();
      }
    } catch (_) {}
    return null;
  }
}
