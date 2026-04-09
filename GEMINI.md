# Getman: Project Documentation & Mandates

This file serves as the foundational context for Getman, a Postman-like HTTP client built with Flutter.

## Core Architecture
- **State Management**: [Riverpod](https://riverpod.dev/) (`StateNotifier`).
- **Persistence**: [Hive](https://pub.dev/packages/hive) (Local NoSQL database).
- **Networking**: [Dio](https://pub.dev/packages/dio).
- **Code Editing**: [re_editor](https://pub.dev/packages/re_editor) with `re_highlight`.

## Project Structure
- `lib/models/`: Hive-annotated data models.
- `lib/providers/`: State management logic (Tabs, Collections, History, Settings).
- `lib/services/`: `StorageService` for Hive persistence.
- `lib/widgets/`: Modular UI components.
- `lib/main.dart`: Entry point, persistence initialization, and top-level layout.

## Key Implementation Details
### 1. Highlighted & Selectable Response View
To ensure the response is both syntax-highlighted and natively selectable on desktop, we use `CodeEditor` from `re_editor` in `readOnly: true` mode. This allows for native selection, syntax highlighting via `re_highlight`, and built-in line numbers.
```dart
CodeEditor(
  controller: _responseController!,
  readOnly: true,
  wordWrap: true,
  style: CodeEditorStyle(
    codeTheme: CodeHighlightTheme(
      languages: { 'json': CodeHighlightThemeMode(mode: langJson) },
      theme: arduinoLightTheme,
    ),
  ),
  indicatorBuilder: (context, controller, chunkController, notifier) {
    return DefaultCodeLineNumber(
      controller: controller,
      notifier: notifier,
    );
  },
)
```

### 2. Drag-and-Drop Collections
Implemented in `lib/widgets/side_menu.dart` using `Draggable<String>` and `DragTarget<String>`. 
- Logic is handled by `CollectionsNotifier.moveNode`.
- Uses the `onAcceptWithDetails` API (modern Flutter).

### 3. Persistence Workflow
Whenever state is modified in a Provider, the corresponding `StorageService.save...` method **must** be called to ensure changes survive app restarts.

## Maintenance Commands
- **Build Adapters**: `dart run build_runner build --delete-conflicting-outputs`
- **Quality Check**: `flutter analyze && flutter test`

## Native Configuration
- **macOS Outgoing Connections**: Enabled via `com.apple.security.network.client` in `.entitlements` files.
- **Git**: `.gitignore` is configured to exclude build artifacts, `.hive` files, and `.dart_tool`.

## Future Roadmap Ideas
- Environment Variable support.
- JSON schema validation.
- Export/Import collections (Postman format).
