import 'package:flutter/material.dart';
import 'package:cast/cast.dart';

class CastController extends ChangeNotifier {
  static final CastController _instance = CastController._internal();
  factory CastController() => _instance;

  CastController._internal();

  CastDevice? _connectedDevice;
  CastSession? _session;
  bool _isConnecting = false;
  bool _isSearching = false;
  
  CastDevice? get connectedDevice => _connectedDevice;
  CastSession? get session => _session;
  bool get isConnected => _connectedDevice != null && _session != null;
  bool get isConnecting => _isConnecting;
  bool get isSearching => _isSearching;

  List<CastDevice> _discoveredDevices = [];
  List<CastDevice> get discoveredDevices => _discoveredDevices;

  Future<void> startDiscovery() async {
    if (_isSearching) return;
    _isSearching = true;
    _discoveredDevices = [];
    notifyListeners();
    
    try {
      final devices = await CastDiscoveryService().search(timeout: const Duration(seconds: 4));
      _discoveredDevices = devices;
    } catch (e) {
      print("Error during cast discovery: $e");
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void stopDiscovery() {
    // No-op for CastDiscoveryService search timeout
  }

  Future<void> connect(CastDevice device) async {
    _isConnecting = true;
    _connectedDevice = null;
    _session = null;
    notifyListeners();

    try {
      final session = await CastSessionManager().startSession(device);
      
      session.stateStream.listen((state) {
        if (state == CastSessionState.connected) {
          _session = session;
          _connectedDevice = device;
          _isConnecting = false;
          notifyListeners();
        } else if (state == CastSessionState.closed) {
          disconnect();
        }
      });
    } catch (e) {
      print("Error connecting to cast device: $e");
      _isConnecting = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _session = null;
    _connectedDevice = null;
    _isConnecting = false;
    notifyListeners();
  }

  void castVideo(String url, String title, String author, String thumbnailUrl) {
    if (_session == null) return;
    
    _session!.sendMessage('urn:x-cast:com.google.cast.media', {
      'type': 'LOAD',
      'media': {
        'contentId': url,
        'contentType': 'video/mp4',
        'streamType': 'BUFFERED',
        'metadata': {
          'metadataType': 1,
          'title': title,
          'subtitle': author,
          'images': [
            {'url': thumbnailUrl}
          ]
        }
      },
      'autoplay': true,
      'currentTime': 0
    });
  }

  void togglePlay(bool isPlaying) {
    if (_session == null) return;
    _session!.sendMessage('urn:x-cast:com.google.cast.media', {
      'type': isPlaying ? 'PLAY' : 'PAUSE',
    });
  }

  void stop() {
    if (_session == null) return;
    _session!.sendMessage('urn:x-cast:com.google.cast.media', {
      'type': 'STOP',
    });
  }
}
