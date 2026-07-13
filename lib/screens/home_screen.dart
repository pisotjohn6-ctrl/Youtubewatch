import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../services/youtube_service.dart';
import '../services/download_service.dart';
import '../controllers/playback_controller.dart';
import '../controllers/favorites_controller.dart';
import '../controllers/cast_controller.dart';
import '../models/playable_item.dart';
import '../models/download_task.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final YoutubeService _youtubeService = YoutubeService();
  final DownloadService _downloadService = DownloadService();
  final PlaybackController _playbackController = PlaybackController();
  final FavoritesController _favoritesController = FavoritesController();
  
  List<yt.Video> _searchResults = [];
  List<yt.Video> _shortsList = [];
  bool _isLoading = false;
  String _selectedTag = "All";

  void performSearch(String query) {
    _performSearch(query);
  }

  final List<String> _categories = [
    "All",
    "Music",
    "Gaming",
    "Comedy",
    "Dramas",
    "Remix",
    "Trending",
  ];

  @override
  void initState() {
    super.initState();
    _loadHomeFeed();
    _loadShortsShelf();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _getQueryForTag(String tag) {
    switch (tag) {
      case "All":
        return "Cambodia trending popular";
      case "Music":
        return "Khmer music trending";
      case "Gaming":
        return "MLBB gaming tournament cambodia";
      case "Comedy":
        return "Khmer comedy funny clip";
      case "Dramas":
        return "Khmer drama full series";
      case "Remix":
        return "Khmer remix 2026 tik tok";
      case "Trending":
        return "trending videos";
      default:
        return tag;
    }
  }

  Future<void> _loadHomeFeed() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    
    final query = _getQueryForTag(_selectedTag);
    final results = await _youtubeService.searchVideos(query);
    
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadShortsShelf() async {
    try {
      final searchList = await _youtubeService.searchVideos("shorts comedy music");
      final shorts = searchList.where((v) {
        final dur = v.duration;
        return dur != null && dur.inSeconds <= 90;
      }).toList();
      if (mounted) {
        setState(() {
          _shortsList = shorts;
        });
      }
    } catch (e) {
      print("Error loading shorts shelf: $e");
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _selectedTag = ""; // Clear active tag selection during search
    });

    final results = await _youtubeService.searchVideos(query);
    
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  void _onTagSelected(String tag) {
    setState(() {
      _selectedTag = tag;
    });
    _loadHomeFeed();
  }

  void _downloadDefault360p(yt.Video video) {
    _downloadService.startDownload(
      id: video.id.value,
      title: video.title,
      author: video.author,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      durationString: video.duration?.toString().split('.').first ?? '00:00',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("បានចាប់ផ្តើមទាញយក: ${video.title}"),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _playVideo(yt.Video video) {
    // Generate playlist queue from current list
    final List<PlayableItem> queue = _searchResults.map((v) => PlayableItem.fromVideo(v)).toList();
    final selectedItem = PlayableItem.fromVideo(video);

    _playbackController.playItem(selectedItem, queue);

    // Navigate to player screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PlayerScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          children: [
            // Category Tags (Always visible below the global top bar)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: _buildCategoryTags(),
            ),
            const Divider(color: Color(0xFF2E2E2E), height: 1),

            // Video Feed & Search Results
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    )
                  : _searchResults.isEmpty
                      ? const Center(
                          child: Text(
                            "No videos found",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        )
                      : StreamBuilder<List<DownloadTask>>(
                          stream: _downloadService.tasksStream,
                          builder: (context, snapshot) {
                            final downloadTasks = snapshot.data ?? _downloadService.tasks;
                            
                            bool showShorts = _shortsList.isNotEmpty && _searchResults.length > 2;
                            int itemCount = _searchResults.length + (showShorts ? 1 : 0);

                            return ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: itemCount,
                              itemBuilder: (context, index) {
                                if (showShorts && index == 2) {
                                  return _buildShortsShelf();
                                }

                                final videoIndex = (showShorts && index > 2) ? index - 1 : index;
                                final video = _searchResults[videoIndex];
                                
                                // Get download status
                                final videoTasks = downloadTasks.where((t) => (t.id.contains('@') ? t.id.split('@').first : t.id.split('_').first) == video.id.value).toList();
                                final dTask = videoTasks.firstWhere(
                                  (t) => t.isDownloading,
                                  orElse: () => videoTasks.isNotEmpty
                                      ? videoTasks.first
                                      : DownloadTask(
                                          id: '',
                                          title: '',
                                          author: '',
                                          thumbnailUrl: '',
                                          durationString: '',
                                        ),
                                );

                                return _buildVideoCard(video, dTask);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTags() {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedTag;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  _onTagSelected(cat);
                }
              },
              selectedColor: Colors.white,
              backgroundColor: const Color(0xFF212121),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoCard(yt.Video video, DownloadTask downloadTask) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail & Duration
        GestureDetector(
          onTap: () => _playVideo(video),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.network(
                    video.thumbnails.mediumResUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[900],
                      child: const Icon(Icons.movie, color: Colors.grey, size: 48),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      video.duration?.toString().split('.').first ?? '00:00',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Title & Info
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF212121),
                child: Text(
                  video.author.isNotEmpty ? video.author[0].toUpperCase() : 'Y',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${video.author} • ${_formatViews(video.engagement.viewCount)} • ${_formatUploadDate(video.uploadDate)}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showActionsBottomSheet(video, downloadTask),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showActionsBottomSheet(yt.Video video, DownloadTask downloadTask) {
    final playableItem = PlayableItem.fromVideo(video);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF212121),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const Divider(color: Color(0xFF2E2E2E)),
              ListenableBuilder(
                listenable: _favoritesController,
                builder: (context, _) {
                  final isFav = _favoritesController.isFavorite(video.id.value);
                  return ListTile(
                    leading: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : Colors.white,
                    ),
                    title: Text(
                      isFav ? "លុបពីវីដេអូពេញចិត្ត (Remove Favorite)" : "បន្ថែមទៅវីដេអូពេញចិត្ត (Add Favorite)",
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    onTap: () {
                      _favoritesController.toggleFavorite(playableItem);
                      Navigator.pop(context);
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
                  );
                },
              ),
              StreamBuilder<List<DownloadTask>>(
                stream: _downloadService.tasksStream,
                builder: (context, snapshot) {
                  // Re-evaluate download status
                  final tasks = snapshot.data ?? _downloadService.tasks;
                  final videoTasks = tasks.where((t) => (t.id.contains('@') ? t.id.split('@').first : t.id.split('_').first) == video.id.value).toList();
                  final dTask = videoTasks.firstWhere(
                    (t) => t.isDownloading,
                    orElse: () => videoTasks.isNotEmpty
                        ? videoTasks.first
                        : DownloadTask(
                            id: '',
                            title: '',
                            author: '',
                            thumbnailUrl: '',
                            durationString: '',
                          ),
                  );

                  final isDownloading = dTask.isDownloading;
                  final isDownloaded = dTask.isCompleted;

                  return ListTile(
                    leading: Icon(
                      isDownloading 
                        ? Icons.hourglass_empty 
                        : isDownloaded 
                            ? Icons.check_circle 
                            : Icons.download,
                      color: isDownloading 
                        ? Colors.red 
                        : isDownloaded 
                            ? Colors.green 
                            : Colors.white,
                    ),
                    title: Text(
                      isDownloading 
                        ? "កំពុងទាញយក: ${(dTask.progress * 100).toInt()}% (Cancel)"
                        : isDownloaded
                            ? "បានទាញយករួចរាល់"
                            : "ទាញយកវីដេអូ (Download Video)",
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (isDownloading) {
                        _downloadService.cancelDownload(dTask.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("លុបចោលការទាញយក"),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      } else if (!isDownloaded) {
                        _downloadDefault360p(video);
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShortsShelf() {
    if (_shortsList.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.play_circle_filled, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text(
                "Shorts",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _shortsList.length,
            itemBuilder: (context, index) {
              final video = _shortsList[index];
              return Container(
                width: 130,
                margin: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => _playVideo(video),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.network(
                                  video.thumbnails.mediumResUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(
                                    color: Colors.grey[900],
                                    child: const Icon(Icons.play_arrow, color: Colors.grey, size: 36),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatViews(video.engagement.viewCount),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2E2E2E), thickness: 4),
      ],
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
