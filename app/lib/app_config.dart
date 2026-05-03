/// Central place to configure the backend base URL for the Flutter app.
///
/// You can override this at build/run time with:
/// flutter run --dart-define=BACKEND_URL=http://your-ip:5000
///
/// In production, set BACKEND_URL to your HTTPS API.
class AppConfig {
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    // PRODUCTION: https://abline.admarktech.cloud
    defaultValue: 'https://abline.admarktech.cloud',
  );

  static const String agoraAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '1400d886612b4896986d7db16b0bbc44',
  );

  /// Normalized base URL with no trailing slash.
  static String get backendBaseUrl {
    if (backendUrl.endsWith('/')) {
      return backendUrl.substring(0, backendUrl.length - 1);
    }
    return backendUrl;
  }
}
