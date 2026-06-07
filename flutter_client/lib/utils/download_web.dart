import 'dart:html' as html;

/// Triggers a browser file download on Flutter Web.
void triggerWebDownload(String fileName, List<int> bytes) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrl(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
