# Getman: Project Documentation & Mandates

Getman is a high-performance, aesthetically pleasing HTTP client built with Flutter, featuring a Neo-Brutalist design. It allows users to manage multiple requests through a tabbed interface, organize them into collections, and track request history.

## Core Architecture
- **State Management**: [Riverpod](https://riverpod.dev/) (`StateNotifier`, `Provider.family`).
- **Persistence**: [Hive](https://pub.dev/packages/hive) (Local NoSQL database).
- **Networking**: [Dio](https://pub.dev/packages/dio).
- **Code Editing**: [re_editor](https://pub.dev/packages/re_editor) with `re_highlight`.
- **UI Patterns**: Neo-Brutalist design with custom `LayoutExtension` for theme-driven spacing and sizing.

## Key Features
- **Tabbed Interface**: Manage multiple concurrent requests. Supports reordering, duplicating, and contextual close options (Close Others, Close to the Right).
- **Request Configuration**:
  - HTTP Methods: GET, POST, PUT, DELETE, PATCH.
  - Interactive Key-Value editors for Params and Headers.
  - JSON Body editor with syntax highlighting and find/replace support.
- **Response Analysis**:
  - Syntax-highlighted and searchable response body (using `re_editor` in read-only mode).
  - Response metadata (Status code, Duration).
  - Response headers view.
  - Automatic JSON prettification.
- **Collections Management**:
  - Hierarchical structure (folders and requests).
  - Drag-and-drop organization.
  - Favorites (starring folders).
  - Searchable collections tree.
- **Request History**:
  - Automatic logging of all sent requests.
  - Configurable history limit.
  - Searchable history list.
  - Option to persist response data in history.
- **User Settings**:
  - Dark/Light mode toggle.
  - Compact/Normal UI density modes.
  - Vertical/Horizontal split layout for Request/Response view.
  - Persistence of side menu width and split ratios.

## Project Structure
- `lib/models/`: Hive-annotated data models (`HttpRequestConfig`, `HttpRequestTabModel`, `CollectionNode`, `SettingsModel`).
- `lib/providers/`: State management logic.
  - `tabs_provider.dart`: Manages open tabs and request execution.
  - `collections_provider.dart`: Handles hierarchical request organization.
  - `history_provider.dart`: Manages the request log.
  - `settings_provider.dart`: Application configuration state.
- `lib/services/`: `StorageService` for centralized Hive persistence.
- `lib/utils/`:
  - `neo_brutalist_theme.dart`: Implementation of the custom design system.
  - `json_utils.dart`: Helpers for JSON formatting.
- `lib/widgets/`:
  - `request_view.dart`: The main workspace for configuring and viewing requests.
  - `side_menu.dart`: Sidebar containing Collections, History, and global actions.
  - `splitter.dart`: Custom draggable divider for resizing UI sections.
- `lib/main.dart`: App entry point, persistence initialization, and top-level layout.

## Key Implementation Details

### 1. Highlighted & Searchable Response View
The response view uses `CodeEditor` from `re_editor` in `readOnly: true` mode. This provides:
- Native text selection.
- Syntax highlighting via `re_highlight`.
- Built-in find functionality with a custom UI (`_CodeFindPanel`).
- Line numbers.

### 2. Drag-and-Drop Collections
Implemented in `lib/widgets/side_menu.dart` using `Draggable<String>` and `DragTarget<String>`. 
- State updates are handled by `CollectionsNotifier.moveNode`.
- Visual feedback for drop targets is provided by `_isDragOver` state.

### 3. Persistence Workflow
Persistence is handled via `StorageService`. `TabsNotifier` uses a debounced save mechanism (10 seconds) to avoid excessive disk I/O during rapid editing, while `CollectionsNotifier` and `HistoryNotifier` save immediately on change.

### 4. Dirty State Tracking
`isTabDirtyProvider` (a `Provider.family`) efficiently determines if a tab has unsaved changes by comparing its current `HttpRequestConfig` with the version stored in the collection node. This is used to show a dirty indicator (`*`) and prompt for confirmation before closing.

## Maintenance Commands
- **Build Adapters**: `dart run build_runner build --delete-conflicting-outputs`
- **Quality Check**: `flutter analyze && flutter test`

## Native Configuration
- **macOS Outgoing Connections**: Enabled via `com.apple.security.network.client` in `.entitlements` files.
- **Git**: `.gitignore` is configured to exclude build artifacts, `.hive` files, and `.dart_tool`.

## Development Mandates
- **Always Build & Verify**: You MUST always build the project (using `flutter analyze` or full build) and make sure it AT LEAST runs before you call something done. No changes should be left unverified.
- **Surgical Updates**: When modifying models, always run `build_runner` to update the generated Hive adapters.
- **Theme Adherence**: Respect the Neo-Brutalist design system by using `LayoutExtension` for sizing and the `BrutalBounce` wrapper for interactive elements.
