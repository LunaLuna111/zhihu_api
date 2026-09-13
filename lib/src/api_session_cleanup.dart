import 'api_session.dart';

/// A server-side signal that a persistent account session may no longer be
/// valid. It is deliberately separate from [ApiSession.clear]: callers can
/// show their own confirmation UI before deleting durable credentials.
class ApiSessionCleanupRequest {
  ApiSessionCleanupRequest({
    required this.reason,
    required this.source,
    required this.credentialRevision,
    this.statusCode,
    this.businessCode,
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now().toUtc();

  final String reason;
  final String source;
  final int credentialRevision;
  final int? statusCode;
  final String? businessCode;
  final DateTime detectedAt;
}

/// Optional account-cleanup boundary implemented by applications with a UI.
///
/// The API package never depends on a widget toolkit. When this capability is
/// present, the request pipeline reports a suspected logout and leaves the
/// session untouched until the host explicitly confirms or dismisses it.
abstract interface class ApiSessionCleanupDelegate {
  Future<bool> requestAccountSessionCleanup(ApiSessionCleanupRequest request);
}
