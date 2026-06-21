class TermsTemplateModel {
  final String id;
  final String? tenantId;
  final String name;
  final String content;
  final bool isPreset;
  final bool isActive;

  TermsTemplateModel({
    required this.id,
    this.tenantId,
    required this.name,
    required this.content,
    this.isPreset = false,
    this.isActive = true,
  });

  factory TermsTemplateModel.fromJson(Map<String, dynamic> json) {
    return TermsTemplateModel(
      id: json['id'] ?? '',
      tenantId: json['tenant_id'],
      name: json['name'] ?? '',
      content: json['content'] ?? '',
      isPreset: json['is_preset'] ?? false,
      isActive: json['is_active'] ?? true,
    );
  }

  factory TermsTemplateModel.presetFromJson(Map<String, dynamic> json, int index) {
    return TermsTemplateModel(
      id: 'preset-$index',
      name: json['name'] ?? '',
      content: json['content'] ?? '',
      isPreset: true,
      isActive: true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'content': content,
    };
  }
}
