import 'dart:convert';

class EndpointContract {
  const EndpointContract({
    required this.role,
    required this.method,
    required this.path,
    required this.origin,
  });

  final String role;
  final String method;
  final String path;
  final String origin;
}

/// Pure-Dart API contract parser. Flutter applications can load their asset
/// and pass the string to [fromJsonString]; the package never uses rootBundle.
class ApiContract {
  ApiContract._(this.endpoints);

  final Map<String, EndpointContract> endpoints;

  factory ApiContract.fromJson(Object? source) {
    if (source is! List) {
      throw const FormatException('API contract root is not a list');
    }
    final values = <String, EndpointContract>{};
    for (final value in source) {
      if (value is! Map) continue;
      final map = value.map((key, item) => MapEntry(key.toString(), item));
      final role = map['flutter_role']?.toString() ?? '';
      if (role.isEmpty || values.containsKey(role)) {
        throw FormatException('invalid or duplicate Flutter role: $role');
      }
      values[role] = EndpointContract(
        role: role,
        method: map['http_method']?.toString() ?? '',
        path: map['path']?.toString() ?? '',
        origin: map['contract_origin']?.toString() ?? '',
      );
    }
    return ApiContract._(Map.unmodifiable(values));
  }

  factory ApiContract.fromJsonString(String source) =>
      ApiContract.fromJson(jsonDecode(source));

  EndpointContract operator [](String role) {
    final endpoint = endpoints[role];
    if (endpoint == null) throw StateError('contract role not found: $role');
    return endpoint;
  }
}
