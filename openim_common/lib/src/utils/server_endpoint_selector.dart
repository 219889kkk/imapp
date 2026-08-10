import 'dart:async';
import 'dart:io';

import 'data_sp.dart';
import 'logger.dart';

/// Picks the fastest reachable IM entry (primary vs backup CDN).
class ServerEndpointSelector {
  ServerEndpointSelector._();

  static const primaryHost = 'im.zghtchat9.top';
  static const backupHost = 'im.hangxun19939.top';

  static const List<String> allHosts = [primaryHost, backupHost];

  static const _probeTimeout = Duration(seconds: 4);
  static const _cacheTtl = Duration(minutes: 15);

  static DateTime? _lastProbeAt;
  static String? _lastSelectedHost;

  static String get selectedHost =>
      DataSp.getServerConfig()?['serverIP']?.toString() ?? primaryHost;

  /// Probe all hosts in parallel and persist the fastest. Returns chosen host.
  static Future<String> ensureBestEndpoint({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastSelectedHost != null &&
        _lastProbeAt != null &&
        now.difference(_lastProbeAt!) < _cacheTtl) {
      return _lastSelectedHost!;
    }

    final cachedHost = DataSp.getServerConfig()?['serverIP']?.toString();
    if (!force &&
        cachedHost != null &&
        cachedHost.isNotEmpty &&
        _lastProbeAt != null &&
        now.difference(_lastProbeAt!) < _cacheTtl) {
      _lastSelectedHost = cachedHost;
      return cachedHost;
    }

    final results = await Future.wait(allHosts.map(_probeHost));
    ServerProbeResult? best;
    for (final r in results) {
      if (r == null) continue;
      if (best == null || r.latencyMs < best.latencyMs) {
        best = r;
      }
    }

    final host = best?.host ?? cachedHost ?? primaryHost;
    await applyHost(host);
    _lastSelectedHost = host;
    _lastProbeAt = now;

    if (best != null) {
      Logger.print(
        'ServerEndpointSelector: using $host (${best.latencyMs}ms) '
        'candidates=${results.whereType<ServerProbeResult>().map((e) => "${e.host}:${e.latencyMs}ms").join(", ")}',
      );
    } else {
      Logger.print(
        'ServerEndpointSelector: probe failed, fallback $host',
      );
    }
    return host;
  }

  /// Switch to the other host when the current one fails. Returns true if switched.
  static Future<bool> failoverFrom(String currentHost) async {
    final next = alternateHost(currentHost);
    if (next == null) return false;
    final probe = await _probeHost(next);
    if (probe == null) return false;
    await applyHost(next);
    _lastSelectedHost = next;
    _lastProbeAt = DateTime.now();
    Logger.print(
      'ServerEndpointSelector: failover $currentHost -> $next (${probe.latencyMs}ms)',
    );
    return true;
  }

  static String? alternateHost(String currentHost) {
    final normalized = currentHost.trim().toLowerCase();
    for (final h in allHosts) {
      if (h.toLowerCase() != normalized) return h;
    }
    return null;
  }

  static Future<void> applyHost(String host) async {
    await DataSp.putServerConfig(buildServerConfig(host));
  }

  /// IM host `im.zghtchat9.top` → base `zghtchat9.top` for LiveKit cert/DNS.
  static String liveKitDomainForHost(String imHost) {
    final h = imHost.trim().toLowerCase();
    if (h.startsWith('im.')) return h.substring(3);
    return h;
  }

  /// LiveKit/WebRTC media is only deployed on the primary CDN domain today.
  /// Backup IM line (`im.hangxun19939.top`) has no `livekit.*` DNS — using it
  /// for RTC breaks voice/video with a generic "network error" on dial.
  static String get canonicalLiveKitWsUrl =>
      'wss://livekit.${liveKitDomainForHost(primaryHost)}';

  static String liveKitWsUrlForHost(String imHost) => canonicalLiveKitWsUrl;

  /// Fix cached configs that used wrong LiveKit hosts.
  static String normalizeLiveKitWsUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    try {
      final uri = Uri.parse(trimmed);
      var host = uri.host.toLowerCase();
      if (host.startsWith('livekit.im.')) {
        host = 'livekit.${host.substring('livekit.im.'.length)}';
        return uri.replace(host: host).toString();
      }
      // Backup CDN has IM/API but no LiveKit — always use primary media edge.
      if (host == 'livekit.hangxun19939.top' ||
          host.contains('127.0.0.1') ||
          host == 'localhost') {
        return canonicalLiveKitWsUrl;
      }
    } catch (_) {}
    return trimmed;
  }

  static Map<String, String> buildServerConfig(String host) {
    final h = host.trim();
    return {
      'serverIP': h,
      'apiUrl': 'https://$h/api',
      'wsUrl': 'wss://$h/msg_gateway',
      'authUrl': 'https://$h/chat',
      'chatTokenUrl': 'https://$h/chat',
      'botApiUrl': 'https://$h/bot',
      'liveKitUrl': canonicalLiveKitWsUrl,
    };
  }

  static Future<ServerProbeResult?> _probeHost(String host) async {
    final uri = Uri.parse('https://$host/api/');
    final sw = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = _probeTimeout
        ..idleTimeout = _probeTimeout;
      final request = await client.headUrl(uri).timeout(_probeTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'HangXunEndpointProbe/1.0');
      final response = await request.close().timeout(_probeTimeout);
      await response.drain();
      sw.stop();
      // 2xx–4xx means reachable (404 on /api/ root is expected).
      if (response.statusCode > 0 && response.statusCode < 500) {
        return ServerProbeResult(host: host, latencyMs: sw.elapsedMilliseconds);
      }
    } catch (e, s) {
      Logger.print('ServerEndpointSelector probe $host failed: $e $s');
    } finally {
      client?.close(force: true);
    }
    return null;
  }
}

class ServerProbeResult {
  final String host;
  final int latencyMs;

  const ServerProbeResult({required this.host, required this.latencyMs});
}
