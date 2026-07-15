import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/sales/payments/presentation/payment_form_state.dart';

void main() {
  test('editing customer text clears stale selected customer id', () {
    const selected = PaymentFormState(
      contactId: 'customer-1',
      contactName: 'Test Customer',
    );

    final edited = selected.copyWith(clearContact: true, contactName: 'Tes');

    expect(edited.contactId, isNull);
    expect(edited.contactName, 'Tes');
    expect(edited.isValid, isFalse);
  });
}
