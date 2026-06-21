import 'dart:convert';

class DownloadTask {
  final String id;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String durationString;
  String? localPath;
  double progress;
  bool isCompleted;
  bool isDownloading;

  DownloadTask({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.durationString,
    this.localPath,
    this.progress = 0.0,
    this.isCompleted = false,
    this.isDownloading = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'thumbnailUrl': thumbnailUrl,
      'durationString': durationString,
      'localPath': localPath,
      'progress': progress,
      'isCompleted': isCompleted,
      'isDownloading': isDownloading,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      author: map['author'] ?? '',
      thumbnailUrl: map['thumbnailUrl'] ?? '',
      durationString: map['durationString'] ?? '',
      localPath: map['localPath'],
      progress: (map['progress'] ?? 0.0).toDouble(),
      isCompleted: map['isCompleted'] ?? false,
      isDownloading: map['isDownloading'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory DownloadTask.fromJson(String source) => DownloadTask.fromMap(json.decode(source));

  DownloadTask copyWith({
    String? id,
    String? title,
    String? author,
    String? thumbnailUrl,
    String? durationString,
    String? localPath,
    double? progress,
    bool? isCompleted,
    bool? isDownloading,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationString: durationString ?? this.durationString,
      localPath: localPath ?? this.localPath,
      progress: progress ?? this.progress,
      isCompleted: isCompleted ?? this.isCompleted,
      isDownloading: isDownloading ?? this.isDownloading,
    );
  }
}
