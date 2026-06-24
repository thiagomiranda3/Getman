import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/byte_format.dart';
import 'package:getman/core/utils/json_file_io.dart';
import 'package:getman/core/utils/response_media.dart';

/// Fallback card for a binary/unviewable response (or the RAW tab of any media
/// response): content-type, size, and Save-to-file. Save is hidden when the
/// live bytes are gone.
class BinaryResponseView extends StatelessWidget {
  const BinaryResponseView({
    required this.bytes,
    required this.contentType,
    required this.url,
    required this.placeholderBody,
    super.key,
  });
  final Uint8List? bytes;
  final String? contentType;
  final String? url;
  final String placeholderBody;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final typography = context.appTypography;
    final data = bytes;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              contentType ?? 'binary',
              style: TextStyle(fontWeight: typography.titleWeight),
            ),
            SizedBox(height: layout.tabSpacing),
            if (data != null)
              Text('${formatBytes(data.length)} · ${data.length} bytes')
            else
              Text(
                placeholderBody.isEmpty
                    ? 'Not stored this session — re-send to view.'
                    : placeholderBody,
                textAlign: TextAlign.center,
              ),
            if (data != null) ...[
              SizedBox(height: layout.pagePadding),
              ElevatedButton.icon(
                key: const ValueKey('binary_save_button'),
                icon: const Icon(Icons.download),
                label: const Text('SAVE TO FILE'),
                onPressed: () {
                  final ext = mediaExtension(
                    contentType: contentType,
                    url: url,
                  );
                  unawaited(
                    saveBytesFileWithFeedback(
                      context,
                      bytes: data,
                      fileName: 'response.$ext',
                      dialogTitle: 'Save response',
                      allowedExtensions: [ext],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
