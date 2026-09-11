/// Errors raised before a response can be normalized into [ApiFailure].
///
/// Transport implementations should use this exception for rejected or
/// unavailable requests. Validation errors use the same type so callers have
/// one stable exception boundary independent of their platform adapter.
class ApiTransportException implements Exception {
  const ApiTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}
