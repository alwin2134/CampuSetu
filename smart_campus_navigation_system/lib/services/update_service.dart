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

        // Get local version and build number
        final packageInfo = await PackageInfo.fromPlatform();
        final localVersionStr = packageInfo.version;
        final localBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

        // Parse remote version and build number (e.g., "v1.2.3+15" or "1.2.3")
        String remoteVersionStr = tagName;
        int remoteBuildNumber = 0;
        
        if (remoteVersionStr.contains('+')) {
          final parts = remoteVersionStr.split('+');
          remoteVersionStr = parts[0];
          remoteBuildNumber = int.tryParse(parts[1]) ?? 0;
        }
        
        if (remoteVersionStr.startsWith('v') || remoteVersionStr.startsWith('V')) {
          remoteVersionStr = remoteVersionStr.substring(1);
        }

        bool hasUpdate = false;

        // Compare semantic version parts (Major.Minor.Patch)
        final localParts = localVersionStr.split('.').map((s) => int.tryParse(s) ?? 0).toList();
        final remoteParts = remoteVersionStr.split('.').map((s) => int.tryParse(s) ?? 0).toList();

        // Pad arrays to same length (minimum 3)
        while (localParts.length < 3) {
          localParts.add(0);
        }
        while (remoteParts.length < 3) {
          remoteParts.add(0);
        }

        for (int i = 0; i < 3; i++) {
          if (remoteParts[i] > localParts[i]) {
            hasUpdate = true;
            break;
          } else if (remoteParts[i] < localParts[i]) {
            break;
          }
        }

        // If version strings are exactly equal, fall back to comparing build number
        if (!hasUpdate && remoteParts[0] == localParts[0] && remoteParts[1] == localParts[1] && remoteParts[2] == localParts[2]) {
           if (remoteBuildNumber > localBuildNumber) {
             hasUpdate = true;
           }
        }

        if (hasUpdate) {
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
