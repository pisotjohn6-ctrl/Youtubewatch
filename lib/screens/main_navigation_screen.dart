import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../controllers/playback_controller.dart';
import 'home_screen.dart';
import 'shorts_screen.dart';
import 'favorites_screen.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final PlaybackController _playbackController = PlaybackController();

  final List<Widget> _pages = [
    const HomeScreen(),
    const ShortsScreen(),
    const FavoritesScreen(),
    const DownloadsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
  }

  Future<void> _requestNotificationPermission() async {
    // Request notification permission for Android 13+ background audio notifications
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playbackController,
      builder: (context, _) {
        final item = _playbackController.currentItem;
        final hasActiveItem = item != null;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Stack(
            children: [
              // Active page view (offset if miniplayer is active)
              Padding(
                padding: EdgeInsets.only(bottom: hasActiveItem ? 64.0 : 0.0),
                child: IndexedStack(
                  index: _currentIndex,
                  children: _pages,
                ),
              ),
              // Floating MiniPlayer
              if (hasActiveItem)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 0, // Float just above the bottom navigation bar
                  child: _buildMiniPlayer(item),
                ),
            ],
          ),
          bottomNavigationBar: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: const Color(0xFF1E1E1E),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              selectedItemColor: Colors.red,
              unselectedItemColor: Colors.grey,
              showUnselectedLabels: true,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.video_library),
                  label: "Video",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.play_circle_outline),
                  label: "Shorts",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.favorite),
                  label: "Favorite",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.download_for_offline),
                  label: "Downloads",
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniPlayer(dynamic item) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const PlayerScreen(),
          ),
        );
      },
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 8,
              offset: const Offset(0, -2),
            )
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  // Video Thumbnail
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                    child: SizedBox(
                      width: 80,
                      height: 58,
                      child: Image.network(
                        item.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Container(
                          color: Colors.grey[900],
                          child: const Icon(Icons.movie, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Title & Channel
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  // Controls
                  IconButton(
                    icon: Icon(
                      _playbackController.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: _playbackController.togglePlay,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white, size: 24),
                    onPressed: _playbackController.playNext,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: _playbackController.stop,
                  ),
                ],
              ),
            ),
            // Progress Bar at the very bottom
            StreamBuilder<Duration>(
              stream: _playbackController.positionStream,
              builder: (context, posSnapshot) {
                final currentPos = posSnapshot.data ?? _playbackController.currentPosition;
                final totalDur = _playbackController.totalDuration;

                double progress = 0.0;
                if (totalDur.inMilliseconds > 0) {
                  progress = currentPos.inMilliseconds / totalDur.inMilliseconds;
                }
                progress = progress.clamp(0.0, 1.0);

                return SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
