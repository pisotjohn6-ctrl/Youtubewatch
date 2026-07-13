import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../models/playable_item.dart';
import '../services/youtube_service.dart';
import '../controllers/cast_controller.dart';

class PlaybackController extends ChangeNotifier with WidgetsBindingObserver {
  // Singleton Pattern
  static final PlaybackController _instance = PlaybackController._internal();
  factory PlaybackController() => _instance;

  PlaybackController._internal() {
    WidgetsBinding.instance.addObserver(this);
    _initAudioPlayer();
  }

  final YoutubeService _youtubeService = YoutubeService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  VideoPlayerController? _videoController;
  yt.StreamManifest? _currentManifest;
  AudioSource? _currentAudioSource;
  String? _currentLoadedAudioId;
  final Map<String, yt.StreamManifest> _manifestCache = {};

  List<PlayableItem> _playlist = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isVideoActive = true;
  bool _isBuffering = false;
  bool _isTransitioning = false;

  // Casting state
  Timer? _castProgressTimer;
  Duration _castPosition = Duration.zero;
  Duration _castDuration = Duration.zero;

  void _startCastProgressTimer() {
    _castProgressTimer?.cancel();
    _castProgressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPlaying && CastController().isConnected) {
        if (_castPosition < _castDuration) {
          _castPosition += const Duration(seconds: 1);
          _positionController.add(_castPosition);
          notifyListeners();
        } else {
          playNext();
        }
      }
    });
  }

  void _stopCastProgressTimer() {
    _castProgressTimer?.cancel();
    _castProgressTimer = null;
  }

  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();

  // Getters
  List<PlayableItem> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  PlayableItem? get currentItem => (_currentIndex >= 0 && _currentIndex < _playlist.length) ? _playlist[_currentIndex] : null;
  bool get isPlaying => _isPlaying;
  bool get isVideoActive => _isVideoActive;
  bool get isBuffering => _isBuffering;
  VideoPlayerController? get videoController => _videoController;
  AudioPlayer get audioPlayer => _audioPlayer;
  yt.StreamManifest? get currentManifest => _currentManifest;

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  Duration get currentPosition {
    if (CastController().isConnected) {
      return _castPosition;
    }
    if (_isVideoActive && _videoController != null && _videoController!.value.isInitialized) {
      return _videoController!.value.position;
    }
    return _audioPlayer.position;
  }

  Duration get totalDuration {
    if (CastController().isConnected) {
      return _castDuration;
    }
    if (_isVideoActive && _videoController != null && _videoController!.value.isInitialized) {
      return _videoController!.value.duration;
    }
    return _audioPlayer.duration ?? Duration.zero;
  }

  void _initAudioPlayer() async {
    _audioPlayer.setVolume(1.0);
    
    // Configure audio attributes so Android knows this is media/music
    await _audioPlayer.setAndroidAudioAttributes(AndroidAudioAttributes(
      contentType: AndroidAudioContentType.music,
      usage: AndroidAudioUsage.media,
    ));

    // Request audio focus and activate the audio session
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (e) {
      print("Error activating AudioSession: $e");
    }

    // Listen for background player status
    _audioPlayer.playerStateStream.listen((state) {
      if (!_isVideoActive) {
        _isPlaying = state.playing;
        
        final isBufferingNow = state.processingState == ProcessingState.buffering || 
                              state.processingState == ProcessingState.loading;
        if (isBufferingNow != _isBuffering) {
          _isBuffering = isBufferingNow;
          notifyListeners();
        }

        if (state.processingState == ProcessingState.completed) {
          playNext();
        }
        notifyListeners();
      }
    });

    _audioPlayer.positionStream.listen((pos) {
      if (!_isVideoActive) {
        _positionController.add(pos);
      }
    });

    _audioPlayer.durationStream.listen((dur) {
      if (!_isVideoActive && dur != null) {
        _durationController.add(dur);
      }
    });
  }

  void _videoListener() {
    if (_videoController == null || !_isVideoActive) return;

    _positionController.add(_videoController!.value.position);
    _durationController.add(_videoController!.value.duration);

    final isBufferingNow = _videoController!.value.isBuffering;
    if (isBufferingNow != _isBuffering) {
      _isBuffering = isBufferingNow;
      notifyListeners();
    }

    // Auto-play next when video finishes
    if (_videoController!.value.position >= _videoController!.value.duration &&
        _videoController!.value.duration > Duration.zero &&
        !_videoController!.value.isPlaying &&
        _isPlaying) {
      playNext();
    }
  }

  Future<void> playItem(PlayableItem item, List<PlayableItem> queue) async {
    if (_isTransitioning) return;
    _isTransitioning = true;

    try {
      _isBuffering = true;
      _isPlaying = false;
      notifyListeners();

      await stop();

      _playlist = List.from(queue);
      _currentIndex = _playlist.indexWhere((t) => t.id == item.id);
      if (_currentIndex == -1) {
        _playlist.insert(0, item);
        _currentIndex = 0;
      }

      await _initializeCurrentItem();
    } finally {
      _isTransitioning = false;
    }
  }

  void _addToCache(String id, yt.StreamManifest manifest) {
    if (_manifestCache.length >= 20) {
      _manifestCache.remove(_manifestCache.keys.first);
    }
    _manifestCache[id] = manifest;
  }

  void _prefetchNextItem() {
    if (_playlist.isEmpty || _currentIndex == -1) return;
    int nextIndex = _currentIndex + 1;
    if (nextIndex >= _playlist.length) {
      nextIndex = 0; // Wrap around
    }
    final nextItem = _playlist[nextIndex];
    if (nextItem.isOffline || _manifestCache.containsKey(nextItem.id)) return;

    _youtubeService.getStreamManifest(nextItem.id).then((manifest) {
      if (manifest != null) {
        _addToCache(nextItem.id, manifest);
        print("Prefetched manifest for next song: ${nextItem.title}");
      }
    }).catchError((e) {
      print("Error prefetching manifest: $e");
    });
  }

  Future<void> _initializeCurrentItem() async {
    final item = currentItem;
    if (item == null) return;

    _isBuffering = true;
    notifyListeners();

    try {
      String? videoUrl;
      String? audioUrl;

      if (item.isOffline) {
        videoUrl = item.localPath;
        audioUrl = item.localPath;
      } else {
        yt.StreamManifest? manifest;
        if (_manifestCache.containsKey(item.id)) {
          manifest = _manifestCache[item.id];
          print("Using cached manifest for song: ${item.title}");
        } else {
          manifest = await _youtubeService.getStreamManifest(item.id);
          if (manifest != null) {
            _addToCache(item.id, manifest);
          }
        }

        if (manifest != null) {
          _currentManifest = manifest;
          
          // Select highest resolution muxed stream (typically 720p) which is 16-aligned
          // and avoids rendering stride corruption on Android emulators like LD Player.
          final videoStream = manifest.muxed.reduce((curr, next) => curr.videoResolution.height > next.videoResolution.height ? curr : next);

          final audioStream = manifest.audio.reduce((curr, next) => curr.bitrate.bitsPerSecond > next.bitrate.bitsPerSecond ? curr : next);
          videoUrl = videoStream.url.toString();
          audioUrl = audioStream.url.toString();
        }
      }

      if (videoUrl == null || audioUrl == null) {
        throw Exception("Could not retrieve stream URLs");
      }

      if (CastController().isConnected) {
        CastController().castVideo(
          videoUrl,
          item.title,
          item.author,
          item.thumbnailUrl,
        );
        _isPlaying = true;
        _isBuffering = false;

        if (item.durationString.isNotEmpty) {
          final parts = item.durationString.split(':');
          if (parts.length == 2) {
            _castDuration = Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
          } else if (parts.length == 3) {
            _castDuration = Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1]), seconds: int.parse(parts[2]));
          } else {
            _castDuration = Duration(seconds: int.parse(parts[0]));
          }
        } else {
          _castDuration = Duration.zero;
        }
        _castPosition = Duration.zero;
        _durationController.add(_castDuration);
        _positionController.add(_castPosition);
        _startCastProgressTimer();
        notifyListeners();

        await _audioPlayer.stop();
        if (_videoController != null) {
          _videoController!.removeListener(_videoListener);
          await _videoController!.pause();
          await _videoController!.dispose();
          _videoController = null;
        }
        return;
      }

      // Initialize AudioPlayer source metadata
      final audioSource = AudioSource.uri(
        item.isOffline ? Uri.file(audioUrl) : Uri.parse(audioUrl),
        tag: MediaItem(
          id: item.id,
          album: item.author,
          title: item.title,
          artUri: Uri.parse(item.thumbnailUrl),
        ),
      );
      _currentAudioSource = audioSource;

      // Initialize VideoPlayer (if foreground)
      if (_isVideoActive) {
        if (item.isOffline) {
          _videoController = VideoPlayerController.file(File(videoUrl));
        } else {
          _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        }

        await _videoController!.initialize();
        _videoController!.addListener(_videoListener);
        await _videoController!.play();
        _isPlaying = true;
        _isBuffering = false;
        notifyListeners();

        // Load audio source in background immediately so it is preloaded and cached!
        if (_currentLoadedAudioId != item.id) {
          _audioPlayer.setAudioSource(audioSource).then((_) {
            _currentLoadedAudioId = item.id;
          }).catchError((e) {
            print("Background audio source error: $e");
            return null;
          });
        }
      } else {
        await _audioPlayer.setAudioSource(audioSource);
        _currentLoadedAudioId = item.id;
        await _audioPlayer.play();
        _isPlaying = true;
        _isBuffering = false;
        notifyListeners();
      }

      // Prefetch the next song's details in the background
      _prefetchNextItem();
    } catch (e) {
      print("Initialization error: $e");
      _isBuffering = false;
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (currentItem == null) return;

    if (CastController().isConnected) {
      _isPlaying = !_isPlaying;
      CastController().togglePlay(_isPlaying);
      if (_isPlaying) {
        _startCastProgressTimer();
      } else {
        _stopCastProgressTimer();
      }
      notifyListeners();
      return;
    }

    if (_isPlaying) {
      if (_isVideoActive && _videoController != null) {
        await _videoController!.pause();
      } else {
        await _audioPlayer.pause();
      }
      _isPlaying = false;
    } else {
      if (_isVideoActive && _videoController != null) {
        await _videoController!.play();
      } else {
        await _audioPlayer.play();
      }
      _isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (CastController().isConnected) {
      CastController().session?.sendMessage('urn:x-cast:com.google.cast.media', {
        'type': 'SEEK',
        'currentTime': position.inSeconds,
      });
      _castPosition = position;
      _positionController.add(_castPosition);
      notifyListeners();
      return;
    }

    if (_isVideoActive && _videoController != null) {
      await _videoController!.seekTo(position);
    } else {
      await _audioPlayer.seek(position);
    }
    notifyListeners();
  }

  Future<void> changeStreamQuality(yt.VideoStreamInfo selectedStream) async {
    if (currentItem == null || currentItem!.isOffline || _videoController == null) return;
    
    _isBuffering = true;
    _isPlaying = false;
    notifyListeners();

    final position = _videoController!.value.position;
    final wasPlaying = _videoController!.value.isPlaying;

    _videoController!.removeListener(_videoListener);
    await _videoController!.pause();
    await _videoController!.dispose();

    // Initialize with new stream URL
    _videoController = VideoPlayerController.networkUrl(selectedStream.url);
    await _videoController!.initialize();
    _videoController!.addListener(_videoListener);
    await _videoController!.seekTo(position);
    
    if (wasPlaying) {
      await _videoController!.play();
      _isPlaying = true;
    } else {
      _isPlaying = false;
    }

    _isBuffering = false;
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_isTransitioning || _playlist.isEmpty) return;
    _isTransitioning = true;

    try {
      int nextIndex = _currentIndex + 1;
      if (nextIndex >= _playlist.length) {
        nextIndex = 0; // Wrap around
      }
      await stop();
      _currentIndex = nextIndex;
      await _initializeCurrentItem();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> playPrevious() async {
    if (_isTransitioning || _playlist.isEmpty) return;
    _isTransitioning = true;

    try {
      int prevIndex = _currentIndex - 1;
      if (prevIndex < 0) {
        prevIndex = _playlist.length - 1;
      }
      await stop();
      _currentIndex = prevIndex;
      await _initializeCurrentItem();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> stop() async {
    _isPlaying = false;
    _currentManifest = null;
    _currentAudioSource = null;
    _currentLoadedAudioId = null;
    _stopCastProgressTimer();
    _castPosition = Duration.zero;
    _castDuration = Duration.zero;
    if (_videoController != null) {
      _videoController!.removeListener(_videoListener);
      await _videoController!.pause();
      await _videoController!.dispose();
      _videoController = null;
    }
    await _audioPlayer.stop();
    if (CastController().isConnected) {
      CastController().stop();
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Transition to BACKGROUND
      if (_isVideoActive && _videoController != null && _videoController!.value.isInitialized) {
        _isVideoActive = false;
        final position = _videoController!.value.position;
        final wasPlaying = _videoController!.value.isPlaying;

        // Clean up video player state listener but keep player instance alive
        _videoController!.removeListener(_videoListener);

        if (wasPlaying && currentItem != null) {
          try {
            _isPlaying = true;
            // If background audio source hasn't loaded yet due to delayed load, set it immediately
            if (_currentLoadedAudioId != currentItem!.id && _currentAudioSource != null) {
              _audioPlayer.setAudioSource(_currentAudioSource!);
              _currentLoadedAudioId = currentItem!.id;
            }
            _audioPlayer.setVolume(1.0); // Ensure volume is not ducked on background transition
            // Play immediately and seek without await to start the foreground service
            // while the app is still in the foreground.
            _audioPlayer.seek(position);
            _audioPlayer.play();
          } catch (e) {
            print("Background audio playback error: $e");
          }
        }
        _videoController!.pause(); // Unawaited pause for instant transition
        notifyListeners();
      }
    } else if (state == AppLifecycleState.resumed) {
      // Transition to FOREGROUND
      if (!_isVideoActive) {
        _isVideoActive = true;
        final position = _audioPlayer.position;
        final wasPlaying = _audioPlayer.playing;

        _audioPlayer.pause(); // Unawaited pause

        if (currentItem != null) {
          try {
            // Check if existing controller is still initialized and valid
            if (_videoController != null && _videoController!.value.isInitialized) {
              _videoController!.removeListener(_videoListener); // Prevent duplicates
              _videoController!.addListener(_videoListener);
              _videoController!.seekTo(position).then((_) {
                if (_isVideoActive && wasPlaying) {
                  _videoController!.play();
                }
              });

              if (wasPlaying) {
                _isPlaying = true;
              } else {
                _isPlaying = false;
              }
              notifyListeners();
            } else {
              // Fallback: Re-create the controller if it was released or became invalid
              _isBuffering = true;
              notifyListeners();

              if (_videoController != null) {
                _videoController!.removeListener(_videoListener);
                await _videoController!.dispose();
              }

              String? videoUrl;
              if (currentItem!.isOffline) {
                videoUrl = currentItem!.localPath;
                _videoController = VideoPlayerController.file(File(videoUrl!));
              } else {
                final manifest = await _youtubeService.getStreamManifest(currentItem!.id);
                if (manifest != null) {
                  final videoStream = manifest.muxed.reduce((curr, next) => curr.videoResolution.height > next.videoResolution.height ? curr : next);
                  videoUrl = videoStream.url.toString();
                }
                if (videoUrl != null) {
                  _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
                }
              }

              if (_videoController != null) {
                await _videoController!.initialize();
                _videoController!.addListener(_videoListener);
                await _videoController!.seekTo(position);

                if (wasPlaying) {
                  await _videoController!.play();
                  _isPlaying = true;
                } else {
                  _isPlaying = false;
                }
              }
              _isBuffering = false;
              notifyListeners();
            }
          } catch (e) {
            print("Resuming video player error: $e");
            _isBuffering = false;
            notifyListeners();
          }
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stop();
    _audioPlayer.dispose();
    _positionController.close();
    _durationController.close();
    _youtubeService.close();
    super.dispose();
  }
}
