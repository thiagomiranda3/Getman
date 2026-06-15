import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A picked workspace folder: its path plus, on macOS, the security-scoped
/// bookmark (base64) that re-authorizes access on a later launch.
class WorkspaceLocation {
  const WorkspaceLocation(this.path, {this.bookmark});
  final String path;
  final String? bookmark;
}

/// The outcome of re-acquiring access from a persisted bookmark on launch.
class WorkspaceAccessResult {
  const WorkspaceAccessResult({
    required this.path,
    required this.bookmark,
    required this.stale,
  });
  final String path;

  /// The bookmark to persist going forward — refreshed when the OS reported the
  /// stored one as stale, otherwise the original.
  final String bookmark;

  /// True when macOS reported the bookmark as stale (resolved fine, but should
  /// be recreated and re-persisted).
  final bool stale;
}

/// Thin wrapper over the macOS `getman/workspace_bookmark` method channel.
///
/// Under the macOS App Sandbox the folder grant from an open-panel does not
/// survive relaunch, so we persist a security-scoped bookmark and re-acquire
/// access from it on each launch. Only meaningful on macOS; every method is a
/// safe no-op (returns null) on other platforms and in tests, so callers can
/// invoke them unconditionally.
class WorkspaceBookmarks {
  static const MethodChannel _channel = MethodChannel(
    'getman/workspace_bookmark',
  );

  /// macOS-only — the sole platform with a sandbox bookmark requirement and a
  /// native handler. `defaultTargetPlatform` is web-safe (no `dart:io`).
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Shows the native directory open-panel and returns the chosen folder plus a
  /// freshly-minted security-scoped bookmark. Returns null on cancel or error.
  static Future<WorkspaceLocation?> pickDirectory() async {
    if (!supported) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'pickDirectory',
      );
      if (res == null) return null;
      final path = res['path'] as String?;
      if (path == null) return null;
      return WorkspaceLocation(path, bookmark: res['bookmark'] as String?);
    } on Object catch (e) {
      debugPrint('Workspace picker (native) failed: $e');
      return null;
    }
  }

  /// Resolves [bookmark] and starts security-scoped access for the process
  /// lifetime. Returns the resolved path and a (possibly refreshed) bookmark,
  /// or null if access could not be re-acquired (folder moved/deleted, or the
  /// grant was revoked) — the caller should then treat the workspace as needing
  /// a reconnect.
  static Future<WorkspaceAccessResult?> resolveAndAccess(
    String bookmark,
  ) async {
    if (!supported) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'resolveBookmark',
        {'bookmark': bookmark},
      );
      if (res == null) return null;
      final path = res['path'] as String?;
      if (path == null) return null;
      return WorkspaceAccessResult(
        path: path,
        bookmark: res['bookmark'] as String? ?? bookmark,
        stale: res['stale'] as bool? ?? false,
      );
    } on Object catch (e) {
      debugPrint('Workspace bookmark resolve failed: $e');
      return null;
    }
  }
}
