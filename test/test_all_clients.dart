import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

void main() async {
  final ytClient = yt.YoutubeExplode();
  final videoId = "CzwSaSnD2bk"; // JZÉ ROI - Lost in Angkor
  print("Testing manifest retrieval on all clients for $videoId...");

  final clients = {
    "ios": yt.YoutubeApiClient.ios,
    "android": yt.YoutubeApiClient.android,
    "androidSdkless": yt.YoutubeApiClient.androidSdkless,
    "androidMusic": yt.YoutubeApiClient.androidMusic,
    "androidVr": yt.YoutubeApiClient.androidVr,
    "safari": yt.YoutubeApiClient.safari,
    "tv": yt.YoutubeApiClient.tv,
    "mediaConnect": yt.YoutubeApiClient.mediaConnect,
    "mweb": yt.YoutubeApiClient.mweb,
    "webCreator": yt.YoutubeApiClient.webCreator,
  };

  for (var entry in clients.entries) {
    print("\n-----------------------------");
    print("Testing client: ${entry.key}...");
    try {
      final manifest = await ytClient.videos.streamsClient.getManifest(
        videoId,
        ytClients: [entry.value],
      );
      print("SUCCESS! Streams count: ${manifest.streams.length}");
    } catch (e) {
      print("FAILED: $e");
    }
  }

  ytClient.close();
}
