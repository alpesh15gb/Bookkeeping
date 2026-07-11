/// Request payloads for the authentication APIs.
///
/// Kept as plain immutable classes with a [toJson] so the repository layer can
/// stay agnostic of the wire format. Validators live next to the form widgets.
library;

import 'package:flutter/foundation.dart';

@immutable
class RegisterRequest {
  const RegisterRequest({
    required this.email,
    required this.password,
    required this.fullName,
    required this.phoneNumber,
    required this.companyLegalName,
    this.companyGstin,
    this.companyPan,
  });

  final String email;
  final String password;
  final String fullName;
  final String phoneNumber;
  final String companyLegalName;
  final String? companyGstin;
  final String? companyPan;

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    'full_name': fullName,
    'phone_number': phoneNumber,
    'company_legal_name': companyLegalName,
    if (companyGstin != null && companyGstin!.isNotEmpty)
      'company_gstin': companyGstin,
    if (companyPan != null && companyPan!.isNotEmpty) 'company_pan': companyPan,
  };
}

@immutable
class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

@immutable
class RefreshRequest {
  const RefreshRequest(this.refreshToken);
  final String refreshToken;

  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};
}

@immutable
class ForgotPasswordRequest {
  const ForgotPasswordRequest(this.email);
  final String email;

  Map<String, dynamic> toJson() => {'email': email};
}

@immutable
class ResetPasswordRequest {
  const ResetPasswordRequest({required this.token, required this.newPassword});

  final String token;
  final String newPassword;

  Map<String, dynamic> toJson() => {
    'token': token,
    'new_password': newPassword,
  };
}

@immutable
class ChangePasswordRequest {
  const ChangePasswordRequest({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;
  final String newPassword;

  Map<String, dynamic> toJson() => {
    'current_password': currentPassword,
    'new_password': newPassword,
  };
}

@immutable
class TotpVerifyRequest {
  const TotpVerifyRequest(this.token);
  final String token;

  Map<String, dynamic> toJson() => {'token': token};
}
