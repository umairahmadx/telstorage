/*
 * File: web_share_settings_service.dart
 * Description: Service for managing public share security settings, expiration, vanity slugs, and deletion on storage.to.
 */

import 'package:hive_flutter/hive_flutter.dart';
import '../models/web_share_job.dart';
import '../utils/app_logger.dart';
import 'web_share_api_client.dart';

/// Helper service for managing remote parameters and metadata for storage.to share links.
class WebShareSettingsService {
  final WebShareApiClient _apiClient;
  final Box _box;

  WebShareSettingsService({
    required WebShareApiClient apiClient,
    required Box box,
  })  : _apiClient = apiClient,
        _box = box;

  /// Revokes and deletes a public share from storage.to and clears local Hive record.
  Future<void> deleteShare(String fileId) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId != null && job.ownerToken != null) {
      try {
        await _apiClient.deleteShareRemote(job.storageToId!, job.ownerToken!);
      } catch (e) {
        AppLogger.w('Failed deleteShare: $e', tag: 'WebShareSettingsService');
      }
    }
    await _box.delete(fileId);
  }

  /// Sets or updates password protection on storage.to share link.
  Future<void> setPassword(String fileId, String password) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final success = await _apiClient.setPasswordRemote(
        job.storageToId!, job.ownerToken!, password);
    if (success) {
      await _box.put(fileId, job.copyWith(password: password).toMap());
    } else {
      throw Exception('Failed password update');
    }
  }

  /// Sets or updates expiration duration in days on storage.to share link.
  Future<void> setExpiry(String fileId, int days) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final success = await _apiClient.setExpiryRemote(
        job.storageToId!, job.ownerToken!, days);
    if (success) {
      await _box.put(fileId, job.copyWith(expiryDays: days).toMap());
    } else {
      throw Exception('Failed expiry update');
    }
  }

  /// Sets maximum download quota limit on storage.to share link.
  Future<void> setMaxDownloads(String fileId, int? maxDownloads) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final success = await _apiClient.setMaxDownloadsRemote(
        job.storageToId!, job.ownerToken!, maxDownloads);
    if (success) {
      await _box.put(fileId, job.copyWith(maxDownloads: maxDownloads).toMap());
    } else {
      throw Exception('Failed download cap update');
    }
  }

  /// Assigns custom vanity alias slug to storage.to share link.
  Future<void> setVanitySlug(String fileId, String vanitySlug) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final formattedSlug =
        vanitySlug.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]'), '-');
    final success = await _apiClient.setVanitySlugRemote(
        job.storageToId!, job.ownerToken!, formattedSlug);
    if (success) {
      final updatedUrl = 'https://storage.to/v/$formattedSlug';
      await _box.put(
        fileId,
        job.copyWith(shareUrl: updatedUrl, vanitySlug: formattedSlug).toMap(),
      );
    } else {
      throw Exception('Failed vanity slug update');
    }
  }
}
