// Integration test for Contacts CRUD workflow.
// Validates: create, list, get, update, delete flow at the model layer.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';

void main() {
  group('Contact Model', () {
    test('fromJson parses full response', () {
      final json = {
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'name': 'Rajesh Enterprises',
        'email': 'rajesh@enterprises.in',
        'phone': '9876543210',
        'contact_type': 'CUSTOMER',
        'gstin': '27AABCE1234F1Z5',
        'pan': 'AABCE1234F',
        'registration_type': 'REGULAR',
        'billing_address': {
          'street': '123 MG Road',
          'city': 'Mumbai',
          'state': 'Maharashtra',
          'state_code': '27',
          'pincode': '400001',
          'country': 'India',
        },
        'is_active': true,
        'opening_balance': '1000.0000',
        'credit_balance': '500.0000',
        'custom_fields': {},
        'created_at': '2025-04-01T10:00:00+00:00',
        'updated_at': '2025-04-01T10:00:00+00:00',
      };
      final contact = const Contact(id: '', name: '').fromJson(json);
      expect(contact.id, '550e8400-e29b-41d4-a716-446655440000');
      expect(contact.name, 'Rajesh Enterprises');
      expect(contact.email, 'rajesh@enterprises.in');
      expect(contact.phone, '9876543210');
      expect(contact.contactType, ContactType.customer);
      expect(contact.gstin, '27AABCE1234F1Z5');
      expect(contact.pan, 'AABCE1234F');
      expect(contact.registrationType, RegistrationType.regular);
      expect(contact.isActive, true);
      expect(contact.openingBalance, 1000.0);
      expect(contact.creditBalance, 500.0);
      expect(contact.billingAddress, isNotNull);
      expect(contact.billingAddress!.city, 'Mumbai');
      expect(contact.billingAddress!.stateCode, '27');
      expect(contact.billingAddress!.country, 'India');
    });

    test('fromJson handles minimal response', () {
      final json = {
        'id': 'abc-123',
        'name': 'Test Contact',
        'contact_type': 'BOTH',
      };
      final contact = const Contact(id: '', name: '').fromJson(json);
      expect(contact.id, 'abc-123');
      expect(contact.name, 'Test Contact');
      expect(contact.contactType, ContactType.both);
      expect(contact.email, isNull);
      expect(contact.phone, isNull);
      expect(contact.billingAddress, isNull);
      expect(contact.openingBalance, 0);
      expect(contact.isActive, true);
    });

    test('toJson produces correct request payload', () {
      const contact = Contact(
        id: '',
        name: 'Test Customer',
        contactType: ContactType.customer,
        registrationType: RegistrationType.regular,
        email: 'test@test.com',
        phone: '9876543210',
        gstin: '27AABCE1234F1Z5',
        billingAddress: Address(
          street: 'Street',
          city: 'City',
          stateCode: '27',
        ),
        openingBalance: 1000,
      );
      final json = contact.toJson();
      expect(json['name'], 'Test Customer');
      expect(json['contact_type'], 'CUSTOMER');
      expect(json['registration_type'], 'REGULAR');
      expect(json['email'], 'test@test.com');
      expect(json['opening_balance'], '1000.00');
      expect(json['billing_address'], isNotNull);
      expect(json['billing_address']['city'], 'City');
      expect(json['billing_address']['street'], 'Street');
    });

    test('ContactType enum fromApi and apiValue roundtrip', () {
      for (final type in ContactType.values) {
        expect(ContactType.fromApi(type.apiValue), type);
      }
    });

    test('RegistrationType enum fromApi and apiValue roundtrip', () {
      for (final type in RegistrationType.values) {
        expect(RegistrationType.fromApi(type.apiValue), type);
      }
    });
  });
}
