class Song {
  final String id;
  String title;
  String artist;
  String album;
  String? coverUrl;
  String? localCoverPath;
  String? videoCoverPath;
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
    this.videoCoverPath,
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
    String? videoCoverPath,
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
      videoCoverPath: videoCoverPath ?? this.videoCoverPath,
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
        'localCoverPath': localCoverPath,
        'videoCoverPath': videoCoverPath,
        'audioUrl': audioUrl,
        'localAudioPath': localAudioPath,
        'durationMs': duration.inMilliseconds,
        'isLiked': isLiked,
        'isDownloaded': isDownloaded,
        'genre': genre,
        'year': year,
        'addedAt': addedAt.toIso8601String(),
      };

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      coverUrl: json['coverUrl'] as String?,
      localCoverPath: json['localCoverPath'] as String?,
      videoCoverPath: json['videoCoverPath'] as String?,
      audioUrl: json['audioUrl'] as String?,
      localAudioPath: json['localAudioPath'] as String?,
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      isLiked: json['isLiked'] as bool? ?? false,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      genre: json['genre'] as String?,
      year: json['year'] as String?,
      addedAt: json['addedAt'] != null ? DateTime.tryParse(json['addedAt'] as String) : null,
    );
  }
}
