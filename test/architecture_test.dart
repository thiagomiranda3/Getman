import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Architectural fitness function tests.
//
// These tests enforce the clean-architecture rules documented in CLAUDE.md by
// scanning the source tree at test time. They catch violations that would
// otherwise slip through only during human code review.
//
// Rules verified:
//  1. Domain layer (*/domain/*) must not import Hive, Dio, or Flutter UI.
//  2. Domain layer must not reach into the data layer via relative imports.
//  3. BLoC files must not import Hive, Dio, or repository implementations.
//  4. BLoC files must not reach into the data layer via relative imports.
//  5. GetIt must only be accessed from main.dart and injection_container.dart.

List<File> _dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

List<String> _importsOf(File file) => file
    .readAsLinesSync()
    .where((line) => line.trimLeft().startsWith('import '))
    .toList();

bool _isRelativeImportIntoData(String importLine) =>
    !importLine.contains("'package:") &&
    !importLine.contains("'dart:") &&
    importLine.contains('/data/');

void main() {
  group('Domain layer must not depend on infrastructure', () {
    late List<File> domainFiles;

    setUpAll(() {
      domainFiles = _dartFilesUnder('lib')
          .where((f) => f.path.contains('/domain/'))
          .toList();
    });

    test('domain files exist', () => expect(domainFiles, isNotEmpty));

    test('no Hive imports', () {
      final violations = [
        for (final file in domainFiles)
          for (final imp in _importsOf(file))
            if (imp.contains('package:hive')) '  ${file.path}\n    $imp',
      ];
      expect(
        violations,
        isEmpty,
        reason: 'Domain layer must not import Hive:\n${violations.join('\n')}',
      );
    });

    test('no Dio imports', () {
      final violations = [
        for (final file in domainFiles)
          for (final imp in _importsOf(file))
            if (imp.contains('package:dio')) '  ${file.path}\n    $imp',
      ];
      expect(
        violations,
        isEmpty,
        reason: 'Domain layer must not import Dio:\n${violations.join('\n')}',
      );
    });

    test('no Flutter UI imports (material / widgets / cupertino)', () {
      const uiPackages = [
        'package:flutter/material',
        'package:flutter/widgets',
        'package:flutter/cupertino',
        'package:flutter/rendering',
        'package:flutter/painting',
      ];
      final violations = [
        for (final file in domainFiles)
          for (final imp in _importsOf(file))
            if (uiPackages.any(imp.contains)) '  ${file.path}\n    $imp',
      ];
      expect(
        violations,
        isEmpty,
        reason:
            'Domain layer must not import Flutter UI packages:\n${violations.join('\n')}',
      );
    });

    test('no imports from the data layer', () {
      final violations = [
        for (final file in domainFiles)
          for (final imp in _importsOf(file))
            if (_isRelativeImportIntoData(imp)) '  ${file.path}\n    $imp',
      ];
      expect(
        violations,
        isEmpty,
        reason:
            'Domain layer must not import from data/:\n${violations.join('\n')}',
      );
    });
  });

  group('BLoC files must not bypass abstraction', () {
    late List<File> blocFiles;

    setUpAll(() {
      blocFiles = _dartFilesUnder('lib')
          .where(
            (f) =>
                f.path.contains('/presentation/bloc/') &&
                f.path.endsWith('_bloc.dart'),
          )
          .toList();
    });

    test('BLoC files exist', () => expect(blocFiles, isNotEmpty));

    test('no Hive imports', () {
      final violations = [
        for (final file in blocFiles)
          for (final imp in _importsOf(file))
            if (imp.contains('package:hive')) '  ${file.path}\n    $imp',
      ];
      expect(
        violations,
        isEmpty,
        reason: 'BLoCs must not import Hive:\n${violations.join('\n')}',
      );
    });

    test('no Dio imports', () {
      final violations = [
        for (final file in blocFiles)
          for (final imp in _importsOf(file))
            if (imp.contains('package:dio')) '  ${file.path}\n    $imp',
      ];
      expect(
        violations,
        isEmpty,
        reason: 'BLoCs must not import Dio:\n${violations.join('\n')}',
      );
    });

    test('no repository implementation imports (_impl.dart)', () {
      final violations = [
        for (final file in blocFiles)
          for (final imp in _importsOf(file))
            if (imp.contains('_impl.dart')) '  ${file.path}\n    $imp',
      ];
      expect(
        violations,
        isEmpty,
        reason:
            'BLoCs must depend on abstract repositories only, not _impl files:\n${violations.join('\n')}',
      );
    });

    test('no imports from the data layer', () {
      final violations = [
        for (final file in blocFiles)
          for (final imp in _importsOf(file))
            if (_isRelativeImportIntoData(imp)) '  ${file.path}\n    $imp',
      ];
      expect(
        violations,
        isEmpty,
        reason:
            'BLoCs must not import from data/:\n${violations.join('\n')}',
      );
    });
  });

  group('GetIt must only be used in DI setup files', () {
    test('no GetIt access outside main.dart and injection_container.dart', () {
      const diFiles = {'main.dart', 'injection_container.dart'};

      final violations = <String>[];
      for (final file in _dartFilesUnder('lib')) {
        if (diFiles.any((name) => file.path.endsWith(name))) continue;
        final content = file.readAsStringSync();
        if (content.contains('GetIt.instance') ||
            content.contains('sl<') ||
            content.contains('locator<')) {
          violations.add('  ${file.path}');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'GetIt must only be accessed from DI setup files:\n${violations.join('\n')}',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Canary tests — verify that each detection rule actually catches violations.
  // Each test points at a committed fixture file under
  // test/fixtures/arch_violations/ that contains an intentional violation.
  // The fixture files are NOT compiled; they exist purely as text to be scanned.
  // ---------------------------------------------------------------------------
  group('Canary: detection rules catch real violations', () {
    const fixtures = 'test/fixtures/arch_violations';

    test('detects Hive import in a domain file', () {
      final file = File('$fixtures/domain_with_hive/domain/fake_entity.dart');
      final violations = [
        for (final imp in _importsOf(file))
          if (imp.contains('package:hive')) imp,
      ];
      expect(violations, isNotEmpty);
    });

    test('detects Dio import in a domain file', () {
      final file = File('$fixtures/domain_with_dio/domain/fake_usecase.dart');
      final violations = [
        for (final imp in _importsOf(file))
          if (imp.contains('package:dio')) imp,
      ];
      expect(violations, isNotEmpty);
    });

    test('detects Flutter UI import in a domain file', () {
      final file = File('$fixtures/domain_with_flutter_ui/domain/fake_entity.dart');
      const uiPackages = [
        'package:flutter/material',
        'package:flutter/widgets',
        'package:flutter/cupertino',
        'package:flutter/rendering',
        'package:flutter/painting',
      ];
      final violations = [
        for (final imp in _importsOf(file))
          if (uiPackages.any(imp.contains)) imp,
      ];
      expect(violations, isNotEmpty);
    });

    test('detects relative import into data/ from a domain file', () {
      final file = File('$fixtures/domain_imports_data/domain/fake_usecase.dart');
      final violations = [
        for (final imp in _importsOf(file))
          if (_isRelativeImportIntoData(imp)) imp,
      ];
      expect(violations, isNotEmpty);
    });

    test('detects Hive import in a BLoC file', () {
      final file = File('$fixtures/bloc_with_hive/presentation/bloc/fake_bloc.dart');
      final violations = [
        for (final imp in _importsOf(file))
          if (imp.contains('package:hive')) imp,
      ];
      expect(violations, isNotEmpty);
    });

    test('detects Dio import in a BLoC file', () {
      final file = File('$fixtures/bloc_with_dio/presentation/bloc/fake_bloc.dart');
      final violations = [
        for (final imp in _importsOf(file))
          if (imp.contains('package:dio')) imp,
      ];
      expect(violations, isNotEmpty);
    });

    test('detects _impl.dart import in a BLoC file', () {
      final file = File('$fixtures/bloc_with_impl/presentation/bloc/fake_bloc.dart');
      final violations = [
        for (final imp in _importsOf(file))
          if (imp.contains('_impl.dart')) imp,
      ];
      expect(violations, isNotEmpty);
    });

    test('detects relative import into data/ from a BLoC file', () {
      final file = File('$fixtures/bloc_imports_data/presentation/bloc/fake_bloc.dart');
      final violations = [
        for (final imp in _importsOf(file))
          if (_isRelativeImportIntoData(imp)) imp,
      ];
      expect(violations, isNotEmpty);
    });

    test('detects GetIt usage outside DI files', () {
      final file = File('$fixtures/widget_with_getit/presentation/widgets/fake_widget.dart');
      final content = file.readAsStringSync();
      final found = content.contains('GetIt.instance') ||
          content.contains('sl<') ||
          content.contains('locator<');
      expect(found, isTrue);
    });
  });
}
