import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

const String referralWebBaseUrl = 'https://takhfidsh.alattab.site/';
const String _pendingReferralKey = 'pending_referral_code_v1';

class ReferralLinkService {
  static final AppLinks _links = AppLinks();
  static StreamSubscription<Uri>? _subscription;
  static String? _pending;

  static String? extractCode(Uri uri) {
    final raw = uri.queryParameters['ref'] ??
        uri.queryParameters['invite'] ??
        uri.queryParameters['referral'];
    if (raw == null) return null;
    final code = raw.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{4,20}$').hasMatch(code)) return null;
    return code;
  }

  static Uri referralUri(String code) => Uri.parse(
        referralWebBaseUrl,
      ).replace(queryParameters: {'ref': code.toUpperCase()});

  static Uri appReferralUri(String code) => Uri(
        scheme: 'altakhfid',
        host: 'invite',
        queryParameters: {'ref': code.toUpperCase()},
      );


  static Future<void> initialize() async {
    // The browser already exposes the invitation URL through Uri.base.
    // Avoid waiting for native app-link plumbing during Flutter Web startup;
    // that keeps the first frame independent of deep-link plugin state.
    if (kIsWeb) {
      await _consumeUri(Uri.base);
      return;
    }

    try {
      final initial = await _links.getInitialLink();
      await _consumeUri(initial);
    } catch (_) {}

    _subscription ??= _links.uriLinkStream.listen(
      (uri) => unawaited(_consumeUri(uri)),
      onError: (_) {},
    );
  }

  static Future<void> _consumeUri(Uri? uri) async {
    if (uri == null) return;
    final code = extractCode(uri);
    if (code == null) return;
    _pending = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingReferralKey, code);
    } catch (_) {}
  }

  static Future<String?> pendingCode() async {
    if (_pending != null) return _pending;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_pendingReferralKey);
      final code = value?.trim().toUpperCase();
      if (code != null && RegExp(r'^[A-Z0-9]{4,20}$').hasMatch(code)) {
        _pending = code;
        return code;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> takePendingCode() async {
    final code = await pendingCode();
    _pending = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingReferralKey);
    } catch (_) {}
    return code;
  }

  static Future<void> clearPendingCode() async {
    _pending = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingReferralKey);
    } catch (_) {}
  }
}
