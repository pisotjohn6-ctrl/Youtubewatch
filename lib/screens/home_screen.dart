import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../services/youtube_service.dart';
import '../services/download_service.dart';
import '../controllers/playback_controller.dart';
import '../controllers/favorites_controller.dart';
import '../models/playable_item.dart';
import '../models/download_task.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final YoutubeService _youtubeService = YoutubeService();
  final DownloadService _downloadService = DownloadService();
  final PlaybackController _playbackController = PlaybackController();
  final FavoritesController _favoritesController = FavoritesController();
  
  final TextEditingController _searchController = TextEditingController();
  List<yt.Video> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    // Default search to show some trending/recommended music content on start
    _performSearch("Khmer remix 2026");
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    final results = await _youtubeService.searchVideos(query);
    
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
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
    // Generate playlist queue from search results
    final queue = _searchResults.map((v) => PlayableItem.fromVideo(v)).toList();
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
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 15),
              // YouTube Logo
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "YouTube",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Subtitle Phrases in Khmer OS Freehand
              const Text(
                "រីករាយទស្សនា",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 22,
                  fontFamily: 'Khmer OS Freehand',
                ),
              ),
              const Text(
                "ដោយ៖ យូមាស",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontFamily: 'Khmer OS Freehand',
                ),
              ),
              const SizedBox(height: 15),
              // Search Bar
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.search,
                  onSubmitted: _performSearch,
                  decoration: InputDecoration(
                    hintText: "Search YouTube...",
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                      },
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              // Search Results
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                        ),
                      )
                    : _searchResults.isEmpty
                        ? Center(
                            child: Text(
                              _hasSearched
                                  ? "No results found"
                                  : "Type to search videos",
                              style: const TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          )
                        : StreamBuilder<List<DownloadTask>>(
                            stream: _downloadService.tasksStream,
                            builder: (context, snapshot) {
                              final downloadTasks = snapshot.data ?? _downloadService.tasks;

                              return ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final video = _searchResults[index];
                                  
                                  // Check download status for this video
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
      ),
    );
  }

  Widget _buildVideoCard(yt.Video video, DownloadTask downloadTask) {
    return GestureDetector(
      onTap: () => _playVideo(video),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail & Duration
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      video.thumbnails.mediumResUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[900],
                        child: const Icon(Icons.movie, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      video.duration?.toString().split('.').first ?? '00:00',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Info Row
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${video.author} • ${_formatViews(video.engagement.viewCount)} • ${_formatUploadDate(video.uploadDate)}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Favorite & Download Action Buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFavoriteButton(video),
                      const SizedBox(width: 8),
                      _buildDownloadActionButton(video, downloadTask),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteButton(yt.Video video) {
    final playableItem = PlayableItem.fromVideo(video);
    return ListenableBuilder(
      listenable: _favoritesController,
      builder: (context, _) {
        final isFav = _favoritesController.isFavorite(video.id.value);
        return CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF2E2E2E),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Colors.red : Colors.white,
              size: 18,
            ),
            onPressed: () {
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

  Widget _buildDownloadActionButton(yt.Video video, DownloadTask dTask) {
    if (dTask.isDownloading) {
      return GestureDetector(
        onTap: () {
          _downloadService.cancelDownload(dTask.id);
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
              "${(dTask.progress * 100).toInt()}%",
              style: const TextStyle(
                color: Colors.red,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: dTask.progress,
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
      radius: 18,
      backgroundColor: const Color(0xFF2E2E2E),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.download, color: Colors.white, size: 18),
        onPressed: () => _downloadDefault360p(video),
      ),
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
