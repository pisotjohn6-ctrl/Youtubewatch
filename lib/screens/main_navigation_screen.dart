import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cast/cast.dart';
import '../controllers/playback_controller.dart';
import '../controllers/cast_controller.dart';
import 'home_screen.dart';
import 'shorts_screen.dart';
import 'favorites_screen.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  static bool pendingSearchActivation = false;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final PlaybackController _playbackController = PlaybackController();
  final CastController _castController = CastController();

  final GlobalKey<HomeScreenState> _homeScreenKey = GlobalKey<HomeScreenState>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;
  Timer? _debounce;

  late final List<Widget> _pages = [
    HomeScreen(key: _homeScreenKey),
    const ShortsScreen(),
    const FavoritesScreen(),
    const DownloadsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void activateSearch() {
    setState(() {
      _isSearching = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _performSearch(query, collapseSearchBar: false);
    });
  }

  Future<void> _requestNotificationPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  void _performSearch(String query, {bool collapseSearchBar = false}) {
    if (query.trim().isEmpty) return;
    setState(() {
      _currentIndex = 0; // Force switch to Video/Home feed tab
      if (collapseSearchBar) {
        _isSearching = false;
        _searchFocusNode.unfocus();
      }
    });
    // Trigger search in HomeScreenState
    _homeScreenKey.currentState?.performSearch(query);
  }

  void _showCastDevicePickerDialog() {
    _castController.startDiscovery();
    
    showDialog(
      context: context,
      builder: (context) {
        return ListenableBuilder(
          listenable: _castController,
          builder: (context, _) {
            final devices = _castController.discoveredDevices;
            final isConnected = _castController.isConnected;
            final connectedDevice = _castController.connectedDevice;
            final isConnecting = _castController.isConnecting;

            return AlertDialog(
              backgroundColor: const Color(0xFF212121),
              title: const Row(
                children: [
                  Icon(Icons.cast, color: Colors.white),
                  SizedBox(width: 8),
                  Text("ជ្រើសរើស TV (Select TV)", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 250,
                child: isConnecting
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.red)),
                            SizedBox(height: 16),
                            Text("កំពុងភ្ជាប់ទៅកាន់ TV...", style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          if (isConnected && connectedDevice != null) ...[
                            ListTile(
                              leading: const Icon(Icons.cast_connected, color: Colors.green),
                              title: Text(connectedDevice.name, style: const TextStyle(color: Colors.white)),
                              subtitle: const Text("បានភ្ជាប់រួចរាល់ (Connected)", style: TextStyle(color: Colors.grey)),
                              trailing: TextButton(
                                onPressed: () {
                                  _castController.disconnect();
                                  Navigator.pop(context);
                                },
                                child: const Text("Disconnect", style: TextStyle(color: Colors.red)),
                              ),
                            ),
                            const Divider(color: Colors.grey),
                          ],
                          Expanded(
                            child: _castController.isSearching
                                ? const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.red)),
                                        SizedBox(height: 12),
                                        Text("កំពុងស្វែងរកឧបករណ៍ TV...", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                      ],
                                    ),
                                  )
                                : devices.isEmpty
                                    ? const Center(
                                        child: Text("រកមិនឃើញឧបករណ៍ TV ទេ (No TV found)", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                      )
                                    : ListView.builder(
                                        itemCount: devices.length,
                                        itemBuilder: (context, index) {
                                          final dev = devices[index];
                                          if (isConnected && connectedDevice?.serviceName == dev.serviceName) {
                                            return const SizedBox.shrink();
                                          }

                                          return ListTile(
                                            leading: const Icon(Icons.tv, color: Colors.white),
                                            title: Text(dev.name, style: const TextStyle(color: Colors.white)),
                                            onTap: () async {
                                              await _castController.connect(dev);
                                              if (mounted) {
                                                Navigator.pop(context);
                                              }
                                            },
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
              ),
              actions: [
                if (!_castController.isSearching && !isConnecting)
                  TextButton(
                    onPressed: () {
                      _castController.startDiscovery();
                    },
                    child: const Text("ស្វែងរកឡើងវិញ (Rescan)", style: TextStyle(color: Colors.red)),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("បិទ (Close)", style: TextStyle(color: Colors.grey)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTopBar() {
    if (_isSearching) {
      return Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF212121),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchFocusNode.unfocus();
                });
              },
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textInputAction: TextInputAction.search,
                onSubmitted: (val) => _performSearch(val, collapseSearchBar: true),
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: "Search YouTube...",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white, size: 18),
              onPressed: () {
                _searchController.clear();
                _homeScreenKey.currentState?.resetFeed();
              },
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  "YouTube",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              "Enjoy Watch (ដោយ៖ ហួត យូមាស)",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const Spacer(),
        ListenableBuilder(
          listenable: _castController,
          builder: (context, _) {
            final isConnected = _castController.isConnected;
            return IconButton(
              icon: Icon(
                isConnected ? Icons.cast_connected : Icons.cast,
                color: isConnected ? Colors.red : Colors.white,
                size: 22,
              ),
              onPressed: _showCastDevicePickerDialog,
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white, size: 22),
          onPressed: () {
            setState(() {
              _isSearching = true;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _searchFocusNode.requestFocus();
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MainNavigationScreen.pendingSearchActivation) {
      MainNavigationScreen.pendingSearchActivation = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        activateSearch();
      });
    }
    return ListenableBuilder(
      listenable: _playbackController,
      builder: (context, _) {
        final item = _playbackController.currentItem;
        final hasActiveItem = item != null;

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          body: SafeArea(
            child: Column(
              children: [
                // Global Header Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: _buildTopBar(),
                ),
                const Divider(color: Color(0xFF2E2E2E), height: 1),

                // Main Stack Area
                Expanded(
                  child: Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: hasActiveItem ? 64.0 : 0.0),
                        child: IndexedStack(
                          index: _currentIndex,
                          children: _pages,
                        ),
                      ),
                      if (hasActiveItem)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 0,
                          child: _buildMiniPlayer(item),
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
              type: BottomNavigationBarType.fixed,
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
