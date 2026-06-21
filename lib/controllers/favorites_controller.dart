import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playable_item.dart';

class FavoritesController extends ChangeNotifier {
  // Singleton Pattern
  static final FavoritesController _instance = FavoritesController._internal();
  factory FavoritesController() => _instance;

  FavoritesController._internal() {
    _loadFavorites();
  }

  List<PlayableItem> _favorites = [];
  List<PlayableItem> get favorites => _favorites;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (!_isInitialized) {
      await _loadFavorites();
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('favorites') ?? [];
      _favorites = list.map((itemStr) {
        final map = jsonDecode(itemStr) as Map<String, dynamic>;
        return PlayableItem.fromJson(map);
      }).toList();
    } catch (e) {
      print("Error loading favorites: $e");
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _favorites.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList('favorites', list);
    } catch (e) {
      print("Error saving favorites: $e");
    }
  }

  bool isFavorite(String id) {
    return _favorites.any((item) => item.id == id);
  }

  Future<void> toggleFavorite(PlayableItem item) async {
    final index = _favorites.indexWhere((f) => f.id == item.id);
    if (index >= 0) {
      _favorites.removeAt(index);
    } else {
      _favorites.add(item);
    }
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> addFavorite(PlayableItem item) async {
    if (!isFavorite(item.id)) {
      _favorites.add(item);
      notifyListeners();
      await _saveFavorites();
    }
  }

  Future<void> removeFavorite(String id) async {
    _favorites.removeWhere((item) => item.id == id);
    notifyListeners();
    await _saveFavorites();
  }
}
