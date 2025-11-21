import 'package:shared_preferences/shared_preferences.dart';
import 'backup_service.dart';

/// Cloud sync service for backing up and restoring library data
/// Currently provides manual sync trigger - can be extended with OAuth for Google Drive
class CloudSyncService {
  final _backupService = BackupService();
  static const _lastSyncKey = 'last_cloud_sync_v1';
  static const _autoSyncKey = 'auto_cloud_sync_enabled_v1';

  /// Check if auto-sync is enabled
  Future<bool> isAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSyncKey) ?? false;
  }

  /// Enable or disable auto-sync
  Future<void> setAutoSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncKey, enabled);
  }

  /// Get the last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastSyncKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Update the last sync timestamp
  Future<void> _updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Get backup data as JSON (ready for upload to cloud)
  Future<String> getBackupForCloud() async {
    return await _backupService.getBackupJson();
  }

  /// Restore from cloud backup JSON
  Future<BackupImportResult> restoreFromCloud(String jsonData) async {
    final result = await _backupService.restoreFromJson(jsonData);
    if (result.success) {
      await _updateLastSyncTime();
    }
    return result;
  }

  /// Manual sync - returns backup JSON that can be uploaded manually
  /// In a full implementation, this would handle OAuth and upload to Google Drive
  Future<CloudSyncResult> manualBackup() async {
    try {
      final json = await getBackupForCloud();
      await _updateLastSyncTime();
      
      return CloudSyncResult(
        success: true,
        message: 'Backup prepared. Copy JSON to your cloud storage.',
        backupData: json,
      );
    } catch (e) {
      return CloudSyncResult(
        success: false,
        message: 'Backup failed: $e',
      );
    }
  }

  /// Manual restore - accepts JSON that was downloaded from cloud
  Future<CloudSyncResult> manualRestore(String jsonData) async {
    try {
      final result = await restoreFromCloud(jsonData);
      return CloudSyncResult(
        success: result.success,
        message: result.message,
      );
    } catch (e) {
      return CloudSyncResult(
        success: false,
        message: 'Restore failed: $e',
      );
    }
  }

  // Future Google Drive integration methods (requires OAuth setup):
  //
  // Future<CloudSyncResult> syncToGoogleDrive() async {
  //   // 1. Authenticate with Google Drive OAuth
  //   // 2. Get backup JSON
  //   // 3. Upload to Google Drive (overwrite existing or create new)
  //   // 4. Update last sync time
  // }
  //
  // Future<CloudSyncResult> restoreFromGoogleDrive() async {
  //   // 1. Authenticate with Google Drive OAuth
  //   // 2. Download backup JSON from Google Drive
  //   // 3. Restore from JSON
  //   // 4. Update last sync time
  // }
}

class CloudSyncResult {
  final bool success;
  final String message;
  final String? backupData; // For manual copy-paste workflows

  CloudSyncResult({
    required this.success,
    required this.message,
    this.backupData,
  });
}
