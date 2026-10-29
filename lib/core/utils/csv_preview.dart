// CSV preview parsing runs in a compute worker. UTF-8 and CSV are decoded in
// chunks, retaining only the header and first 500 body rows while counting all
// rows. Memory beyond the input/preview is bounded by one CSV row and a chunk;
// quoted fields may span chunks, so never split or count physical newlines.
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

const kCsvPreviewRows = 500;

@immutable
class CsvPreview {
  const CsvPreview({required this.rows, required this.totalBodyRows});

  final List<List<String>> rows;
  final int totalBodyRows;
}

Future<CsvPreview> loadCsvPreview(Uint8List bytes) =>
    compute(parseCsvPreview, bytes);

/// Chunked parser, public for deterministic boundary regression tests.
CsvPreview parseCsvPreview(Uint8List bytes) {
  final collector = _PreviewSink();
  final csvSink = const CsvDecoder(
    fieldDelimiter: ',',
  ).startChunkedConversion(collector);
  final utf8Sink = const Utf8Decoder(
    allowMalformed: true,
  ).startChunkedConversion(csvSink);
  const chunkSize = 16384;
  for (var start = 0; start < bytes.length; start += chunkSize) {
    final end = (start + chunkSize).clamp(0, bytes.length);
    utf8Sink.addSlice(bytes, start, end, false);
  }
  utf8Sink.close();
  return CsvPreview(
    rows: collector.rows,
    totalBodyRows: (collector.count - 1).clamp(0, collector.count),
  );
}

class _PreviewSink implements Sink<List<dynamic>> {
  final rows = <List<String>>[];
  int count = 0;

  @override
  void add(List<dynamic> row) {
    count++;
    if (rows.length <= kCsvPreviewRows) {
      rows.add(row.cast<String>());
    }
  }

  @override
  void close() {}
}
