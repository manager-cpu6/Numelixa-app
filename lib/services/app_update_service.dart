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
    releaseNotes: (j['releaseNotes'] ?? '').toString(),
    mandatory: j['isMandatory'] == true || j['mandatory'] == true || j['force'] == true,
    allowSkip: j['allowSkip'] != false && j['force'] != true,
    apkSizeBytes: int.tryParse((j['apkSizeBytes'] ?? j['sizeBytes'] ?? '').toString()),
    sha256: j['sha256']?.toString(),
  );
}

class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;

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
        releaseNotes: (release['body'] ?? 'A new version of Numelixa is available.').toString(),
        mandatory: false,
        allowSkip: true,
        apkSizeBytes: int.tryParse((apk['size'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> downloadAndOpen(AppUpdateInfo update, void Function(int received, int total) onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('\${dir.path}/numelixa-update-\${update.versionCode}.apk');
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
