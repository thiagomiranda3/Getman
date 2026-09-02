import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/utils/body_type_utils.dart';

void main() {
  group('BodyTypeUtils.applyContentType', () {
    test('urlencoded forces the form content-type', () {
      final h = <String, String>{};
      BodyTypeUtils.applyContentType(h, BodyType.urlencoded);
      expect(h['Content-Type'], 'application/x-www-form-urlencoded');
    });
    test('multipart strips content-type (Dio adds the boundary)', () {
      final h = <String, String>{'content-type': 'text/plain'};
      BodyTypeUtils.applyContentType(h, BodyType.multipart);
      expect(h.keys.any((k) => k.toLowerCase() == 'content-type'), isFalse);
    });
    test('binary sets octet-stream only when no custom type is present', () {
      final h = <String, String>{};
      BodyTypeUtils.applyContentType(h, BodyType.binary);
      expect(h['Content-Type'], 'application/octet-stream');
    });
    test('binary respects an existing custom content-type', () {
      final h = <String, String>{'Content-Type': 'image/png'};
      BodyTypeUtils.applyContentType(h, BodyType.binary);
      expect(h['Content-Type'], 'image/png');
    });
    test('none leaves headers untouched; raw keeps an existing value', () {
      final none = <String, String>{};
      final raw = <String, String>{'Content-Type': 'application/json'};
      BodyTypeUtils.applyContentType(none, BodyType.none);
      BodyTypeUtils.applyContentType(raw, BodyType.raw);
      expect(none, isEmpty);
      expect(raw['Content-Type'], 'application/json');
    });
  });

  group('BodyTypeUtils.defaultContentType', () {
    test('maps every body type to the Content-Type the wire carries', () {
      expect(BodyTypeUtils.defaultContentType(BodyType.none), isNull);
      expect(
        BodyTypeUtils.defaultContentType(BodyType.raw),
        'application/json',
      );
      expect(
        BodyTypeUtils.defaultContentType(BodyType.urlencoded),
        'application/x-www-form-urlencoded',
      );
      expect(
        BodyTypeUtils.defaultContentType(BodyType.multipart),
        'multipart/form-data',
      );
      expect(
        BodyTypeUtils.defaultContentType(BodyType.binary),
        'application/octet-stream',
      );
      expect(
        BodyTypeUtils.defaultContentType(BodyType.graphql),
        'application/json',
      );
    });
  });

  group('BodyTypeUtils.isAutoContentType', () {
    test('recognizes every auto default regardless of case/params', () {
      expect(BodyTypeUtils.isAutoContentType('application/json'), isTrue);
      expect(
        BodyTypeUtils.isAutoContentType(' Application/JSON; charset=utf-8 '),
        isTrue,
      );
      expect(
        BodyTypeUtils.isAutoContentType('application/x-www-form-urlencoded'),
        isTrue,
      );
      expect(
        BodyTypeUtils.isAutoContentType('multipart/form-data; boundary=x'),
        isTrue,
      );
      expect(
        BodyTypeUtils.isAutoContentType('application/octet-stream'),
        isTrue,
      );
    });
    test('a user-chosen type is not auto', () {
      expect(BodyTypeUtils.isAutoContentType('text/xml'), isFalse);
      expect(BodyTypeUtils.isAutoContentType('image/png'), isFalse);
      expect(BodyTypeUtils.isAutoContentType(''), isFalse);
    });
  });

  group('BodyTypeUtils.syncContentType (body-type switch)', () {
    test('inserts the default as the FIRST row when absent', () {
      final out = BodyTypeUtils.syncContentType(
        {'Accept': '*/*'},
        BodyType.urlencoded,
      );
      expect(out.keys.toList(), ['Content-Type', 'Accept']);
      expect(out['Content-Type'], 'application/x-www-form-urlencoded');
    });
    test(
      'replaces an auto value in place, keeping key spelling + position',
      () {
        final out = BodyTypeUtils.syncContentType(
          {'Accept': '*/*', 'content-type': 'application/json'},
          BodyType.binary,
        );
        expect(out.keys.toList(), ['Accept', 'content-type']);
        expect(out['content-type'], 'application/octet-stream');
      },
    );
    test('leaves a user-chosen (non-auto) value untouched', () {
      final input = {'Content-Type': 'text/xml', 'Accept': '*/*'};
      final out = BodyTypeUtils.syncContentType(input, BodyType.multipart);
      expect(out, input);
      expect(out.keys.toList(), input.keys.toList());
    });
    test('none drops an auto Content-Type row', () {
      final out = BodyTypeUtils.syncContentType(
        {'Content-Type': 'application/json', 'Accept': '*/*'},
        BodyType.none,
      );
      expect(out, {'Accept': '*/*'});
    });
    test('none keeps a user-chosen Content-Type row', () {
      final out = BodyTypeUtils.syncContentType(
        {'Content-Type': 'text/xml'},
        BodyType.none,
      );
      expect(out, {'Content-Type': 'text/xml'});
    });
    test('none with no Content-Type row is a no-op', () {
      final out = BodyTypeUtils.syncContentType({'A': '1'}, BodyType.none);
      expect(out, {'A': '1'});
    });
    test('returns a new map — the input is never mutated', () {
      final input = <String, String>{'Accept': '*/*'};
      BodyTypeUtils.syncContentType(input, BodyType.raw);
      expect(input, {'Accept': '*/*'});
    });
  });

  group('BodyTypeUtils.withDefaultContentType (imports)', () {
    test('adds the default first when absent', () {
      final out = BodyTypeUtils.withDefaultContentType(
        {'X': '1'},
        BodyType.multipart,
      );
      expect(out.keys.toList(), ['Content-Type', 'X']);
      expect(out['Content-Type'], 'multipart/form-data');
    });
    test('never touches an existing row, auto or not', () {
      final auto = {'content-type': 'application/json'};
      final custom = {'Content-Type': 'text/xml'};
      expect(
        BodyTypeUtils.withDefaultContentType(auto, BodyType.binary),
        auto,
      );
      expect(
        BodyTypeUtils.withDefaultContentType(custom, BodyType.binary),
        custom,
      );
    });
    test('none adds nothing', () {
      expect(
        BodyTypeUtils.withDefaultContentType({'X': '1'}, BodyType.none),
        {'X': '1'},
      );
    });
  });

  group('BodyTypeUtils.applyContentType raw (Dio implied default)', () {
    test('raw sets application/json when no Content-Type is present', () {
      final h = <String, String>{'Accept': '*/*'};
      BodyTypeUtils.applyContentType(h, BodyType.raw);
      expect(h['Content-Type'], 'application/json');
    });
    test('raw keeps any Content-Type the user set', () {
      final h = <String, String>{'content-type': 'text/xml'};
      BodyTypeUtils.applyContentType(h, BodyType.raw);
      expect(h, {'content-type': 'text/xml'});
    });
  });
}
