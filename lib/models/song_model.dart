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

  /// ID del video de YouTube del que se transmite el audio (canciones en streaming)
  String? youtubeId;

  /// Enlace original que pegó el usuario (YouTube o Spotify)
  String? sourceUrl;

  /// Plataforma de origen: 'local', 'youtube' o 'spotify'
  String source;

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
    this.youtubeId,
    this.sourceUrl,
    this.source = 'local',
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Canción importada desde la red (YouTube o Spotify)
  bool get isImported => youtubeId != null || source == 'youtube' || source == 'spotify';

  /// La canción se reproduce directamente desde internet (aún sin archivo local completo)
  bool get isStreaming => isImported && (localAudioPath == null || localAudioPath!.isEmpty);

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
    String? youtubeId,
    String? sourceUrl,
    String? source,
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
      youtubeId: youtubeId ?? this.youtubeId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      source: source ?? this.source,
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
        'youtubeId': youtubeId,
        'sourceUrl': sourceUrl,
        'source': source,
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
      youtubeId: json['youtubeId'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      source: json['source'] as String? ?? 'local',
      addedAt: json['addedAt'] != null ? DateTime.tryParse(json['addedAt'] as String) : null,
    );
  }
}
