import 'dart:async';
import 'package:http/http.dart' as http;

typedef MockResponder = FutureOr<http.Response> Function(http.BaseRequest request);

class MockApiClient extends http.BaseClient {
  final MockResponder responder;
  final List<http.BaseRequest> requests = [];

  MockApiClient({MockResponder? responder})
      : responder = responder ??
            ((request) => http.Response(
                  '{}',
                  200,
                  headers: {'content-type': 'application/json'},
                ));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = await responder(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      contentLength: response.bodyBytes.length,
      request: request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
