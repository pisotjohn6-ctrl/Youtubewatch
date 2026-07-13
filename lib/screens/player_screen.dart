import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../controllers/playback_controller.dart';
import '../controllers/favorites_controller.dart';
import '../controllers/cast_controller.dart';
import '../services/youtube_service.dart';
import '../services/download_service.dart';
import '../models/download_task.dart';
import '../models/playable_item.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final PlaybackController _playbackController = PlaybackController();
  final FavoritesController _favoritesController = FavoritesController();
  final DownloadService _downloadService = DownloadService();
  final YoutubeService _youtubeService = YoutubeService();
  ChewieController? _chewieController;
  VideoPlayerController? _lastVideoController;
  Future<yt.Video?>? _videoDetailsFuture;
  String? _lastItemId;

  @override
  void initState() {
    super.initState();
    _playbackController.addListener(_onPlaybackStateChanged);
    CastController().addListener(_onCastStateChanged);
    _setupChewie();
    _updateVideoDetails();
  }

  void _onCastStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _updateVideoDetails() {
    final item = _playbackController.currentItem;
    if (item != null && item.id != _lastItemId) {
      _lastItemId = item.id;
      if (item.isOffline) {
        _videoDetailsFuture = Future.value(null);
      } else {
        _videoDetailsFuture = _youtubeService.getVideoDetails(item.id);
      }
    }
  }

  void _showUnifiedQualitySheet(BuildContext context, PlayableItem item) {
    final manifest = _playbackController.currentManifest;
    if (manifest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Stream details not loaded yet. Please wait.")),
      );
      return;
    }

    final watchStreams = manifest.muxed.toList();
    watchStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  item.author,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                
                // Section 1: Watch Quality
                const Row(
                  children: [
                    Icon(Icons.play_circle_outline, color: Colors.redAccent, size: 18),
                    SizedBox(width: 8),
                    Text(
                      "កម្រិតចាក់ទស្សនា (Watch Quality)",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (watchStreams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text("No streaming qualities available", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: watchStreams.map((stream) {
                      final currentHeight = _playbackController.videoController?.value.size.height;
                      final isActive = currentHeight != null && (stream.videoResolution.height - currentHeight).abs() < 5;
                      
                      return ChoiceChip(
                        label: Text(stream.qualityLabel),
                        selected: isActive,
                        selectedColor: Colors.red,
                        backgroundColor: const Color(0xFF2E2E2E),
                        labelStyle: TextStyle(
                          color: isActive ? Colors.white : Colors.grey[400],
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (selected) {
                          Navigator.pop(context);
                          _playbackController.changeStreamQuality(stream);
                        },
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _playbackController.removeListener(_onPlaybackStateChanged);
    CastController().removeListener(_onCastStateChanged);
    _chewieController?.dispose();
    super.dispose();
  }

  void _onPlaybackStateChanged() {
    if (mounted) {
      setState(() {
        _setupChewie();
        _updateVideoDetails();
      });
    }
  }

  void _setupChewie() {
    final currentVc = _playbackController.videoController;
    
    // Only re-create if the underlying VideoPlayerController instance changes
    if (currentVc == _lastVideoController) {
      return;
    }

    _chewieController?.dispose();
    _chewieController = null;
    _lastVideoController = currentVc;

    if (currentVc != null && currentVc.value.isInitialized) {
      _chewieController = ChewieController(
        videoPlayerController: currentVc,
        autoPlay: _playbackController.isPlaying,
        looping: false,
        showControls: true,
        aspectRatio: currentVc.value.aspectRatio,
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.red),
          ),
        ),
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.red,
          handleColor: Colors.redAccent,
          backgroundColor: Colors.grey[800]!,
          bufferedColor: Colors.grey[500]!,
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return "$minutes:${twoDigits(seconds)}";
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playbackController,
      builder: (context, _) {
        final item = _playbackController.currentItem;
        final hasItem = item != null;

        // Calculate dynamic aspect ratio based on video dimension
        final vc = _playbackController.videoController;
        final double playerAspectRatio = (vc != null && vc.value.isInitialized)
            ? vc.value.aspectRatio
            : 16 / 9;

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              "Now Playing",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
            ),
            centerTitle: true,
          ),
          body: !hasItem
              ? const Center(
                  child: Text(
                    "No media playing",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : SafeArea(
                  child: Column(
                    children: [
                      // Video Player Area
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.55,
                        ),
                        child: AspectRatio(
                          aspectRatio: playerAspectRatio,
                          child: Container(
                            color: Colors.black,
                            child: CastController().isConnected
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.cast_connected,
                                          color: Colors.red,
                                          size: 64,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          "Casting to ${CastController().connectedDevice?.name ?? 'TV'}",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          "សូមរីករាយទស្សនាលើអេក្រង់ TV របស់អ្នក",
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : _playbackController.isBuffering
                                    ? const Center(
                                        child: CircularProgressIndicator(color: Colors.red),
                                      )
                                    : _chewieController != null
                                        ? Chewie(controller: _chewieController!)
                                    : Center(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            item.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) => const Icon(
                                              Icons.movie,
                                              color: Colors.grey,
                                              size: 50,
                                            ),
                                          ),
                                        ),
                                      ),
                          ),
                        ),
                      ),
                      
                      // Progress / Slider bar (sync details)
                      StreamBuilder<Duration>(
                        stream: _playbackController.positionStream,
                        builder: (context, posSnapshot) {
                          final currentPos = posSnapshot.data ?? _playbackController.currentPosition;
                          final totalDur = _playbackController.totalDuration;

                          double sliderValue = 0.0;
                          if (totalDur.inMilliseconds > 0) {
                            sliderValue = currentPos.inMilliseconds / totalDur.inMilliseconds;
                          }
                          sliderValue = sliderValue.clamp(0.0, 1.0);

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Column(
                              children: [
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: Colors.red,
                                    inactiveTrackColor: Colors.grey[800],
                                    trackHeight: 3.0,
                                    thumbColor: Colors.red,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                    overlayColor: Colors.red.withAlpha(32),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                                  ),
                                  child: Slider(
                                    value: sliderValue,
                                    onChanged: (val) {
                                      final newMs = (val * totalDur.inMilliseconds).toInt();
                                      _playbackController.seek(Duration(milliseconds: newMs));
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatDuration(currentPos),
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                      Text(
                                        _formatDuration(totalDur),
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // Meta Title, Channel & Playback Buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FutureBuilder<yt.Video?>(
                              future: _videoDetailsFuture,
                              builder: (context, snapshot) {
                                final video = snapshot.data;
                                
                                String subtitleText = item.author;
                                if (video != null) {
                                  final views = _formatViews(video.engagement.viewCount);
                                  final uploaded = _formatUploadDate(video.uploadDate);
                                  subtitleText = "${item.author} • $views${uploaded.isNotEmpty ? ' • $uploaded' : ''}";
                                }

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            subtitleText,
                                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _buildPlayerFavoriteButton(item),
                                    if (!item.isOffline) ...[
                                      const SizedBox(width: 12),
                                      _buildPlayerQualityButton(),
                                      const SizedBox(width: 12),
                                      _buildPlayerDownloadButton(item),
                                    ],
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            
                            // Audio Controller Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                                  onPressed: _playbackController.playPrevious,
                                ),
                                const SizedBox(width: 20),
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.red,
                                  child: IconButton(
                                    icon: Icon(
                                      _playbackController.isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      size: 32,
                                      color: Colors.white,
                                    ),
                                    onPressed: _playbackController.togglePlay,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                IconButton(
                                  icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
                                  onPressed: _playbackController.playNext,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 15),
                      const Divider(color: Color(0xFF222222), height: 1),

                      // Playlist Queue (Up Next)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 20.0, top: 15.0, bottom: 8.0),
                              child: Text(
                                "Up Next",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: _playbackController.playlist.length,
                                itemBuilder: (context, index) {
                                  final queueItem = _playbackController.playlist[index];
                                  final isActive = index == _playbackController.currentIndex;

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: SizedBox(
                                        width: 80,
                                        height: 45,
                                        child: Image.network(
                                          queueItem.thumbnailUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Container(
                                            color: Colors.grey[900],
                                            child: const Icon(Icons.movie, color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      queueItem.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isActive ? Colors.red : Colors.white,
                                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                    ),
                                    subtitle: Text(
                                      queueItem.author,
                                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                                    ),
                                    trailing: Text(
                                      queueItem.durationString,
                                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                                    ),
                                    onTap: () {
                                      _playbackController.playItem(queueItem, _playbackController.playlist);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  String _formatViews(int? views) {
    if (views == null) return '0 views';
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M views';
    } else if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)}K views';
    } else {
      return '$views views';
    }
  }

  String _formatUploadDate(DateTime? uploadDate) {
    if (uploadDate == null) return '';
    final difference = DateTime.now().difference(uploadDate);
    if (difference.inDays >= 365) {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    } else if (difference.inDays >= 30) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else if (difference.inDays >= 7) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildPlayerQualityButton() {
    final manifest = _playbackController.currentManifest;
    if (manifest == null) return const SizedBox.shrink();
    final muxedStreams = manifest.muxed.toList();
    if (muxedStreams.isEmpty) return const SizedBox.shrink();

    final item = _playbackController.currentItem;
    if (item == null) return const SizedBox.shrink();

    final currentVc = _playbackController.videoController;
    final currentHeight = currentVc?.value.size.height;
    
    String currentLabel = "Quality";
    if (currentHeight != null && currentHeight > 0) {
      final matchingStream = muxedStreams.firstWhere(
        (s) => (s.videoResolution.height - currentHeight).abs() < 5,
        orElse: () => muxedStreams.first,
      );
      currentLabel = matchingStream.qualityLabel;
    } else {
      muxedStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      currentLabel = muxedStreams.first.qualityLabel;
    }

    return CircleAvatar(
      radius: 19,
      backgroundColor: const Color(0xFF2E2E2E),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hd, color: Colors.red, size: 14),
            Text(
              currentLabel.replaceAll('p', ''),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        onPressed: () => _showUnifiedQualitySheet(context, item),
      ),
    );
  }

  void _downloadDefault360p(PlayableItem item) {
    if (item.isOffline) return;

    _downloadService.startDownload(
      id: item.id,
      title: item.title,
      author: item.author,
      thumbnailUrl: item.thumbnailUrl,
      durationString: item.durationString,
      streamInfo: _playbackController.currentManifest?.muxed.isNotEmpty == true
          ? _playbackController.currentManifest!.muxed.first
          : null,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("បានចាប់ផ្តើមទាញយក: ${item.title}"),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildPlayerDownloadButton(PlayableItem item) {
    return StreamBuilder<List<DownloadTask>>(
      stream: _downloadService.tasksStream,
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? _downloadService.tasks;
        final videoTasks = tasks.where((t) => (t.id.contains('@') ? t.id.split('@').first : t.id.split('_').first) == item.id).toList();
        final isDownloading = videoTasks.any((t) => t.isDownloading);

        if (isDownloading) {
          final activeTask = videoTasks.firstWhere((t) => t.isDownloading);
          return GestureDetector(
            onTap: () {
              _downloadService.cancelDownload(activeTask.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Download cancelled"),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${(activeTask.progress * 100).toInt()}%",
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: activeTask.progress,
                        color: Colors.red,
                        backgroundColor: Colors.grey[800],
                        strokeWidth: 3,
                      ),
                      const Icon(Icons.close, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFF2E2E2E),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.download, color: Colors.white, size: 18),
            onPressed: () {
              _downloadDefault360p(item);
            },
          ),
        );
      },
    );
  }

  Widget _buildPlayerFavoriteButton(PlayableItem item) {
    return ListenableBuilder(
      listenable: _favoritesController,
      builder: (context, _) {
        final isFav = _favoritesController.isFavorite(item.id);
        return CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFF2E2E2E),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Colors.red : Colors.white,
              size: 18,
            ),
            onPressed: () {
              _favoritesController.toggleFavorite(item);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isFav 
                      ? "បានលុបពីវីដេអូពេញចិត្ត" 
                      : "បានបន្ថែមទៅវីដេអូពេញចិត្ត"
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class StreamDownloadOption {
  final String qualityLabel;
  final int height;
  final bool isMuxed;
  final yt.StreamInfo videoStreamInfo;
  final double sizeMb;

  StreamDownloadOption({
    required this.qualityLabel,
    required this.height,
    required this.isMuxed,
    required this.videoStreamInfo,
    required this.sizeMb,
  });
}
