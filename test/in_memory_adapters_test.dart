import 'package:test/test.dart';
import 'package:zhihu_api/zhihu_api_core.dart';

ApiResponse _response(Uri uri) => ApiResponse(
  uri: uri,
  statusCode: 200,
  bodyBytes: 2,
  json: const {'data': <Object>[]},
  headers: const {'content-type': 'application/json'},
);

void main() {
  test('normalizes mobile cookie maps without dropping named cookies', () {
    expect(
      ZhihuApiClient.cookieHeaderFromValue({
        'z_c0': 'account-cookie',
        'd_c0': 'device-cookie',
        '_xsrf': 'csrf-token',
      }),
      'z_c0=account-cookie; d_c0=device-cookie; _xsrf=csrf-token',
    );
  });

  test('in-memory session stores and clears a guest context', () async {
    final session = InMemoryApiSession();

    expect(session.hasCompleteMobileContext, isFalse);
    await session.saveGuestSession(
      accessToken: 'guest-token',
      udid: 'device-id',
      zCookie: 'guest-cookie',
    );

    expect(session.hasGuestSession, isTrue);
    expect(session.authorization, 'Bearer guest-token');
    expect(session.cookie, 'z_c0=guest-cookie');
    expect(
      session.requestHeaders(
        method: 'GET',
        uri: Uri.parse('https://api.zhihu.com/'),
      ),
      {
        'Authorization': 'Bearer guest-token',
        'x-udid': 'device-id',
        'Cookie': 'z_c0=guest-cookie',
      },
    );

    final revision = session.credentialRevision;
    await session.clearGuestSession();
    expect(session.hasCompleteMobileContext, isFalse);
    expect(session.credentialRevision, greaterThan(revision));
  });

  test(
    'in-memory session protects account commits by credential revision',
    () async {
      final session = InMemoryApiSession();

      final saved = await session.saveAccountSession(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        udid: 'device-id',
        expiresIn: const Duration(hours: 1),
        zCookie: 'account-cookie',
        uid: '42',
      );
      expect(saved, isTrue);
      expect(session.hasAccountSession, isTrue);
      expect(session.hasRefreshableAccountSession, isTrue);
      expect(session.accountUid, '42');
      expect(session.cookie, 'z_c0=account-cookie');

      final staleCommit = await session.saveAccountSession(
        accessToken: 'new-access-token',
        refreshToken: 'new-refresh-token',
        udid: 'device-id',
        expiresIn: const Duration(hours: 1),
        expectedCredentialRevision: 0,
      );
      expect(staleCommit, isFalse);
      expect(session.authorization, 'Bearer access-token');
    },
  );

  test('keeps and refreshes the complete mobile cookie context', () async {
    final session = InMemoryApiSession();
    await session.saveAccountSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      udid: 'device-id',
      expiresIn: const Duration(hours: 1),
      zCookie: 'z_c0=account-cookie; d_c0=device-cookie; _xsrf=csrf-token',
    );

    expect(
      session.cookie,
      'z_c0=account-cookie; d_c0=device-cookie; _xsrf=csrf-token',
    );
    await session.updateCookie('d_c0=rotated-cookie; Path=/; HttpOnly');
    expect(
      session.cookie,
      'z_c0=account-cookie; d_c0=rotated-cookie; _xsrf=csrf-token',
    );
  });

  test(
    'in-memory response cache is bounded and refreshes insertion order',
    () async {
      final cache = InMemoryApiResponseCache(maxEntries: 2);
      final first = Uri.parse('https://api.zhihu.com/one');
      final second = Uri.parse('https://api.zhihu.com/two');
      final third = Uri.parse('https://api.zhihu.com/three');

      await cache.write('one', _response(first));
      await cache.write('two', _response(second));
      expect(await cache.read('one'), isNotNull);
      await cache.write('one', _response(first));
      await cache.write('three', _response(third));

      expect(await cache.read('two'), isNull);
      expect((await cache.read('one'))?.uri, first);
      expect((await cache.read('three'))?.uri, third);
    },
  );
}
