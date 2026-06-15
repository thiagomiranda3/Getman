import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:getman/core/utils/workspace/workspace_bookmark.dart';

/// Prompts for a workspace directory. Desktop/mobile only — returns null on web
/// (no filesystem) and on cancel/error.
///
/// On macOS the native picker also mints a security-scoped bookmark (so writes
/// survive relaunch under the App Sandbox); other platforms have no sandbox
/// bookmark requirement and use `file_picker` with a null bookmark.
Future<WorkspaceLocation?> pickWorkspaceDirectory() async {
  if (kIsWeb) return null;
  if (WorkspaceBookmarks.supported) {
    return WorkspaceBookmarks.pickDirectory();
  }
  try {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose workspace folder',
    );
    return path == null ? null : WorkspaceLocation(path);
  } on Object catch (e) {
    debugPrint('Workspace picker failed: $e');
    return null;
  }
}
