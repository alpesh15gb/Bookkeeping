class UserResponse {
  final String id;
  final String email;
  final String fullName;
  final String? phoneNumber;
  final bool isActive;

  UserResponse({
    required this.id,
    required this.email,
    required this.fullName,
    this.phoneNumber,
    required this.isActive,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    return UserResponse(
      id: json['id'],
      email: json['email'],
      fullName: json['full_name'] ?? json['fullName'] ?? '',
      phoneNumber: json['phone_number'] ?? json['phoneNumber'],
      isActive: json['is_active'] ?? json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'is_active': isActive,
    };
  }
}

class TenantMembership {
  final String id;
  final String tenantId;
  final String role;
  final bool isActive;
  final String? tenantName;

  TenantMembership({
    required this.id,
    required this.tenantId,
    required this.role,
    required this.isActive,
    this.tenantName,
  });

  factory TenantMembership.fromJson(Map<String, dynamic> json) {
    return TenantMembership(
      id: json['id'],
      tenantId: json['tenant_id'] ?? json['tenantId'],
      role: json['role'] ?? 'member',
      isActive: json['is_active'] ?? json['isActive'] ?? true,
      tenantName: json['tenant_name'] ?? json['tenantName'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'role': role,
      'is_active': isActive,
      'tenant_name': tenantName,
    };
  }
}
