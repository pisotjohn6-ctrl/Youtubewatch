class PlayableItem {
  final String id;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String durationString;
  final bool isOffline;
  final String? url; // Streaming video/audio URL if online
  final String? localPath; // Local file path if offline

  PlayableItem({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.durationString,
    required this.isOffline,
    this.url,
    this.localPath,
  });

  factory PlayableItem.fromVideo(dynamic video, {String? streamUrl}) {
    // video can be a youtube_explode Video object
    return PlayableItem(
      id: video.id.value,
      title: video.title,
      author: video.author,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      durationString: video.duration?.toString().split('.').first ?? '00:00',
      isOffline: false,
      url: streamUrl,
    );
  }

  factory PlayableItem.fromDownloadTask(dynamic task) {
    // task is a DownloadTask object
    return PlayableItem(
      id: task.id,
      title: task.title,
      author: task.author,
      thumbnailUrl: task.thumbnailUrl,
      durationString: task.durationString,
      isOffline: true,
      localPath: task.localPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'thumbnailUrl': thumbnailUrl,
      'durationString': durationString,
      'isOffline': isOffline,
      'url': url,
      'localPath': localPath,
    };
  }

  factory PlayableItem.fromJson(Map<String, dynamic> json) {
    return PlayableItem(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String,
      durationString: json['durationString'] as String,
      isOffline: json['isOffline'] as bool,
      url: json['url'] as String?,
      localPath: json['localPath'] as String?,
    );
  }
}
