import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The app's one notifications plugin, initialised once per isolate, so the
/// daily reminder and the new-article notice share it and a tap is routed
/// by its payload. Mobile only (imported from `*_io.dart` files).
abstract final class LocalNotifications {
  static final plugin = FlutterLocalNotificationsPlugin();

  static Future<void>? _ready;

  /// Called with the payload when the user taps a notification while the
  /// app is running (a tap that launches the app: [launchPayload]).
  static void Function(String? payload)? onTap;

  static Future<void> ensureInitialized() => _ready ??= plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (response) =>
        onTap?.call(response.payload),
  );

  /// The payload of the notification that launched the app, if one did.
  static Future<String?> launchPayload() async {
    await ensureInitialized();
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details!.notificationResponse?.payload;
  }

  static AndroidFlutterLocalNotificationsPlugin? get android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
}
