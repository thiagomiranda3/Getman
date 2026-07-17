// PREVIEW viewer for a CSV response: decodes the bytes as UTF-8 (malformed
// bytes tolerated) and renders a scrollable DataTable, first row as the
// header. Capped at 500 body rows with a "showing first N of M" note.
import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';

/// Renders a CSV response as a scrollable table (first row = header).
class CsvResponseView extends StatelessWidget {
  const CsvResponseView({required this.bytes, super.key});
  final Uint8List bytes;

  static const _maxRows = 500;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final decoded = utf8.decode(bytes, allowMalformed: true);
    final rows = Csv(autoDetect: false).decode(decoded);
    if (rows.isEmpty) {
      return const Center(child: Text('Empty CSV'));
    }
    final header = rows.first;
    final body = rows.skip(1).take(_maxRows).toList();
    final truncated = rows.length - 1 > _maxRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (truncated)
          Padding(
            padding: EdgeInsets.all(layout.tabSpacing),
            child: Text('Showing first $_maxRows of ${rows.length - 1} rows'),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final h in header) DataColumn(label: Text('$h')),
                ],
                rows: [
                  for (final r in body)
                    DataRow(
                      cells: [
                        for (var i = 0; i < header.length; i++)
                          DataCell(Text(i < r.length ? '${r[i]}' : '')),
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
