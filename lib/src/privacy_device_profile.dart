/// Public, synthetic device presentation used by every network-facing client
/// surface. Native code owns the per-install identifiers; Dart only needs the
/// non-secret hardware/UA portion so API requests and WebViews stay coherent.
abstract final class PrivacyDeviceProfile {
  static const brand = 'Xiaomi';
  static const model = 'Xiaomi 14';
  static const androidRelease = '14';
  static const buildId = 'UKQ1.230917.001';
  static const logicalScreenWidth = 411;
  static const logicalScreenHeight = 914;
  static const availableScreenHeight = 890;
  static const devicePixelRatio = 1200 / logicalScreenWidth;
  static const timezoneOffsetSeconds = 8 * 60 * 60;
  static const timeZoneName = 'Asia/Shanghai';
  static const language = 'zh-CN';
  static const cpuCores = 8;
  static const browserDeviceMemoryGiB = 8;
  static const maxTouchPoints = 10;
  static const webGlVendor = 'Qualcomm';
  static const webGlRenderer = 'Adreno (TM) 750';

  static const appUserAgent =
      'com.zhihu.android/Futureve/11.4.0 Mozilla/5.0 (Linux; Android '
      '$androidRelease; $model Build/$buildId; wv) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Version/4.0 Chrome/57.0.1000.10 Mobile Safari/537.36';
}
