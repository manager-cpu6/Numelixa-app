import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  const AppUpdateInfo({required this.version, required this.versionCode, required this.apkUrl, required this.releaseNotes, required this.mandatory, required this.allowSkip, this.apkSizeBytes, this.sha256});
  final String version;
  final int versionCode;
  final String apkUrl;
  final String releaseNotes;
  final bool mandatory;
  final bool allowSkip;
  final int? apkSizeBytes;
  final String? sha256;
  factory AppUpdateInfo.fromJson(Map<String,dynamic> j) => AppUpdateInfo(
    version: (j['versionName'] ?? j['version'] ?? '').toString(),
    versionCode: int.tryParse((j['versionCode'] ?? 0).toString()) ?? 0,
    apkUrl: (j['apkUrl'] ?? j['downloadUrl'] ?? '').toString(),
    releaseNotes: _cleanReleaseNotes(j['releaseNotes']),
    mandatory: j['isMandatory'] == true || j['mandatory'] == true || j['force'] == true,
    allowSkip: j['allowSkip'] != false && j['force'] != true,
    apkSizeBytes: int.tryParse((j['apkSizeBytes'] ?? j['sizeBytes'] ?? '').toString()),
    sha256: j['sha256']?.toString(),
  );
}

String _cleanReleaseNotes(dynamic raw) {
  var text = (raw ?? '').toString()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  // Release notes may be copied from GitHub markdown, including duplicated
  // compare links, repeated "Full Changelog" blocks, and wrapped URLs.
  text = text.replaceAll(RegExp(r'\*\*Full Changelog\*\*:?[^\n]*', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'Full Changelog:?[^\n]*', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'github\.com/[^\s]*', caseSensitive: false), '');
  final seen = <String>{};
  final lines = <String>[];
  for (var line in text.split('\n')) {
    line = line
        .replaceAll(RegExp(r'^\s*[-*•>]+\s*'), '')
        .replaceAll(RegExp(r'[\x60*_]{1,3}'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    if (lower.contains('full changelog') ||
        lower.contains('commits/android-latest') ||
        lower.contains('github.com/manager-cpu6') ||
        lower == 'yo' || lower == 'infc' || lower == 'una' || lower == 'hom') continue;
    if (line.length < 8) continue;
    final normalized = lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    if (normalized.isEmpty || !seen.add(normalized)) continue;
    lines.add(line);
    if (lines.length >= 4) break;
  }
  return lines.join('\n');
}

class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;

  Future<void> _ensureUpdateNotifications() async {
    if (_notificationsReady) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(const InitializationSettings(android: android));
    const channel = AndroidNotificationChannel('app_updates', 'Numelixa app updates', description: 'APK download progress and installation status', importance: Importance.low, playSound: false, enableVibration: false);
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    _notificationsReady = true;
  }

  Future<void> _showProgress(int received, int total, {String title = 'Downloading Numelixa update', bool completed = false}) async {
    try {
      await _ensureUpdateNotifications();
      final determinate = total > 0;
      final percent = determinate ? ((received / total) * 100).round().clamp(0, 100) : 0;
      await _notifications.show(7106, completed ? 'Numelixa update downloaded' : title,
        completed ? 'Tap to return to Numelixa and install the update.' : (determinate ? '$percent% · ${(received / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB' : 'Download in progress…'),
        NotificationDetails(android: AndroidNotificationDetails('app_updates', 'Numelixa app updates', channelDescription: 'APK download progress and installation status', importance: Importance.low, priority: Priority.low, onlyAlertOnce: true, showProgress: !completed && determinate, maxProgress: 100, progress: percent, ongoing: !completed, indeterminate: !determinate && !completed, autoCancel: completed)));
    } catch (_) {
      // Download/install must still work if the user disabled notifications.
    }
  }

  Future<File> _pendingFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/numelixa-update.pending');
  }

  Future<bool> resumePendingInstall() async {
    final marker = await _pendingFile();
    if (!await marker.exists()) return false;
    final path = (await marker.readAsString()).trim();
    if (path.isEmpty) { await marker.delete(); return false; }
    final file = File(path);
    if (!await file.exists() || await file.length() < 1024) { await marker.delete(); return false; }
    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type == ResultType.done) {
      await marker.delete();
      try { await _notifications.cancel(7106); } catch (_) {}
      return true;
    }
    return false;
  }

  Future<AppUpdateInfo?> check() async {
    final package = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(package.buildNumber) ?? 0;
    try {
      final response = await _dio.get<Map<String,dynamic>>(
        'https://www.numelixa.com/api/app-update',
        queryParameters: {
          'platform':'android',
          'packageId':'com.numelixa.app',
          'version':package.version,
          'versionCode':currentCode,
        },
        options: Options(responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12)),
      );
      final body = response.data;
      if (body != null &&
          (body['enabled'] == false || body['isActive'] == false || body['updateAvailable'] == false)) {
        return null;
      }
      if (body != null) {
        final data = body['update'] is Map
            ? Map<String,dynamic>.from(body['update'] as Map)
            : body;
        final update = AppUpdateInfo.fromJson(data);
        if (update.versionCode > currentCode && update.apkUrl.startsWith('https://')) return update;
      }
    } catch (_) {}

    try {
      final response = await _dio.get<Map<String,dynamic>>(
        'https://api.github.com/repos/manager-cpu6/Numelixa-app/releases/tags/android-latest',
        options: Options(responseType: ResponseType.json,
          headers: {'Accept':'application/vnd.github+json'},
          receiveTimeout: const Duration(seconds: 12)),
      );
      final release = response.data;
      if (release == null) return null;
      final name = (release['name'] ?? '').toString();
      final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(name);
      final codeMatch = RegExp(r'\+(\d+)').firstMatch(name);
      final versionCode = int.tryParse(codeMatch?.group(1) ?? '') ?? 0;
      final assets = release['assets'];
      if (versionCode <= currentCode || assets is! List) return null;
      final apk = assets.whereType<Map>().cast<Map<String,dynamic>>()
          .where((asset) => (asset['name'] ?? '').toString().endsWith('.apk'))
          .firstOrNull;
      if (apk == null) return null;
      final url = (apk['browser_download_url'] ?? '').toString();
      if (!url.startsWith('https://')) return null;
      return AppUpdateInfo(
        version: versionMatch?.group(1) ?? name,
        versionCode: versionCode,
        apkUrl: url,
        releaseNotes: _cleanReleaseNotes(release['body']).isEmpty ? 'A smoother, more reliable Numelixa experience with performance improvements and bug fixes.' : _cleanReleaseNotes(release['body']),
        mandatory: false,
        allowSkip: true,
        apkSizeBytes: int.tryParse((apk['size'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> downloadAndOpen(AppUpdateInfo update, void Function(int received, int total) onProgress) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/numelixa-update-${update.versionCode}.apk');
    await _ensureUpdateNotifications();
    await _showProgress(0, update.apkSizeBytes ?? 0);
    try {
      await _dio.download(update.apkUrl, file.path, deleteOnError: true,
        onReceiveProgress: (received, total) {
          onProgress(received, total);
          _showProgress(received, total);
        },
        options: Options(receiveTimeout: const Duration(minutes: 20),
          sendTimeout: const Duration(seconds: 30)));
      if (!await file.exists() || await file.length() < 1024) throw Exception('The downloaded APK is incomplete.');
      final expected = update.sha256?.trim().toLowerCase();
      if (expected != null && expected.isNotEmpty) {
        final actual = (await sha256.bind(file.openRead()).first).toString();
        if (actual != expected) {
          await file.delete();
          throw Exception('The downloaded file failed its SHA-256 integrity check.');
        }
      }
      final marker = await _pendingFile();
      await marker.writeAsString(file.path, flush: true);
      await _showProgress(await file.length(), await file.length(), completed: true);
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type == ResultType.done) {
        await marker.delete();
        try { await _notifications.cancel(7106); } catch (_) {}
        return;
      }
      // Keep the completed APK and pending marker. On app resume, the shell
      // retries the installer handoff instead of silently losing the update.
      throw Exception(result.message.isEmpty ? 'Android could not open the installer. Return to Numelixa and tap the update notification to retry.' : result.message);
    } catch (_) {
      await _showProgress(0, 0, title: 'Numelixa update needs attention');
      rethrow;
    }
  }
}
