import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_sound_stub.dart'
    if (dart.library.js_interop) 'notification_sound_web.dart';

/// Manages the Admin Panel notification bell chime and persisted mute state.
class NotificationSoundService extends ChangeNotifier {
  NotificationSoundService._();
  static final NotificationSoundService instance = NotificationSoundService._();

  static const String _prefKey = 'staff_notif_sound_muted';

  bool _isMuted = false;
  bool _loaded = false;

  bool get isMuted => _isMuted;

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isMuted = prefs.getBool(_prefKey) ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, _isMuted);
    } catch (_) {}
  }

  Future<void> playBellChime() async {
    await init();
    if (_isMuted) return;
    playNotificationBellChimeImpl();
  }
}
