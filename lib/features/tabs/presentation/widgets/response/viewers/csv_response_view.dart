// PREVIEW viewer for CSV responses. Caches a background chunked parse per byte
// buffer, showing a loading first frame and discarding stale async results.
// Header + 500 body rows are retained, with an exact total-row count.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/csv_preview.dart';

/// Renders a CSV response as a scrollable table (first row = header).
class CsvResponseView extends StatefulWidget {
  const CsvResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  @override
  State<CsvResponseView> createState() => _CsvResponseViewState();
}

class _CsvResponseViewState extends State<CsvResponseView> {
  late Future<CsvPreview> _preview;

  @override
  void initState() {
    super.initState();
    _preview = loadCsvPreview(widget.bytes);
  }

  @override
  void didUpdateWidget(CsvResponseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _preview = loadCsvPreview(widget.bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CsvPreview>(
      future: _preview,
      builder: (context, snapshot) {
        // FutureBuilder can keep old data while waiting for a new future.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: Text('Loading CSV…'));
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to preview CSV'));
        }
        return _table(context, snapshot.requireData);
      },
    );
  }

  Widget _table(BuildContext context, CsvPreview preview) {
    final layout = context.appLayout;
    final rows = preview.rows;
    if (rows.isEmpty) {
      return const Center(child: Text('Empty CSV'));
    }
    final header = rows.first;
    final body = rows.skip(1);
    final truncated = preview.totalBodyRows > kCsvPreviewRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (truncated)
          Padding(
            padding: EdgeInsets.all(layout.tabSpacing),
            child: Text(
              'Showing first $kCsvPreviewRows of ${preview.totalBodyRows} rows',
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final h in header) DataColumn(label: Text(h)),
                ],
                rows: [
                  for (final r in body)
                    DataRow(
                      cells: [
                        for (var i = 0; i < header.length; i++)
                          DataCell(Text(i < r.length ? r[i] : '')),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
