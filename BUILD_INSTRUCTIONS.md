# Build Instructions

## Prerequisites

Install Flutter SDK from https://docs.flutter.dev/get-started/install

## Android Build

```bash
cd flutter_client

# Clean and get dependencies
flutter clean
flutter pub get

# Build APK for testing
flutter build apk --release

# Build App Bundle for Play Store
flutter build appbundle --release

# Output locations:
# APK: build/app/outputs/flutter-apk/app-release.apk
# AAB: build/app/outputs/bundle/release/app-release.aab
```

## Web Build

```bash
cd flutter_client

# Clean and get dependencies
flutter clean
flutter pub get

# Build for web
flutter build web --release

# Output location:
# build/web/
```

## Desktop Builds (Optional)

### Windows
```bash
flutter build windows --release
# Output: build/windows/runner/Release/
```

### Linux
```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

## Verification

After building, verify the Flutter client works:

1. **Android**: Install APK on device/emulator and test login, password change
2. **Web**: Serve `build/web/` with a static server and verify in browser
3. **Desktop**: Run the executable and verify basic functionality

## CI/CD Integration

For automated builds, add these steps to your CI pipeline:

```yaml
# Example GitHub Actions
- name: Set up Flutter
  uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.x'
    
- name: Build Android
  run: |
    cd flutter_client
    flutter clean
    flutter pub get
    flutter build apk --release
    
- name: Build Web
  run: |
    cd flutter_client
    flutter clean
    flutter pub get
    flutter build web --release
```

## Recent Fixes Applied

The following issues have been fixed in commit `d7e2cd1`:

- ✅ Flutter compile error: `report_list_view.dart` duplicate class import
- ✅ Password validator: Now requires 8+ chars with complexity (matches backend)
- ✅ Backend SMTP: Shared helper with EHLO/STARTTLS/timeout
- ✅ Backend Celery: Retry with exponential backoff for email tasks
- ✅ Backend: Fixed silent exception in forgot_password

These fixes should be verified in the built applications before production deployment.