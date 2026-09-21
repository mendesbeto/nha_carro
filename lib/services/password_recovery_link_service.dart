import 'dart:async';

import 'package:app_links/app_links.dart';

class PasswordRecoveryLinkService {
  PasswordRecoveryLinkService({AppLinks? appLinks})
      : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  StreamSubscription<Uri>? _subscription;

  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  void listen(void Function(Uri uri) onLink) {
    _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(onLink);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static String? accessTokenFrom(Uri uri) {
    if (uri.scheme != 'nhacarro' ||
        uri.host != 'auth' ||
        uri.path != '/reset-password') {
      return null;
    }

    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;

    try {
      final params = Uri.splitQueryString(fragment);
      final type = params['type'];
      final accessToken = params['access_token'];

      if (type != null && type != 'recovery') return null;
      if (accessToken == null || accessToken.isEmpty) return null;

      return accessToken;
    } on FormatException {
      return null;
    }
  }
}
