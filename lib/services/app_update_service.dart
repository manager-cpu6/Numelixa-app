import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
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

String _preferCanonicalApkUrl(String rawUrl) =>
    'https://www.numelixa.com/android';

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

  Future<AppUpdateInfo?> check() async {
    final package = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(package.buildNumber) ?? 0;
    AppUpdateInfo? best;

    // Read the website's admin-controlled update first. It carries mandatory
    // update policy, release notes and optional SHA-256 verification.
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
      if (body != null) {
        final data = body['update'] is Map
            ? Map<String,dynamic>.from(body['update'] as Map)
            : body;
        final update = AppUpdateInfo.fromJson(data);
        final canonicalUrl = _preferCanonicalApkUrl(update.apkUrl);
        if (update.versionCode > currentCode &&
            canonicalUrl.startsWith('https://')) {
          best = AppUpdateInfo(
            version: update.version,
            versionCode: update.versionCode,
            apkUrl: canonicalUrl,
            releaseNotes: update.releaseNotes,
            mandatory: update.mandatory,
            allowSkip: update.allowSkip,
            apkSizeBytes: update.apkSizeBytes,
            sha256: update.sha256,
          );
        }
      }
    } catch (_) {}

    // The website endpoint is the single source of truth for version and
    // mandatory policy. Never request GitHub release assets from the device;
    // all APK downloads must remain on the official Numelixa domain.

    return best;
  }

  Future<void> downloadAndOpen(AppUpdateInfo update, void Function(int received, int total) onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/numelixa-update-${update.versionCode}.apk');
    await _dio.download(update.apkUrl, file.path, deleteOnError: true,
      onReceiveProgress: onProgress,
      options: Options(receiveTimeout: const Duration(minutes: 5),
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
    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) throw Exception(result.message.isEmpty ? 'Android could not open the installer.' : result.message);
  }
}
