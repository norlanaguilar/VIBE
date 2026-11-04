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
    expect(sp?.type, equals(LinkType.track));

    final spPlaylist = LinkImportService.parse('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M');
    expect(spPlaylist?.platform, equals(LinkPlatform.spotify));
    expect(spPlaylist?.type, equals(LinkType.playlist));
    expect(spPlaylist?.isPlaylist, isTrue);

    final spAlbum = LinkImportService.parse('https://open.spotify.com/album/4m2880jivSbbyEGAKfITCa');
    expect(spAlbum?.platform, equals(LinkPlatform.spotify));
    expect(spAlbum?.type, equals(LinkType.album));
    expect(spAlbum?.isPlaylist, isTrue);

    final ytPlaylist = LinkImportService.parse('https://www.youtube.com/playlist?list=PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj');
    expect(ytPlaylist?.platform, equals(LinkPlatform.youtube));
    expect(ytPlaylist?.type, equals(LinkType.playlist));
    expect(ytPlaylist?.isPlaylist, isTrue);
  });
}
