import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  Future<List<Video>> searchVideos(String query) async {
    try {
      final searchList = await _yt.search.search(query);
      return searchList.toList();
    } catch (e) {
      print('Error searching videos: $e');
      return [];
    }
  }

  Future<VideoSearchList?> getSearchList(String query) async {
    try {
      return await _yt.search.search(query);
    } catch (e) {
      print('Error getting search list: $e');
      return null;
    }
  }

  Future<Video?> getVideoDetails(String videoId) async {
    try {
      return await _yt.videos.get(videoId);
    } catch (e) {
      print('Error getting video details: $e');
      return null;
    }
  }

  Future<List<Video>> getRelatedVideos(Video video) async {
    try {
      final related = await _yt.videos.getRelatedVideos(video);
      return related?.toList() ?? [];
    } catch (e) {
      print('Error getting related videos: $e');
      return [];
    }
  }

  Future<StreamManifest?> getStreamManifest(String videoId) async {
    try {
      return await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.ios,
          YoutubeApiClient.tv,
          YoutubeApiClient.android,
        ],
        requireWatchPage: false,
      );
    } catch (e) {
      print('Error getting stream manifest: $e');
      return null;
    }
  }

  void close() {
    _yt.close();
  }
}
