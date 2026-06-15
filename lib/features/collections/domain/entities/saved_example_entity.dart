import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';

/// A named request+response snapshot saved under a collection leaf node. The
/// [config] carries the full request *and* the captured response (statusCode /
/// responseBody / responseHeaders / durationMs already live on
/// [HttpRequestConfigEntity]), so opening an example as a tab renders the saved
/// response immediately. Examples are kept separate from a node's `children` so
/// tree-walk logic (sort/findNode/drag-drop/export) never sees them.
class SavedExampleEntity extends Equatable {
  const SavedExampleEntity({
    required this.id,
    required this.name,
    required this.capturedAt,
    required this.config,
  });
  final String id;
  final String name;
  final DateTime capturedAt;
  final HttpRequestConfigEntity config;

  SavedExampleEntity copyWith({
    String? name,
    DateTime? capturedAt,
    HttpRequestConfigEntity? config,
  }) {
    return SavedExampleEntity(
      id: id,
      name: name ?? this.name,
      capturedAt: capturedAt ?? this.capturedAt,
      config: config ?? this.config,
    );
  }

  @override
  List<Object?> get props => [id, name, capturedAt, config];
}
