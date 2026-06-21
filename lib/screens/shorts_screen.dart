import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../services/youtube_service.dart';
import '../services/download_service.dart';
import 'package:video_player/video_player.dart';
import '../models/download_task.dart';
import '../models/playable_item.dart';
import '../controllers/favorites_controller.dart';


class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key});

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  final YoutubeService _youtubeService = YoutubeService();
  final TextEditingController _searchController = TextEditingController();
  final PageController _pageController = PageController();
  List<yt.Video> _shorts = [];
  yt.VideoSearchList? _currentSearchList;
  bool _isLoading = true;
  bool _isFetchingMore = false;
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadShorts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadShorts({String query = "shorts music"}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _shorts = [];
    });

    try {
      final searchQuery = query.toLowerCase().contains("short") ? query : "$query shorts";
      final searchList = await _youtubeService.getSearchList(searchQuery);
      if (searchList != null) {
        _currentSearchList = searchList;
        final list = searchList.toList();
        final filtered = list.where((v) {
          final dur = v.duration;
          return dur != null && dur.inSeconds <= 90;
        }).toList();

        if (mounted) {
          setState(() {
            _shorts = filtered.isNotEmpty ? filtered : list;
            _isLoading = false;
            _focusedIndex = 0;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreShorts() async {
    if (_isFetchingMore || _currentSearchList == null) return;
    _isFetchingMore = true;

    try {
      final nextPage = await _currentSearchList!.nextPage();
      if (nextPage != null) {
        _currentSearchList = nextPage;
        final list = nextPage.toList();
        final filtered = list.where((v) {
          final dur = v.duration;
          return dur != null && dur.inSeconds <= 90;
        }).toList();

        if (mounted) {
          setState(() {
            _shorts.addAll(filtered.isNotEmpty ? filtered : list);
          });
        }
      }
    } catch (e) {
      print("Error fetching more shorts: $e");
    } finally {
      _isFetchingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_isLoading) {
      content = const Center(
        child: CircularProgressIndicator(color: Colors.red),
      );
    } else if (_shorts.isEmpty) {
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("No Shorts found", style: TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _loadShorts(
                query: _searchController.text.isNotEmpty ? _searchController.text : "shorts music"
              ),
              child: const Text("Retry"),
            )
          ],
        ),
      );
    } else {
      content = PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _shorts.length,
        onPageChanged: (index) {
          if (mounted) {
            setState(() {
              _focusedIndex = index;
            });
          }
          if (index >= _shorts.length - 3) {
            _loadMoreShorts();
          }
        },
        itemBuilder: (context, index) {
          return ShortPlayerItem(
            video: _shorts[index],
            isActive: index == _focusedIndex,
            onNext: () {
              if (index < _shorts.length - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
            onPrev: () {
              if (index > 0) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: content),
          // Floating Search Bar at the top
          Positioned(
            top: 0,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (val) {
                    _loadShorts(query: val);
                  },
                  decoration: InputDecoration(
                    hintText: "Search Shorts...",
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                      onPressed: () {
                        _searchController.clear();
                      },
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShortPlayerItem extends StatefulWidget {
  final yt.Video video;
  final bool isActive;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const ShortPlayerItem({
    super.key,
    required this.video,
    required this.isActive,
    required this.onNext,
    required this.onPrev,
  });

  @override
  State<ShortPlayerItem> createState() => _ShortPlayerItemState();
}

class _ShortPlayerItemState extends State<ShortPlayerItem> {
  final YoutubeService _youtubeService = YoutubeService();
  final DownloadService _downloadService = DownloadService();
  final FavoritesController _favoritesController = FavoritesController();
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoadingStream = true;
  String? _streamUrl;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _initializePlayer();
    }
  }

  @override
  void didUpdateWidget(ShortPlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initializePlayer();
    } else if (!widget.isActive && oldWidget.isActive) {
      _disposePlayer();
    }
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStream = true;
      _isInitialized = false;
    });

    try {
      final manifest = await _youtubeService.getStreamManifest(widget.video.id.value);
      if (manifest != null) {
        final stream = manifest.muxed.reduce((c, n) => c.videoResolution.height > n.videoResolution.height ? c : n);
        _streamUrl = stream.url.toString();
        
        _controller = VideoPlayerController.networkUrl(Uri.parse(_streamUrl!));
        await _controller!.initialize();
        _controller!.setLooping(true);
        
        if (mounted && widget.isActive) {
          setState(() {
            _isInitialized = true;
            _isLoadingStream = false;
          });
          // Auto-play is disabled on opening
        }
      }
    } catch (e) {
      print("Error loading short: $e");
      if (mounted) {
        setState(() {
          _isLoadingStream = false;
        });
      }
    }
  }

  void _disposePlayer() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
    _isLoadingStream = false;
  }

  void _downloadDefault360p() {
    _downloadService.startDownload(
      id: widget.video.id.value,
      title: widget.video.title,
      author: widget.video.author,
      thumbnailUrl: widget.video.thumbnails.mediumResUrl,
      durationString: widget.video.duration?.toString().split('.').first ?? '00:00',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("បានចាប់ផ្តើមទាញយក: ${widget.video.title}"),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return "$minutes:${twoDigits(seconds)}";
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Video player viewport
        Positioned.fill(
          child: _isInitialized && _controller != null
              ? GestureDetector(
                  onTap: () {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  },
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),
                )
              : Center(
                  child: _isLoadingStream
                      ? const CircularProgressIndicator(color: Colors.red)
                      : Container(
                          color: Colors.black,
                          child: const Icon(Icons.error, color: Colors.grey, size: 40),
                        ),
                ),
        ),

        // Bottom gradient mask
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 220,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ),
        ),

        // Play duration indicator overlay
        if (_isInitialized && _controller != null)
          Positioned(
            left: 15,
            bottom: 110,
            child: ValueListenableBuilder(
              valueListenable: _controller!,
              builder: (context, VideoPlayerValue value, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "${_formatDuration(value.position)} / ${_formatDuration(value.duration)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),

        // Actions deck on the right
        Positioned(
          right: 15,
          bottom: 80,
          child: Column(
            children: [
              // Prev Button
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.black.withValues(alpha: 0.5),
                child: IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 22),
                  onPressed: widget.onPrev,
                ),
              ),
              const SizedBox(height: 12),
              // Next Button
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.black.withValues(alpha: 0.5),
                child: IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 22),
                  onPressed: widget.onNext,
                ),
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _favoritesController,
                builder: (context, _) {
                  final isFav = _favoritesController.isFavorite(widget.video.id.value);
                  return CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    child: IconButton(
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.red : Colors.white,
                        size: 24,
                      ),
                      onPressed: () {
                        final playableItem = PlayableItem.fromVideo(widget.video);
                        _favoritesController.toggleFavorite(playableItem);
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
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<DownloadTask>>(
                stream: _downloadService.tasksStream,
                builder: (context, snapshot) {
                  final tasks = snapshot.data ?? _downloadService.tasks;
                  final videoTasks = tasks.where((t) => (t.id.contains('@') ? t.id.split('@').first : t.id.split('_').first) == widget.video.id.value).toList();
                  final isDownloading = videoTasks.any((t) => t.isDownloading);

                  if (isDownloading) {
                    final activeTask = videoTasks.firstWhere((t) => t.isDownloading);
                    return Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            _downloadService.cancelDownload(activeTask.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Download cancelled"),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          },
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.black.withValues(alpha: 0.5),
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
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Cancel (${(activeTask.progress * 100).toInt()}%)",
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        child: IconButton(
                          icon: const Icon(Icons.download, color: Colors.white, size: 22),
                          onPressed: _downloadDefault360p,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text("Download", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // Description/Meta details on the left
        Positioned(
          left: 15,
          bottom: 30,
          right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "@${widget.video.author} • ${_formatViews(widget.video.engagement.viewCount)} • ${_formatUploadDate(widget.video.uploadDate)}",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        // Thin progress bar at the very bottom
        if (_isInitialized && _controller != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder(
              valueListenable: _controller!,
              builder: (context, VideoPlayerValue value, child) {
                final progress = value.duration.inMilliseconds > 0
                    ? value.position.inMilliseconds / value.duration.inMilliseconds
                    : 0.0;
                return SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  ),
                );
              },
            ),
          ),
      ],
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
