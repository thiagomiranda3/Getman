# Getman: Project Documentation & Mandates

Getman is a high-performance, aesthetically pleasing HTTP client built with Flutter, featuring a Neo-Brutalist design. It allows users to manage multiple requests through a tabbed interface, organize them into collections, and track request history.

## 1. Core Architecture & Stack
- **Architecture**: Feature-First combined with Clean Architecture principles (`domain`, `data`, `presentation` layers).
- **State Management**: [BLoC / flutter_bloc](https://bloclibrary.dev/) (Strict separation of UI and business logic).
- **Persistence**: [Hive](https://pub.dev/packages/hive) (Local NoSQL database).
- **Networking**: [Dio](https://pub.dev/packages/dio).
- **Code Editing**: [re_editor](https://pub.dev/packages/re_editor) with `re_highlight`.
- **UI Patterns**: Atomic Design principles. Neo-Brutalist design with custom `LayoutExtension` for theme-driven spacing/sizing.

## 2. Project Structure (Feature-First)
The application is strictly divided into domains. Never place files by their "type" globally unless they are truly core utilities.
- `lib/core/`: Shared infrastructure, themes, generic UI widgets, and global network/storage clients.
- `lib/features/`: Isolated functionality modules (e.g., `tabs`, `collections`, `history`, `settings`).
  - `[feature]/domain/`: Entities and Repository Interfaces.
  - `[feature]/data/`: Hive Models (DTOs), Data Sources, and Repository Implementations.
  - `[feature]/presentation/`: BLoCs, Events, States, Screens, and local Widgets.

## 3. Key Features & Implementation Details

### A. Highlighted & Searchable Response View
The response view uses `CodeEditor` from `re_editor` in `readOnly: true` mode. This provides:
- Native text selection and line numbers.
- Syntax highlighting via `re_highlight`.
- Built-in find functionality with a custom UI (`_CodeFindPanel`).

### B. Drag-and-Drop Collections
Implemented in the side menu using `Draggable<String>` and `DragTarget<String>`.
- State updates are handled via BLoC events (e.g., `MoveNodeEvent`).
- Visual feedback for drop targets is provided by `_isDragOver` state.

### C. Persistence Workflow
Persistence is handled via `StorageService`.
- The BLoC managing tabs uses a debounced save mechanism (e.g., via `rxdart` or bloc event transformers with 10-second debounce) to avoid excessive disk I/O during rapid editing.
- Collections and History BLoCs save immediately upon state change.

### D. Dirty State Tracking
A specific selector or state property efficiently determines if a tab has unsaved changes by comparing its current `HttpRequestConfig` with the persisted version. Used to show a dirty indicator (`*`) and prompt for confirmation before closing.

## 4. Development Mandates (Gemini Instructions)

### Architectural Rules
- **Domain First**: When creating a new feature, ALWAYS generate the `domain` layer (interfaces and entities) before writing implementation or UI.
- **Dependency Inversion**: BLoCs must only depend on abstract repository interfaces, never concrete Hive/Dio implementations. This ensures 100% testability.
- **Imutability**: All BLoC States and Events must use `equatable` (or `freezed`) to ensure predictable state transitions.

### UI & Styling Rules
- **Theme Adherence**: Respect the Neo-Brutalist design system. Use `LayoutExtension` for sizing and the `BrutalBounce` wrapper for interactive elements. Do not hardcode colors.
- **Atomic Design**: Keep widgets small. If a UI component is reusable across features, place it in `lib/core/ui/widgets/`.

### Workflow Rules
- **Always Build & Verify**: No changes should be considered done until they compile. I (Gemini) must ensure syntax correctness.
- **Surgical Updates**: When modifying Hive models in the `data` layer, remind the user to run `dart run build_runner build --delete-conflicting-outputs`.