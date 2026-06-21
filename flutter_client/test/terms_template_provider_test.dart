import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client/providers/terms_template_provider.dart';
import 'mock_api_client/mock_api_client.dart';

void main() {
  test('fetchTemplates loads reusable terms templates without network dependency', () async {
    final client = MockApiClient(
      responder: (request) {
        if (request.url.path.endsWith('/terms-templates')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'terms-1',
                'tenant_id': 'tenant-1',
                'name': 'Standard Invoice Terms',
                'content': 'Payment due within 15 days.',
                'is_preset': false,
                'is_active': true,
              }
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      },
    );
    final provider = TermsTemplateProvider(client: client);

    final templates = await provider.fetchTemplates();

    expect(templates, hasLength(1));
    expect(templates.first.name, 'Standard Invoice Terms');
    expect(templates.first.content, 'Payment due within 15 days.');
  });
}
