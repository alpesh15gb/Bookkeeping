/// Stub for non-web platforms. Throws if called.
void triggerWebDownload(String fileName, List<int> bytes) {
  throw UnsupportedError('Web download is only supported on web platforms');
}
