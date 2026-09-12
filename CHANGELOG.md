# Changelog

## 0.2.1

- Added anonymous search completion routes and a tolerant response parser for
  `GET /api/v4/search/suggest?q=...&magi=1`.

## 0.2.0

- Added the non-persistent `InMemoryApiSession` adapter for Dart processes,
  examples, and tests.
- Added the bounded `InMemoryApiResponseCache` adapter.
- Documented the public entrypoints, dependency injection boundaries, and
  Git-based installation workflow.

## 0.1.0

- Initial reusable API client, response types, protocol routes, parsers, and
  optional login and Salt modules.
