/// Team member model for Settings.
library;

import 'package:flutter/foundation.dart';

import '../../../auth/data/models/membership_models.dart';

/// Invitation lifecycle for a pending member.
enum InvitationStatus { pending, active, expired }

extension InvitationStatusX on InvitationStatus {
  String get wire => name;

  String get label {
    switch (this) {
      case InvitationStatus.pending:
        return 'Pending';
      case InvitationStatus.active:
        return 'Active';
      case InvitationStatus.expired:
        return 'Expired';
    }
  }

  static InvitationStatus fromWire(String? value) {
    switch (value) {
      case 'pending':
        return InvitationStatus.pending;
      case 'active':
        return InvitationStatus.active;
      case 'expired':
        return InvitationStatus.expired;
      default:
        return InvitationStatus.active;
    }
  }
}

/// A user belonging to the current company/tenant.
@immutable
class TeamMember {
  const TeamMember({
    required this.id,
    required this.email,
    this.fullName = '',
    required this.role,
    this.isActive = true,
    this.invitationStatus = InvitationStatus.active,
    this.joinedAt,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: (json['full_name'] as String?) ?? '',
      role: MemberRoleX.fromWire(json['role'] as String?),
      isActive: (json['is_active'] as bool?) ?? true,
      invitationStatus:
          InvitationStatusX.fromWire(json['invitation_status'] as String?),
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
    );
  }

  final String id;
  final String email;
  final String fullName;
  final MemberRole role;
  final bool isActive;
  final InvitationStatus invitationStatus;
  final DateTime? joinedAt;

  /// Display name — falls back to the email local part.
  String get displayName =>
      fullName.isNotEmpty ? fullName : email.split('@').first;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'role': role.wire,
    'is_active': isActive,
    'invitation_status': invitationStatus.wire,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamMember &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
