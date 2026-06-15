import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared plumbing for the Postman-compatible JSON import/export flows
/// (collections and environments). Both features pick `.json` files, map them
/// through a parser, and report success/failures through a snackbar — keep
/// that behavior in one place.

/// Filesystem-safe lowercase slug for an export filename.
String slugFilename(String name) {
  final trimmed = name.trim().toLowerCase();
  final slug = trimmed.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? 'untitled' : slug;
}

/// One-line user-facing summary of an import run, or null when there is
/// nothing to report (no files imported, no failures).
String? importSummaryMessage({
  required int importedCount,
  required List<String> failures,
  required String noun,
}) {
  if (failures.isNotEmpty) {
    return importedCount == 0
        ? 'Import failed: ${failures.join('; ')}'
        : 'Imported $importedCount $noun(s). Skipped: ${failures.join('; ')}';
  }
  if (importedCount > 0) return 'Imported $importedCount $noun(s).';
  return null;
}

/// Reads a picked file's content, preferring in-memory bytes (web) over path.
Future<String?> readPickedFile(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes != null) return utf8.decode(bytes);
  final path = file.path;
  if (path != null) return File(path).readAsString();
  return null;
}

/// Prompts for a destination and writes [jsonString] there. Shows the outcome
/// in a snackbar. No-op when the user cancels the picker.
Future<void> saveJsonFileWithFeedback(
  BuildContext context, {
  required String jsonString,
  required String fileName,
  required String dialogTitle,
  List<String> allowedExtensions = const ['json'],
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      bytes: utf8.encode(jsonString),
    );
    if (path == null) return;
    // On desktop saveFile only returns the chosen path; the write is ours.
    // On web the bytes parameter already triggered the download.
    if (!kIsWeb) {
      await File(path).writeAsString(jsonString);
    }
    messenger?.showSnackBar(SnackBar(content: Text('Exported to $path')));
  } catch (e) {
    debugPrint('Export failed: $e');
    messenger?.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}

/// Lets the user pick one or more `.json` files, runs each through [parse]
/// (which may yield several entities per file), reports per-file failures in
/// a snackbar, and hands all successfully parsed entities to [onImported].
Future<void> importJsonFilesWithFeedback<T>(
  BuildContext context, {
  required List<T> Function(String content) parse,
  required void Function(List<T> imported) onImported,
  required String noun,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
  } catch (e) {
    debugPrint('File picker failed: $e');
    messenger?.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    return;
  }
  if (result == null || result.files.isEmpty) return;

  final imported = <T>[];
  final failures = <String>[];
  for (final file in result.files) {
    try {
      final content = await readPickedFile(file);
      if (content == null) {
        failures.add('${file.name}: unable to read file');
        continue;
      }
      imported.addAll(parse(content));
    } catch (e) {
      failures.add('${file.name}: $e');
    }
  }

  if (imported.isNotEmpty) {
    onImported(imported);
  }
  final message = importSummaryMessage(
    importedCount: imported.length,
    failures: failures,
    noun: noun,
  );
  if (message != null) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}
