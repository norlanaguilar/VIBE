class Song {
  final String id;
  String title;
  String artist;
  String album;
  String? coverUrl;
  String? localCoverPath;
  String? audioUrl;
  String? localAudioPath;
  Duration duration;
  bool isLiked;
  bool isDownloaded;
  String? genre;
  String? year;
  DateTime addedAt;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.coverUrl,
    this.localCoverPath,
    this.audioUrl,
    this.localAudioPath,
    this.duration = Duration.zero,
    this.isLiked = false,
    this.isDownloaded = false,
    this.genre,
    this.year,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
    String? localCoverPath,
    String? audioUrl,
    String? localAudioPath,
    Duration? duration,
    bool? isLiked,
    bool? isDownloaded,
    String? genre,
    String? year,
    DateTime? addedAt,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      localCoverPath: localCoverPath ?? this.localCoverPath,
      audioUrl: audioUrl ?? this.audioUrl,
      localAudioPath: localAudioPath ?? this.localAudioPath,
      duration: duration ?? this.duration,
      isLiked: isLiked ?? this.isLiked,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}
