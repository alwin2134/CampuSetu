import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:flutter/foundation.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String? downloadUrl;
  final String? versionName;
  final String? releaseNotes;

  UpdateInfo({
    required this.hasUpdate,
    this.downloadUrl,
    this.versionName,
    this.releaseNotes,
  });
}

class UpdateService {
  static const String _repoOwner = 'alwin2134';
  static const String _repoName = 'CampuSetu';
  static const String _apiUrl = 'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  static Future<UpdateInfo> checkForUpdate() async {
    try {
      if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
        return UpdateInfo(hasUpdate: false);
      }

      final response = await http.get(Uri.parse(_apiUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String tagName = data['tag_name']; // e.g. v1.0.0+15
        final String body = data['body'] ?? '';
        
        // Find APK asset
        final List assets = data['assets'] ?? [];
        String? apkUrl;
        for (var asset in assets) {
          if (asset['name'].toString().endsWith('.apk')) {
            apkUrl = asset['browser_download_url'];
            break;
          }
        }

        if (apkUrl == null) return UpdateInfo(hasUpdate: false);

        // Parse remote build number
        final parts = tagName.split('+');
        if (parts.length != 2) return UpdateInfo(hasUpdate: false);
        final remoteBuildNumber = int.tryParse(parts[1]) ?? 0;

        // Get local build number
        final packageInfo = await PackageInfo.fromPlatform();
        final localBuildNumberStr = packageInfo.buildNumber;
        final localBuildNumber = int.tryParse(localBuildNumberStr) ?? 0;

        if (remoteBuildNumber > localBuildNumber) {
          return UpdateInfo(
            hasUpdate: true,
            downloadUrl: apkUrl,
            versionName: tagName,
            releaseNotes: body,
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
    
    return UpdateInfo(hasUpdate: false);
  }

  static Stream<OtaEvent> downloadAndInstallUpdate(String downloadUrl) {
    try {
      return OtaUpdate().execute(
        downloadUrl,
        destinationFilename: 'campusetu_update.apk',
      );
    } catch (e) {
      debugPrint('Failed to make OTA update. Details: $e');
      return Stream.error(e);
    }
  }
}
