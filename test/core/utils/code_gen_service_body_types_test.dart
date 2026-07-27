// test/core/utils/code_gen_service_body_types_test.dart
//
// Per-language body-type coverage for CodeGenService: multipart/binary/
// urlencoded emitters in every target, the GraphQL envelope's lenient
// variables parsing, and the empty-raw-body "no data" branches.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/utils/code_gen_service.dart';

void main() {
  const multipart = HttpRequestConfigEntity(
    id: 'm',
    method: 'POST',
    url: 'https://api.dev/upload',
    bodyType: BodyType.multipart,
    formFields: [
      MultipartFieldEntity(name: 'field', value: 'v'),
      MultipartFieldEntity(name: 'pic', isFile: true, filePath: '/tmp/pic.png'),
      MultipartFieldEntity(name: '', value: 'zzz-skipped'),
    ],
  );

  const binary = HttpRequestConfigEntity(
    id: 'b',
    method: 'POST',
    url: 'https://api.dev/upload',
    bodyType: BodyType.binary,
    bodyFilePath: '/tmp/data.bin',
  );

  const urlencoded = HttpRequestConfigEntity(
    id: 'u',
    method: 'POST',
    url: 'https://api.dev/form',
    bodyType: BodyType.urlencoded,
    formFields: [
      MultipartFieldEntity(name: 'a', value: '1'),
      MultipartFieldEntity(name: 'upload', isFile: true, filePath: '/f'),
    ],
  );

  group('graphql envelope variables parsing (lenient)', () {
    test('invalid variables JSON degrades to an empty object', () {
      const config = HttpRequestConfigEntity(
        id: 'g',
        method: 'POST',
        url: 'https://api.dev/graphql',
        bodyType: BodyType.graphql,
        body: 'query { me }',
        graphqlVariables: '{oops',
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains('"variables":{}'));
      expect(out, contains('query { me }'));
    });

    test('blank variables text becomes an empty object', () {
      const config = HttpRequestConfigEntity(
        id: 'g',
        method: 'POST',
        url: 'https://api.dev/graphql',
        bodyType: BodyType.graphql,
        body: 'query { me }',
        graphqlVariables: '   ',
      );
      final out = CodeGenService.generate(config, CodeGenTarget.curl);
      expect(out, contains('"variables":{}'));
    });

    test('JS fetch wraps the envelope as the body', () {
      const config = HttpRequestConfigEntity(
        id: 'g',
        method: 'POST',
        url: 'https://api.dev/graphql',
        bodyType: BodyType.graphql,
        body: 'query { me }',
        graphqlVariables: '{"x":1}',
      );
      final out = CodeGenService.generate(config, CodeGenTarget.jsFetch);
      expect(out, contains('body:'));
      expect(out, contains('"query"'));
      expect(out, contains('"x":1'));
    });
  });

  group('JavaScript fetch body types', () {
    test('urlencoded uses URLSearchParams and skips file rows', () {
      final out = CodeGenService.generate(urlencoded, CodeGenTarget.jsFetch);
      expect(out, contains("body: new URLSearchParams({ 'a': '1' })"));
      expect(out, isNot(contains('upload')));
    });

    test('multipart appends text fields, comments file rows, skips '
        'nameless rows', () {
      final out = CodeGenService.generate(multipart, CodeGenTarget.jsFetch);
      expect(out, contains('const form = new FormData();'));
      expect(out, contains("form.append('field', 'v');"));
      expect(
        out,
        contains("// form.append('pic', /* File for /tmp/pic.png */);"),
      );
      expect(out, contains('body: form,'));
      expect(out, isNot(contains('zzz-skipped')));
    });

    test('binary emits an attach-the-file comment and no body option', () {
      final out = CodeGenService.generate(binary, CodeGenTarget.jsFetch);
      expect(
        out,
        contains('// Attach the file at /tmp/data.bin as the request body.'),
      );
      expect(out, isNot(contains('body:')));
    });
  });

  group('Node.js axios body types', () {
    test('urlencoded uses URLSearchParams and skips file rows', () {
      final out = CodeGenService.generate(urlencoded, CodeGenTarget.nodeAxios);
      expect(out, contains("data: new URLSearchParams({ 'a': '1' })"));
      expect(out, isNot(contains('upload')));
    });

    test('multipart appends text fields and comments file streams', () {
      final out = CodeGenService.generate(multipart, CodeGenTarget.nodeAxios);
      expect(out, contains("const FormData = require('form-data');"));
      expect(out, contains("form.append('field', 'v');"));
      expect(
        out,
        contains(
          "// form.append('pic', fs.createReadStream('/tmp/pic.png'));",
        ),
      );
      expect(out, contains('data: form,'));
      expect(out, contains('...form.getHeaders()'));
      expect(out, isNot(contains('zzz-skipped')));
    });

    test('binary emits a read-the-file comment and no data option', () {
      final out = CodeGenService.generate(binary, CodeGenTarget.nodeAxios);
      expect(out, contains('// Read the file at /tmp/data.bin'));
      expect(out, contains('fs.readFileSync'));
      expect(out, isNot(contains('data: form')));
    });
  });

  group('Python requests body types', () {
    test('multipart builds a files dict: open(rb) for files, (None, value) '
        'for text fields', () {
      final out = CodeGenService.generate(
        multipart,
        CodeGenTarget.pythonRequests,
      );
      expect(out, contains("'pic': open('/tmp/pic.png', 'rb'),"));
      expect(out, contains("'field': (None, 'v'),"));
      expect(out, contains('files=files'));
      expect(out, isNot(contains('zzz-skipped')));
    });
  });

  group('Go net/http body types', () {
    test('multipart emits a builder comment and a nil request body', () {
      final out = CodeGenService.generate(multipart, CodeGenTarget.goNetHttp);
      expect(
        out,
        contains(
          '// Build a multipart/form-data body with mime/multipart.Writer '
          '(omitted).',
        ),
      );
      expect(out, contains('http.NewRequest(method, url, nil)'));
    });

    test('binary emits an open-the-file comment and a nil request body', () {
      final out = CodeGenService.generate(binary, CodeGenTarget.goNetHttp);
      expect(
        out,
        contains(
          '// Open the file at /tmp/data.bin and pass it as the request body.',
        ),
      );
      expect(out, contains('http.NewRequest(method, url, nil)'));
    });
  });

  group('Java OkHttp body types', () {
    test('multipart builds a MultipartBody with text parts and commented '
        'file parts', () {
      final out = CodeGenService.generate(multipart, CodeGenTarget.javaOkHttp);
      expect(
        out,
        contains('new MultipartBody.Builder().setType(MultipartBody.FORM)'),
      );
      expect(out, contains('.addFormDataPart("field", "v")'));
      expect(out, contains('// .addFormDataPart("pic", "/tmp/pic.png"'));
      expect(out, contains('.method("POST", body)'));
      expect(out, isNot(contains('zzz-skipped')));
    });

    test(
      'binary comments the file read and passes a null-initialized body',
      () {
        final out = CodeGenService.generate(binary, CodeGenTarget.javaOkHttp);
        expect(
          out,
          contains(
            '// Read the file at /tmp/data.bin into a '
            'RequestBody',
          ),
        );
        expect(out, contains('RequestBody body = null;'));
        expect(out, contains('.method("POST", body)'));
      },
    );

    test('urlencoded FormBody skips file rows', () {
      final out = CodeGenService.generate(urlencoded, CodeGenTarget.javaOkHttp);
      expect(out, contains('.add("a", "1")'));
      expect(out, isNot(contains('.add("upload"')));
    });
  });

  group('empty raw body emits no data in any target', () {
    const emptyRaw = HttpRequestConfigEntity(id: 'e', url: 'https://api.dev/x');

    test('cURL', () {
      final out = CodeGenService.generate(emptyRaw, CodeGenTarget.curl);
      expect(out, isNot(contains('--data')));
    });

    test('JS fetch', () {
      final out = CodeGenService.generate(emptyRaw, CodeGenTarget.jsFetch);
      expect(out, isNot(contains('body:')));
    });

    test('Node axios', () {
      final out = CodeGenService.generate(emptyRaw, CodeGenTarget.nodeAxios);
      expect(out, isNot(contains('data:')));
    });

    test('Python requests', () {
      final out = CodeGenService.generate(
        emptyRaw,
        CodeGenTarget.pythonRequests,
      );
      expect(out, isNot(contains('data =')));
      expect(out, contains("requests.request('GET', url, headers=headers)"));
    });

    test('Java OkHttp', () {
      final out = CodeGenService.generate(emptyRaw, CodeGenTarget.javaOkHttp);
      expect(out, contains('.method("GET", null)'));
    });
  });

  test('the GraphQL envelope is valid JSON end to end', () {
    const config = HttpRequestConfigEntity(
      id: 'g',
      method: 'POST',
      url: 'https://api.dev/graphql',
      bodyType: BodyType.graphql,
      body: 'query { me }',
      graphqlVariables: '{"x": 1}',
    );
    final out = CodeGenService.generate(config, CodeGenTarget.curl);
    final dataMatch = RegExp(r"--data '(.+)'$", dotAll: true).firstMatch(out);
    expect(dataMatch, isNotNull);
    final decoded = jsonDecode(dataMatch!.group(1)!) as Map<String, dynamic>;
    expect(decoded['query'], 'query { me }');
    expect(decoded['variables'], {'x': 1});
  });
}
