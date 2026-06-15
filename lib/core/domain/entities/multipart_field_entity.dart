import 'package:equatable/equatable.dart';

/// One row of a form body (`x-www-form-urlencoded` or `multipart/form-data`).
/// Text rows use [name]/[value]; file rows set [isFile] + [filePath] (and may
/// carry a [contentType]). [name]/[value] may contain `{{env vars}}`, resolved
/// at send time.
class MultipartFieldEntity extends Equatable {
  const MultipartFieldEntity({
    required this.name,
    this.value = '',
    this.isFile = false,
    this.filePath,
    this.contentType,
  });
  final String name;
  final String value;
  final bool isFile;
  final String? filePath;
  final String? contentType;

  MultipartFieldEntity copyWith({
    String? name,
    String? value,
    bool? isFile,
    String? filePath,
    String? contentType,
  }) {
    return MultipartFieldEntity(
      name: name ?? this.name,
      value: value ?? this.value,
      isFile: isFile ?? this.isFile,
      filePath: filePath ?? this.filePath,
      contentType: contentType ?? this.contentType,
    );
  }

  @override
  List<Object?> get props => [name, value, isFile, filePath, contentType];
}
