/// Central configuration for the third customer app's Flask API.
class ApiConfig {
  ApiConfig._();

  /// Override with --dart-define=API_BASE_URL=https://example.test/api/v1
  static const String configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://takhfidsh.alattab.site/api/v1',
  );

  /// Dio needs a trailing slash so relative paths remain under /api/v1.
  static String get baseUrl => normalizeBaseUrl(configuredBaseUrl);

  static String normalizeBaseUrl(String rawUrl) {
    final value = rawUrl.trim();
    final uri = Uri.tryParse(value);

    if (uri == null ||
        !uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw FormatException(
        'API_BASE_URL must be an absolute HTTP(S) URL without credentials, query, or fragment.',
        rawUrl,
      );
    }

    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: '${path.isEmpty ? '' : path}/').toString();
  }

  /// Resolves media paths against the host root, not under /api/v1.
  static String resolveMediaUrl(String mediaPath, {String? apiBaseUrl}) {
    final value = mediaPath.trim();
    if (value.isEmpty) return '';

    final mediaUri = Uri.tryParse(value);
    if (mediaUri == null || (mediaUri.hasAuthority && !mediaUri.hasScheme)) {
      throw FormatException('Invalid media URL.', mediaPath);
    }

    if (mediaUri.hasScheme) {
      if (!const {'http', 'https'}.contains(mediaUri.scheme.toLowerCase()) ||
          mediaUri.host.isEmpty) {
        throw FormatException('Media URL must use HTTP(S).', mediaPath);
      }
      return mediaUri.toString();
    }

    final base = Uri.parse(normalizeBaseUrl(apiBaseUrl ?? configuredBaseUrl));
    final origin = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    );
    final rootedPath = value.startsWith('/') ? value : '/$value';
    return origin.resolve(rootedPath).toString();
  }
}
