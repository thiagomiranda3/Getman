// Immutable ScriptLimits value exchanged by script execution components.
import 'package:equatable/equatable.dart';

class ScriptLimits extends Equatable {
  const ScriptLimits({
    this.timeout = const Duration(seconds: 1),
    this.memoryBytes = 32 * 1024 * 1024,
    this.sourceBytes = 256 * 1024,
    this.inputBytes = 8 * 1024 * 1024,
    this.outputBytes = 1024 * 1024,
    this.logEntries = 200,
    this.logBytes = 64 * 1024,
    this.testCount = 200,
  });
  final Duration timeout;
  final int memoryBytes;
  final int sourceBytes;
  final int inputBytes;
  final int outputBytes;
  final int logEntries;
  final int logBytes;
  final int testCount;

  ScriptLimits copyWith({
    Duration? timeout,
    int? memoryBytes,
    int? sourceBytes,
    int? inputBytes,
    int? outputBytes,
    int? logEntries,
    int? logBytes,
    int? testCount,
  }) => ScriptLimits(
    timeout: timeout ?? this.timeout,
    memoryBytes: memoryBytes ?? this.memoryBytes,
    sourceBytes: sourceBytes ?? this.sourceBytes,
    inputBytes: inputBytes ?? this.inputBytes,
    outputBytes: outputBytes ?? this.outputBytes,
    logEntries: logEntries ?? this.logEntries,
    logBytes: logBytes ?? this.logBytes,
    testCount: testCount ?? this.testCount,
  );
  @override
  List<Object?> get props => [
    timeout,
    memoryBytes,
    sourceBytes,
    inputBytes,
    outputBytes,
    logEntries,
    logBytes,
    testCount,
  ];
}
