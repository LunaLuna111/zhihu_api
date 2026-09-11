/// Pure Dart models and wire-format parsers used by the API client.
///
/// This entrypoint deliberately contains no transport, session, Flutter, or
/// update-service code. Applications that only need to normalize API payloads
/// can depend on this smaller surface.
library;

export 'src/comment_emoticons.dart';
export 'src/json_tools.dart';
