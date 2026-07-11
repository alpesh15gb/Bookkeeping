/// Core authentication models: [UserModel] and [TokenPair].
///
/// Shapes mirror the backend responses documented in
/// `AUTHENTICATION_GUIDE.md` and `REQUEST_RESPONSE_REFERENCE.md`.
library;

import 'package:flutter/foundation.dart';

/// Response from `POST /auth/register` and `GET /auth/me`.
@immutable
class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    required this.isActive,
    required this.emailVerified,
    required this.totpEnabled,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      phoneNumber: (json['phone_number'] as String?) ?? '',
      isActive: (json['is_active'] as bool?) ?? true,
      emailVerified: (json['email_verified'] as bool?) ?? false,
      totpEnabled: (json['totp_enabled'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String email;
  final String fullName;
  final String phoneNumber;
  final bool isActive;
  final bool emailVerified;
  final bool totpEnabled;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'phone_number': phoneNumber,
    'is_active': isActive,
    'email_verified': emailVerified,
    'totp_enabled': totpEnabled,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Response from `POST /auth/login` and `POST /auth/refresh`.
@immutable
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    return TokenPair(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: (json['token_type'] as String?) ?? 'bearer',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
}

/// Response from `POST /auth/2fa/enable` — an OTP-auth URI to render as a QR.
@immutable
class TotpSetup {
  const TotpSetup({required this.secret, required this.qrUri});

  factory TotpSetup.fromJson(Map<String, dynamic> json) {
    return TotpSetup(
      secret: (json['secret'] as String?) ?? '',
      qrUri:
          (json['qr_uri'] as String?) ?? (json['otpauth_uri'] as String?) ?? '',
    );
  }

  final String secret;
  final String qrUri;
}
