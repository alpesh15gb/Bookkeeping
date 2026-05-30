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
