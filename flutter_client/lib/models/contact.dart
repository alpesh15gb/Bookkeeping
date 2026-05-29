class ContactModel {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String contactType; // CUSTOMER, VENDOR, BOTH
  final String? gstin;
  final String? pan;
  final String registrationType;
  final Map<String, dynamic> billingAddress;
  final Map<String, dynamic>? shippingAddress;
  final String stateCode;
  final bool isActive;

  ContactModel({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    required this.contactType,
    this.gstin,
    this.pan,
    required this.registrationType,
    required this.billingAddress,
    this.shippingAddress,
    required this.stateCode,
    required this.isActive,
  });

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      contactType: json['contact_type'] ?? 'CUSTOMER',
      gstin: json['gstin'],
      pan: json['pan'],
      registrationType: json['registration_type'] ?? 'CONSUMER',
      billingAddress: json['billing_address'] is Map ? Map<String, dynamic>.from(json['billing_address']) : {},
      shippingAddress: json['shipping_address'] is Map ? Map<String, dynamic>.from(json['shipping_address']) : null,
      stateCode: json['state_code'] ?? '27',
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'contact_type': contactType,
      'gstin': gstin,
      'pan': pan,
      'registration_type': registrationType,
      'billing_address': billingAddress,
      'shipping_address': shippingAddress,
      'state_code': stateCode,
    };
  }
}
