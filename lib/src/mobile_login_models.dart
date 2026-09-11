import 'api_response.dart';

class MobileDigitsResult {
  const MobileDigitsResult({
    required this.response,
    required this.sent,
    required this.requiresCaptcha,
    required this.message,
    this.captchaImageBase64,
  });

  final ApiResponse response;
  final bool sent;
  final bool requiresCaptcha;
  final String message;
  final String? captchaImageBase64;
}

class MobileSignInResult {
  const MobileSignInResult({
    required this.response,
    required this.signedIn,
    required this.requiresVerification,
    required this.message,
    this.errorCode,
    this.errorName,
  });

  final ApiResponse response;
  final bool signedIn;
  final bool requiresVerification;
  final String message;
  final String? errorCode;
  final String? errorName;
}
