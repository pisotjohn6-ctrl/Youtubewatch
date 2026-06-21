import 'package:flutter/material.dart';
import '../controllers/favorites_controller.dart';
import '../controllers/playback_controller.dart';
import '../models/playable_item.dart';
import 'player_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoritesController _favoritesController = FavoritesController();
  final PlaybackController _playbackController = PlaybackController();

  void _playVideo(PlayableItem item) {
    final queue = _favoritesController.favorites;
    _playbackController.playItem(item, queue);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PlayerScreen(),
      ),
    );
  }

  void _playAll() {
    if (_favoritesController.favorites.isEmpty) return;
    final firstItem = _favoritesController.favorites.first;
    _playVideo(firstItem);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text(
          "វីដេអូពេញចិត្ត",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          ListenableBuilder(
            listenable: _favoritesController,
            builder: (context, _) {
              if (_favoritesController.favorites.isEmpty) {
                return const SizedBox.shrink();
              }
              return TextButton.icon(
                onPressed: _playAll,
                icon: const Icon(Icons.play_arrow, color: Colors.red),
                label: const Text(
                  "ចាក់ទាំងអស់",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _favoritesController,
        builder: (context, _) {
          final favorites = _favoritesController.favorites;

          if (favorites.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "មិនទាន់មានវីដេអូពេញចិត្តនៅឡើយទេ",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            physics: const BouncingScrollPhysics(),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final item = favorites[index];
              return _buildFavoriteCard(item);
            },
          );
        },
      ),
    );
  }

  Widget _buildFavoriteCard(PlayableItem item) {
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              SizedBox(
                width: 100,
                height: 56,
                child: Image.network(
                  item.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.movie, color: Colors.grey),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    item.durationString,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            item.author,
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.favorite, color: Colors.red),
          onPressed: () {
            _favoritesController.toggleFavorite(item);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("បានលុបពីវីដេអូពេញចិត្ត"),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        onTap: () => _playVideo(item),
      ),
    );
  }
}
