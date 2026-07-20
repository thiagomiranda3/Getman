// Renders an ApiDoc as a human-readable Markdown API reference: one section
// per operation tag, a parameters table (path/query/header), and fenced
// JSON/text example blocks for request bodies and each response.

import 'dart:convert';

import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/utils/apidoc/api_doc.dart';

/// Renders an [ApiDoc] as a human-readable Markdown API reference.
class MarkdownDocSerializer {
  MarkdownDocSerializer._();

  static const _encoder = JsonEncoder.withIndent('  ');

  static String toMarkdown(ApiDoc doc) {
    final buf = StringBuffer()
      ..writeln('# ${doc.title}')
      ..writeln();

    if (doc.servers.isNotEmpty) {
      buf.writeln('**Servers:**');
      for (final s in doc.servers) {
        buf.writeln('- `${s.url}`');
      }
      buf.writeln();
    }

    final groups = <String, List<ApiOperation>>{};
    for (final op in doc.operations) {
      groups.putIfAbsent(op.tag ?? 'General', () => []).add(op);
    }

    for (final entry in groups.entries) {
      buf
        ..writeln('## ${entry.key}')
        ..writeln();
      for (final op in entry.value) {
        _operation(op, buf);
      }
    }

    return buf.toString();
  }

  static void _operation(ApiOperation op, StringBuffer buf) {
    buf
      ..writeln('### ${op.method} ${op.path}')
      ..writeln();
    if (op.description != null) {
      buf
        ..writeln(op.description)
        ..writeln();
    }

    final params = [
      for (final p in op.pathParams) (p, 'path'),
      for (final p in op.queryParams) (p, 'query'),
      for (final p in op.headerParams) (p, 'header'),
    ];
    if (params.isNotEmpty) {
      buf
        ..writeln('**Parameters**')
        ..writeln()
        ..writeln('| Name | In | Required | Example |')
        ..writeln('| --- | --- | --- | --- |');
      for (final (p, location) in params) {
        final req = (location == 'path' || p.isRequired) ? 'yes' : 'no';
        buf.writeln('| ${p.name} | $location | $req | ${p.example ?? ''} |');
      }
      buf.writeln();
    }

    final authLine = _authLine(op.security);
    if (authLine != null) {
      buf
        ..writeln(authLine)
        ..writeln();
    }

    if (op.requestBody != null) {
      buf
        ..writeln('**Request body** (`${op.requestBody!.contentType}`)')
        ..writeln();
      _exampleBlock(op.requestBody!.example, buf);
    }

    buf
      ..writeln('**Responses**')
      ..writeln();
    for (final r in op.responses) {
      buf.writeln('- `${r.statusCode}` — ${r.description}');
      if (r.body?.example != null) {
        buf.writeln();
        _exampleBlock(r.body!.example, buf);
      }
    }
    buf.writeln();
  }

  static String? _authLine(AuthConfig auth) {
    switch (auth.type) {
      case AuthType.none:
      case AuthType.inherit:
        return null;
      case AuthType.bearer:
        return '**Auth:** Bearer';
      case AuthType.basic:
        return '**Auth:** Basic';
      case AuthType.apiKey:
        return '**Auth:** API key (`${auth.apiKeyName}`)';
    }
  }

  static void _exampleBlock(Object? example, StringBuffer buf) {
    if (example == null) return;
    final isJson = example is Map || example is List;
    final rendered = isJson ? _encoder.convert(example) : example.toString();
    buf
      ..writeln(isJson ? '```json' : '```')
      ..writeln(rendered)
      ..writeln('```')
      ..writeln();
  }
}
