import 'package:flutter/material.dart';
import '../services/download_service.dart';
import '../controllers/playback_controller.dart';
import '../models/playable_item.dart';
import '../models/download_task.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadService _downloadService = DownloadService();
  final PlaybackController _playbackController = PlaybackController();

  void _playOfflineVideo(DownloadTask task, List<DownloadTask> allCompletedTasks) {
    final queue = allCompletedTasks.map((t) => PlayableItem.fromDownloadTask(t)).toList();
    final selectedItem = PlayableItem.fromDownloadTask(task);

    _playbackController.playItem(selectedItem, queue);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PlayerScreen(),
      ),
    );
  }

  void _deleteDownload(DownloadTask task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Delete Video", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to delete '${task.title}'?", style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _downloadService.deleteTask(task);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Video deleted"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Text(
          "Downloads",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<DownloadTask>>(
        stream: _downloadService.tasksStream,
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? _downloadService.tasks;
          final completedTasks = tasks.where((t) => t.isCompleted).toList();

          if (completedTasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_for_offline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No downloaded videos yet",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            physics: const BouncingScrollPhysics(),
            children: completedTasks.map((task) => _buildOfflineCard(task, completedTasks)).toList(),
          );
        },
      ),
    );
  }

  Widget _buildOfflineCard(DownloadTask task, List<DownloadTask> completedTasks) {
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
                  task.thumbnailUrl,
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
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    task.durationString,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        title: Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            task.author,
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.grey),
          onPressed: () => _deleteDownload(task),
        ),
        onTap: () => _playOfflineVideo(task, completedTasks),
      ),
    );
  }
}
