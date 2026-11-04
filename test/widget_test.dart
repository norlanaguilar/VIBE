import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_local/models/song_model.dart';
import 'package:vibe_local/services/link_import_service.dart';

void main() {
  test('Song model serialization smoke test', () {
    final song = Song(
      id: 'test_1',
      title: 'Test Title',
      artist: 'Test Artist',
      album: 'Test Album',
      youtubeId: 'xyz123',
      source: 'youtube',
    );

    expect(song.isStreaming, isTrue);
    final json = song.toJson();
    final restored = Song.fromJson(json);
    expect(restored.id, equals('test_1'));
    expect(restored.youtubeId, equals('xyz123'));
  });

  test('Link parser recognizes YouTube and Spotify links', () {
    final yt = LinkImportService.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(yt?.platform, equals(LinkPlatform.youtube));
    expect(yt?.id, equals('dQw4w9WgXcQ'));

    final sp = LinkImportService.parse('https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT');
    expect(sp?.platform, equals(LinkPlatform.spotify));
    expect(sp?.id, equals('4cOdK2wGLETKBW3PvgPWqT'));
  });
}
