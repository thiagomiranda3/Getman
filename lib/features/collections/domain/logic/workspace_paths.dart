// Pure predicate for "is this repo path part of the mirrored workspace?" —
// the file set the Review dialog can diff/stage/commit (*.req.json,
// */.folder.json, .getman/workspace.json). Shared by GitBranchService
// (isDirty) and WorkspaceReviewService so the two can never disagree about
// what counts as an uncommitted workspace change.

/// True when [path] (repo-relative, as reported by `git status`) is one of
/// the files the workspace mirror owns. Everything else (.DS_Store, a
/// README, editor droppings) is invisible to Getman's git flows: Review
/// ignores it, so dirtiness checks must too — otherwise a branch switch is
/// refused for "uncommitted changes" that REVIEW CHANGES then reports as
/// empty, a dead end the user cannot commit their way out of.
bool isWorkspacePath(String path) =>
    path == '.getman/workspace.json' ||
    path == '.folder.json' ||
    path.endsWith('/.folder.json') ||
    path.endsWith('.req.json');
