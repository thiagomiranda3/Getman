// Picks the native or stub workspace data source at compile time so dart:io
// never reaches the web build.
export 'workspace_collections_data_source_stub.dart'
    if (dart.library.io) 'workspace_collections_data_source_io.dart'
    show createWorkspaceDataSource;
