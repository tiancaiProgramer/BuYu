// Community maintenance and new features: tiancaiProgramer.

/// Only official login response fields are persisted, alongside encrypted cookies.
/// OAuth expiry and music-key expiry are different; never infer one from the other.
class QqSessionMetadata {
  static const names = {
    'openid',
    'unionid',
    'access_token',
    'refresh_token',
    'refresh_key',
    'expired_in',
    'expired_at',
    'musickeyCreateTime',
    'keyExpiresIn',
    'needRefreshKeyIn',
    'loginType',
    'receivedAt',
    'renewalMethod',
    'lastRenewalAt',
    'lastRenewalKeyChanged',
  };

  static Map<String, dynamic> read(Map value) {
    final result = <String, dynamic>{
      for (final name in names)
        if (value[name] is String || value[name] is num) name: value[name],
    };
    for (final name in ['openid', 'unionid', 'refresh_token']) {
      if ('${result[name] ?? ''}'.isEmpty && value['wx$name'] is String) {
        result[name] = value['wx$name'];
      }
    }
    return result;
  }

  static int seconds(Object? value) {
    final n = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return n > 0 && n <= 253402300799 ? n : 0;
  }

  static bool renewable(Map value) =>
      value['refresh_key'] is String &&
          (value['refresh_key'] as String).trim().isNotEmpty ||
      value['refresh_token'] is String &&
          (value['refresh_token'] as String).trim().isNotEmpty;

  static Map<String, dynamic> issued(Map value, DateTime now, {Map? previous}) {
    final result = previous == null ? <String, dynamic>{} : read(previous);
    // A new music key cannot inherit the previous key's lifetime.
    for (final name in [
      'musickeyCreateTime',
      'keyExpiresIn',
      'needRefreshKeyIn'
    ]) {
      result.remove(name);
    }
    result.addAll(read(value));
    result['receivedAt'] = now.millisecondsSinceEpoch ~/ 1000;
    return result;
  }

  static DateTime renewalAt(Map value, DateTime loadedAt) {
    final received = seconds(value['receivedAt']);
    final created = seconds(value['musickeyCreateTime']);
    final lifetime = seconds(value['keyExpiresIn']);
    final refreshIn = seconds(value['needRefreshKeyIn']);
    final base = created > 0 ? created : received;
    final candidates = <int>[];
    if (base > 0 && refreshIn > 0) candidates.add(base + refreshIn);
    if (created > 0 && lifetime > 0) {
      // Daily-use apps need a useful window before expiry, rather than having
      // to be open during the final few minutes of a multi-day web session.
      final lead = lifetime >= 86400
          ? (lifetime ~/ 3).clamp(300, 86400)
          : (lifetime ~/ 10).clamp(1, 300);
      candidates.add(created + lifetime - lead);
    }
    // Unknown lifetime: attempt a bounded compatibility refresh, not an assumed TTL.
    if (candidates.isEmpty) {
      candidates.add(
          (received > 0 ? received : loadedAt.millisecondsSinceEpoch ~/ 1000) +
              1800);
    }
    candidates.sort();
    return DateTime.fromMillisecondsSinceEpoch(candidates.first * 1000);
  }
}
