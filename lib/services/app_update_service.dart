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
    mandatory: j['isMandatory'] == true || j['mandatory'] == true,
    allowSkip: j['allowSkip'] != false,
    apkSizeBytes: int.tryParse((j['apkSizeBytes'] ?? '').toString()),
    sha256: j['sha256']?.toString(),
  );
}
class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;
  Future<AppUpdateInfo?> check() async {
    try {
      final package = await PackageInfo.fromPlatform();
      final response = await _dio.get<Map<String,dynamic>>('https://www.numelixa.com/api/app-update',
        queryParameters: {'platform':'android','packageId':'com.numelixa.app','version':package.version,'versionCode':int.tryParse(package.buildNumber) ?? 0},
        options: Options(responseType: ResponseType.json, receiveTimeout: const Duration(seconds: 12), sendTimeout: const Duration(seconds: 12)));
      final body = response.data;
      if (body == null || body['enabled'] == false || body['isActive'] == false || body['updateAvailable'] == false) return null;
      final data = body['update'] is Map ? Map<String,dynamic>.from(body['update'] as Map) : body;
      final update = AppUpdateInfo.fromJson(data);
      if (update.versionCode <= (int.tryParse(package.buildNumber) ?? 0) || update.apkUrl.isEmpty || !update.apkUrl.startsWith('https://')) return null;
      return update;
    } catch (_) { return null; }
  }
  Future<void> downloadAndOpen(AppUpdateInfo update, void Function(int received, int total) onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/numelixa-update-${update.versionCode}.apk');
    await _dio.download(update.apkUrl, file.path, deleteOnError: true, onReceiveProgress: onProgress,
      options: Options(receiveTimeout: const Duration(minutes: 5), sendTimeout: const Duration(seconds: 30)));
    if (!await file.exists() || await file.length() < 1024) throw Exception('The downloaded APK is incomplete.');
    final expected = update.sha256?.trim().toLowerCase();
    if (expected != null && expected.isNotEmpty) {
      final actual = (await sha256.bind(file.openRead()).first).toString();
      if (actual != expected) { await file.delete(); throw Exception('The downloaded file failed its SHA-256 integrity check.'); }
    }
    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) throw Exception(result.message.isEmpty ? 'Android could not open the installer.' : result.message);
  }
}