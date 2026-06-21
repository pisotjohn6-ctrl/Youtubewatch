import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/session.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import '../models/download_task.dart';

class DownloadService {
  // Singleton Pattern
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;

  DownloadService._internal();

  final YoutubeExplode _yt = YoutubeExplode();
  List<DownloadTask> _tasks = [];
  final StreamController<List<DownloadTask>> _tasksController = StreamController<List<DownloadTask>>.broadcast();

  final Set<String> _cancelledTaskIds = {};
  final Map<String, List<StreamSubscription>> _activeSubscriptions = {};
  final Map<String, FFmpegSession> _activeFfmpegSessions = {};
  final Map<String, CancelToken> _activeCancelTokens = {};
  final Map<String, Completer<void>> _activeCompleters = {};

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  List<DownloadTask> get tasks => _tasks;

  static const String _prefsKey = 'downloaded_tasks_v1';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? [];
    _tasks = list.map((item) => DownloadTask.fromJson(item)).toList();
    
    // Clean up any tasks that think they are downloading from a previous app run
    for (var task in _tasks) {
      if (task.isDownloading) {
        task.isDownloading = false;
        task.progress = 0.0;
      }
      // Double check file existence
      if (task.isCompleted && task.localPath != null) {
        final file = File(task.localPath!);
        if (!await file.exists()) {
          task.isCompleted = false;
          task.localPath = null;
          task.progress = 0.0;
        }
      }
    }
    _tasksController.add(List.from(_tasks));
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _tasks.map((task) => task.toJson()).toList();
    await prefs.setStringList(_prefsKey, list);
    _tasksController.add(List.from(_tasks));
  }

  Future<void> startDownload({
    required String id,
    required String title,
    required String author,
    required String thumbnailUrl,
    required String durationString,
    StreamInfo? streamInfo,
  }) async {
    print("DownloadService: startDownload called for video: $title ($id)");
    // Check if already downloading (prevent concurrent downloads of same video)
    final String videoId = id;
    final bool isAlreadyDownloading = _tasks.any((t) {
      final taskVideoId = t.id.contains('@') ? t.id.split('@').first : t.id.split('_').first;
      return taskVideoId == videoId && t.isDownloading;
    });

    if (isAlreadyDownloading) {
      print("DownloadService: Already downloading this video: $videoId");
      return;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Generate unique taskId and unique filename using timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final taskId = '$videoId@$timestamp';

    // Clear from cancelled list just in case
    _cancelledTaskIds.remove(taskId);

    // Replace invalid file path characters in title
    final safeTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final filePath = '${dir.path}/${videoId}_${timestamp}_$safeTitle.mp4';

    print("DownloadService: Created task ID: $taskId, file path: $filePath");

    final task = DownloadTask(
      id: taskId,
      title: title,
      author: author,
      thumbnailUrl: thumbnailUrl,
      durationString: durationString,
      progress: 0.0,
      isDownloading: true,
      isCompleted: false,
      localPath: filePath,
    );

    _tasks.add(task);
    await _saveTasks();

    // Start background download and merge
    print("DownloadService: Initiating _executeDownload for task: $taskId");
    _executeDownload(task, streamInfo, filePath);
  }

  Future<void> _executeDownload(DownloadTask task, StreamInfo? streamInfo, String filePath) async {
    try {
      final videoId = task.id.contains('@') ? task.id.split('@').first : task.id.split('_').first;
      
      StreamInfo? selectedStream = streamInfo;
      if (selectedStream == null) {
        final manifest = await _yt.videos.streamsClient.getManifest(
          VideoId(videoId),
          ytClients: [
            YoutubeApiClient.ios,
            YoutubeApiClient.tv,
            YoutubeApiClient.android,
          ],
          requireWatchPage: false,
        );

        // 1. Try to find a muxed stream with height == 360
        for (var stream in manifest.muxed) {
          if (stream.videoResolution.height == 360) {
            selectedStream = stream;
            break;
          }
        }

        // 2. If not found, try to find any muxed stream closest to 360p
        if (selectedStream == null && manifest.muxed.isNotEmpty) {
          final sortedMuxed = List<MuxedStreamInfo>.from(manifest.muxed);
          sortedMuxed.sort((a, b) => (a.videoResolution.height - 360).abs().compareTo((b.videoResolution.height - 360).abs()));
          selectedStream = sortedMuxed.first;
        }

        // 3. Fallback to videoOnly or audioOnly
        if (selectedStream == null) {
          if (manifest.videoOnly.isNotEmpty) {
            final sortedVideo = List<VideoOnlyStreamInfo>.from(manifest.videoOnly);
            sortedVideo.sort((a, b) => (a.videoResolution.height - 360).abs().compareTo((b.videoResolution.height - 360).abs()));
            selectedStream = sortedVideo.first;
          } else if (manifest.audio.isNotEmpty) {
            selectedStream = manifest.audio.first;
          }
        }
      }

      if (selectedStream == null) {
        throw Exception("No downloadable streams found");
      }

      if (selectedStream is MuxedStreamInfo) {
        // Direct download for muxed quality (e.g. 360p)
        await _downloadStreamToFile(task, selectedStream, filePath);

        if (_cancelledTaskIds.contains(task.id)) {
          throw Exception("Download cancelled");
        }
        
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index].isDownloading = false;
          _tasks[index].isCompleted = true;
          _tasks[index].localPath = filePath;
          _tasks[index].progress = 1.0;
          await _saveTasks();
        }
      } else if (streamInfo is VideoOnlyStreamInfo) {
        // High quality (e.g. 480p, 720p, 1080p): Requires separate video/audio downloading and merging
        final manifest = await _yt.videos.streamsClient.getManifest(
          VideoId(videoId),
          ytClients: [
            YoutubeApiClient.ios,
            YoutubeApiClient.tv,
            YoutubeApiClient.android,
          ],
          requireWatchPage: false,
        );
        final audioStreamInfo = manifest.audio.reduce((curr, next) => curr.bitrate.bitsPerSecond > next.bitrate.bitsPerSecond ? curr : next);

        final appDir = await getApplicationDocumentsDirectory();
        final tempVideoPath = '${appDir.path}/downloads/temp_video_${task.id}.mp4';
        final tempAudioPath = '${appDir.path}/downloads/temp_audio_${task.id}.m4a';

        // Download Video (weight = 80%)
        await _downloadStreamToFile(task, streamInfo, tempVideoPath, progressMultiplier: 0.8, progressOffset: 0.0);

        if (_cancelledTaskIds.contains(task.id)) {
          throw Exception("Download cancelled");
        }
        
        // Download Audio (weight = 20%)
        await _downloadStreamToFile(task, audioStreamInfo, tempAudioPath, progressMultiplier: 0.2, progressOffset: 0.8);

        if (_cancelledTaskIds.contains(task.id)) {
          throw Exception("Download cancelled");
        }

        // Update progress to 99% during merge
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index].progress = 0.99;
          _tasksController.add(List.from(_tasks));
        }

        // Run FFmpeg to merge video and audio without re-encoding video
        final command = '-y -i "$tempVideoPath" -i "$tempAudioPath" -c:v copy -c:a aac -shortest "$filePath"';

        final completer = Completer<Session>();
        final session = await FFmpegKit.executeAsync(command, (Session finishedSession) {
          completer.complete(finishedSession);
        });

        // Track session for cancellation
        _activeFfmpegSessions[task.id] = session;

        final finishedSession = await completer.future;
        _activeFfmpegSessions.remove(task.id);

        final returnCode = await finishedSession.getReturnCode();

        // Delete temporary files
        try {
          final tempVideo = File(tempVideoPath);
          final tempAudio = File(tempAudioPath);
          if (await tempVideo.exists()) await tempVideo.delete();
          if (await tempAudio.exists()) await tempAudio.delete();
        } catch (_) {}

        if (_cancelledTaskIds.contains(task.id)) {
          throw Exception("Download cancelled");
        }

        if (ReturnCode.isSuccess(returnCode)) {
          final index = _tasks.indexWhere((t) => t.id == task.id);
          if (index != -1) {
            _tasks[index].isDownloading = false;
            _tasks[index].isCompleted = true;
            _tasks[index].localPath = filePath;
            _tasks[index].progress = 1.0;
            await _saveTasks();
          }
        } else {
          throw Exception("FFmpeg merge failed with code: $returnCode");
        }
      }
    } catch (e) {
      print('Download error: $e');
      
      // Attempt to clean up the main file
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}

      // Clean up temp files if they exist
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final tempVideo = File('${appDir.path}/downloads/temp_video_${task.id}.mp4');
        final tempAudio = File('${appDir.path}/downloads/temp_audio_${task.id}.m4a');
        if (await tempVideo.exists()) await tempVideo.delete();
        if (await tempAudio.exists()) await tempAudio.delete();
      } catch (_) {}

      // Only mark as failed if it was NOT explicitly cancelled
      // (If it was cancelled, cancelDownload already removed it from the tasks list)
      if (!_cancelledTaskIds.contains(task.id)) {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index].isDownloading = false;
          _tasks[index].isCompleted = false;
          _tasks[index].progress = 0.0;
          await _saveTasks();
        }
      } else {
        // Clean up cancellation tracking
        _cancelledTaskIds.remove(task.id);
      }
    }
  }

  Future<void> _downloadStreamToFile(
    DownloadTask task, 
    StreamInfo streamInfo, 
    String filePath, 
    {double progressMultiplier = 1.0, 
    double progressOffset = 0.0}
  ) async {
    if (_cancelledTaskIds.contains(task.id)) {
      throw Exception("Download cancelled");
    }

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }

    final fileSink = file.openWrite(mode: FileMode.append);
    final client = http.Client();
    final totalBytes = streamInfo.size.totalBytes;
    int downloadedBytes = 0;

    String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36';
    final clientParam = streamInfo.url.queryParameters['c'];
    if (clientParam == 'IOS') {
      userAgent = 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
    } else if (clientParam == 'ANDROID') {
      userAgent = 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
    } else if (clientParam == 'TVHTML5') {
      userAgent = 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version,gzip(gfe)';
    }

    final Map<String, String> requestHeaders = {
      'user-agent': userAgent,
      'cookie': 'CONSENT=YES+cb',
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
      'accept-language': 'en-US,en;q=0.5',
    };

    const int chunkSize = 1024 * 1024; // 1 MB chunk range

    try {
      while (downloadedBytes < totalBytes) {
        if (_cancelledTaskIds.contains(task.id)) {
          throw Exception("Download cancelled");
        }

        final from = downloadedBytes;
        final to = (from + chunkSize < totalBytes) ? (from + chunkSize - 1) : (totalBytes - 1);

        int retryCount = 0;
        bool chunkSuccess = false;

        while (!chunkSuccess && retryCount < 5) {
          if (_cancelledTaskIds.contains(task.id)) {
            throw Exception("Download cancelled");
          }

          try {
            Uri requestUrl = streamInfo.url;
            final Map<String, String> headers = Map.from(requestHeaders);

            if (streamInfo.url.queryParameters['c'] == 'ANDROID') {
              headers['Range'] = 'bytes=$from-$to';
            } else {
              final Map<String, String> newQuery = Map.from(streamInfo.url.queryParameters);
              newQuery['range'] = '$from-$to';
              requestUrl = streamInfo.url.replace(queryParameters: newQuery);
            }

            final request = http.Request('GET', requestUrl);
            request.headers.addAll(headers);

            final response = await client.send(request).timeout(const Duration(seconds: 12));

            if (response.statusCode != 200 && response.statusCode != 206) {
              throw Exception("Server returned status code: ${response.statusCode}");
            }

            final List<int> chunkData = [];
            final completer = Completer<void>();

            final subscription = response.stream.timeout(
              const Duration(seconds: 12),
              onTimeout: (sink) {
                sink.addError(TimeoutException("Chunk read timed out"));
              },
            ).listen(
              (data) {
                chunkData.addAll(data);
              },
              onDone: () => completer.complete(),
              onError: (err) => completer.completeError(err),
              cancelOnError: true,
            );

            // Register active subscription & completer so cancellation works immediately
            _activeSubscriptions[task.id] = [subscription];
            _activeCompleters[task.id] = completer;

            await completer.future;

            // Write the full chunk to disk
            fileSink.add(chunkData);
            await fileSink.flush();

            downloadedBytes += chunkData.length;
            chunkSuccess = true;
          } catch (e) {
            retryCount++;
            print("Error downloading chunk $from-$to (retry $retryCount/5): $e");
            if (retryCount >= 5) {
              rethrow;
            }
            await Future.delayed(Duration(seconds: 1 * retryCount));
          } finally {
            _activeSubscriptions.remove(task.id);
            _activeCompleters.remove(task.id);
          }
        }

        // Update UI progress
        final progress = progressOffset + ((downloadedBytes / totalBytes) * progressMultiplier);
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          if ((progress - _tasks[index].progress).abs() > 0.01 || progress == 1.0) {
            _tasks[index].progress = progress;
            _tasksController.add(List.from(_tasks));
          }
        }
      }
    } finally {
      client.close();
      await fileSink.close();
    }
  }

  Future<void> cancelDownload(String taskId) async {
    print("DownloadService: cancelDownload called for task: $taskId");
    print(StackTrace.current);
    _cancelledTaskIds.add(taskId);

    // Cancel active completers
    try {
      if (_activeCompleters.containsKey(taskId)) {
        print("DownloadService: Cancelling active completer for task: $taskId");
        final completer = _activeCompleters[taskId];
        if (completer != null && !completer.isCompleted) {
          completer.completeError(Exception("Download cancelled"));
        }
        _activeCompleters.remove(taskId);
      }
    } catch (e) {
      print("Error cancelling completer: $e");
    }

    // Cancel active Dio downloads
    try {
      if (_activeCancelTokens.containsKey(taskId)) {
        print("DownloadService: Cancelling active Dio download for task: $taskId");
        _activeCancelTokens[taskId]?.cancel();
        _activeCancelTokens.remove(taskId);
      }
    } catch (e) {
      print("Error cancelling Dio download: $e");
    }

    // 1. Cancel active stream subscriptions
    try {
      if (_activeSubscriptions.containsKey(taskId)) {
        print("DownloadService: Cancelling active subscriptions for task: $taskId");
        final subs = List<StreamSubscription>.from(_activeSubscriptions[taskId]!);
        for (var sub in subs) {
          await sub.cancel();
        }
        _activeSubscriptions.remove(taskId);
      }
    } catch (e) {
      print("Error cancelling stream: $e");
    }

    // 2. Cancel active FFmpeg sessions
    try {
      if (_activeFfmpegSessions.containsKey(taskId)) {
        final session = _activeFfmpegSessions[taskId];
        if (session != null) {
          await FFmpegKit.cancel(session.getSessionId());
        }
        _activeFfmpegSessions.remove(taskId);
      }
    } catch (e) {
      print("Error cancelling FFmpeg: $e");
    }

    // 3. Remove the task from the list and delete incomplete files
    try {
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        final task = _tasks[index];
        
        // Clean up temp files
        final appDir = await getApplicationDocumentsDirectory();
        final tempVideoPath = '${appDir.path}/downloads/temp_video_${task.id}.mp4';
        final tempAudioPath = '${appDir.path}/downloads/temp_audio_${task.id}.m4a';
        try {
          final tempVideo = File(tempVideoPath);
          final tempAudio = File(tempAudioPath);
          if (await tempVideo.exists()) await tempVideo.delete();
          if (await tempAudio.exists()) await tempAudio.delete();
        } catch (_) {}

        // Clean up main incomplete download file if it was created
        if (task.localPath != null) {
          try {
            final file = File(task.localPath!);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }

        _tasks.removeAt(index);
        await _saveTasks();
      }
    } catch (e) {
      print("Error removing task: $e");
    }
  }

  Future<void> deleteTask(DownloadTask task) async {
    if (task.localPath != null) {
      try {
        final file = File(task.localPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting file: $e');
      }
    }
    _tasks.removeWhere((t) => t.id == task.id);
    await _saveTasks();
  }

  void dispose() {
    _yt.close();
    _tasksController.close();
  }
}
