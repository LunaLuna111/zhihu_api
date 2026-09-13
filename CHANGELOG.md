# Changelog

## 0.2.6

- Added comment image upload alias and `comment_img` payload support.

## 0.2.5

- Added the native `vertical_info` tuple to content-type search filters.

## 0.2.4

- Added search filter configuration models, parsing, and fetch route.

## 0.2.3

- Search completion parsing now removes case-insensitive duplicate queries.

## 0.2.2

- Added anonymous hot-search routes and tolerant parsing for
  `GET /api/v4/search/hot_search`.
- Added case-insensitive duplicate filtering for search hot items.

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
