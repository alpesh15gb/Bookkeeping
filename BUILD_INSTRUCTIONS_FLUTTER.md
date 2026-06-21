# Flutter Build Instructions

## P1 Complete - Build Commands

Commit: `5c0f4e0` - "feat: P1 workflow optimization complete"
Branch: `master`
Git Status: ✅ Pushed to origin

---

## Prerequisites

Ensure Flutter SDK is installed and configured:

```bash
# Verify Flutter installation
flutter doctor

# Ensure Flutter is in PATH
# Windows: C:\src\flutter\bin
# macOS: /Users/[username]/flutter/bin
# Linux: /home/[username]/flutter/bin

# Check for connected devices
flutter devices
```

---

## Build Flutter Web (Release)

### Option 1: Standard Web Build

```bash
cd flutter_client
flutter build web --release
```

**Output:** `flutter_client/build/web/`

**Deploy to hosting:**
- Copy `build/web/` contents to web server
- Or deploy to Firebase Hosting, Vercel, Netlify, AWS S3

### Option 2: Web with Base href

If deploying to subdirectory (e.g., `example.com/apexbooks/`):

```bash
flutter build web --release --base-href /apexbooks/
```

### Option 3: Web with CanvasKit (better rendering)

```bash
flutter build web --release --web-renderer canvaskit
```

---

## Build Flutter Android (APK)

### Option 1: Universal APK

```bash
cd flutter_client
flutter build apk --release
```

**Output:** `flutter_client/build/app/outputs/flutter-apk/app-release.apk`

### Option 2: Split APKs (per ABI - smaller download)

```bash
flutter build appbundle --release
```

**Output:** `flutter_client/build/app/outputs/bundle/release/app-release.aab`

Upload `.aab` to Google Play Console.

### Option 3: Build for specific ABI

```bash
# ARM64 only (most modern phones)
flutter build apk --release --target-platform android-arm64

# ARM32 only (older phones)
flutter build apk --release --target-platform android-arm
```

---

## Build iOS (if needed)

```bash
cd flutter_client
flutter build ios --release
```

**Output:** `build/ios/iphoneos/Runner.app`

Archive via Xcode for App Store submission.

---

## Test Builds Locally

### Web

```bash
cd flutter_client
flutter run -d chrome --release
```

### Android Emulator

```bash
flutter emulators --launch <emulator_id>
flutter run --release
```

### Android Physical Device

```bash
# Enable USB debugging on device
# Connect via USB
flutter devices
flutter run --release
```

---

## Post-Build Verification

### 1. Check Build Size

```bash
# Web
cd flutter_client/build/web
du -sh *

# APK
ls -lh flutter_client/build/app/outputs/flutter-apk/app-release.apk
```

**Expected:**
- Web: ~3-5 MB total
- APK: ~30-50 MB

### 2. Test Core Flows

**Web:**
1. Open `build/web/index.html` in browser
2. Create invoice (test keyboard shortcuts: Alt+F, Alt+I, Ctrl+S)
3. Test table navigation (J/K, Ctrl+D, Alt+C)
4. Verify PDF generation
5. Test mobile view (responsive)

**Android:**
1. Install APK on device
2. Create invoice (touch-optimized)
3. Test mobile quick actions
4. Verify dashboard loads
5. Test offline mode (if implemented)

---

## Common Build Issues & Fixes

### Issue: "No supported devices connected"

**Fix:** 
```bash
# Enable Chrome for web
flutter config --enable-web

# List devices
flutter devices

# Run on Chrome
flutter run -d chrome
```

### Issue: "Minimum supported Flutter version is 3.13.0"

**Fix:**
```bash
flutter upgrade
```

### Issue: Android build fails with "SDK not found"

**Fix:**
```bash
# Set Android SDK path
export ANDROID_HOME=/path/to/android/sdk
flutter config --android-sdk $ANDROID_HOME

# Accept licenses
flutter doctor --android-licenses
```

### Issue: "SigningConfig not found" (Android)

**Fix:** Edit `flutter_client/android/app/build.gradle`:

```gradle
android {
    signingConfigs {
        release {
            keyAlias 'your_key_alias'
            keyPassword 'your_key_password'
            storeFile file('path/to/keystore.jks')
            storePassword 'your_store_password'
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

### Issue: Web build shows blank screen

**Fix:** Check console errors, likely missing base href:

```bash
flutter build web --release --base-href /
```

---

## Deployment Instructions

### Deploy Web to Firebase Hosting

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Initialize (first time)
firebase init hosting

# Select 'flutter_client/build/web' as public directory
# Configure rewrites: Single Page App → Yes

# Deploy
firebase deploy --only hosting
```

### Deploy Web to Vercel

```bash
# Install Vercel CLI
npm install -g vercel

# Deploy
cd flutter_client/build/web
vercel --prod
```

### Deploy Web to Netlify

```bash
# Drag-and-drop build/web folder to netlify.com
# Or use Netlify CLI:
npm install -g netlify-cli
netlify deploy --prod --dir=flutter_client/build/web
```

### Deploy Android APK

1. **Test Build:** Share APK via Google Drive, Dropbox
2. **Play Store:** Upload `.aab` to Google Play Console
3. **Direct Download:** Host APK on website with download link

---

## Build Verification Checklist

After building, verify:

- [ ] Web build loads in Chrome/Edge/Firefox
- [ ] Invoice creation works (<30s target)
- [ ] Keyboard shortcuts functional (Alt+F, Ctrl+S, etc.)
- [ ] Tables render correctly (sticky headers)
- [ ] Mobile view responsive
- [ ] PDF generation works
- [ ] APK installs on Android device
- [ ] No console errors (web)
- [ ] No crash on Android

---

## Next Steps After Build

### Week 1: Verification Sprint
- Create 340 transactions with real data
- Verify TB, P&L, BS reconcile
- Verify GSTR-1, GSTR-3B match
- Test multi-tenant isolation

### Week 2: Discount Beta
- Onboard 5 friendly users
- Daily check-ins
- Bug fixes only

### Week 3-10: Full Beta
- 20-50 companies
- Track daily active usage
- Collect NPS feedback

### After Success Criteria Met:
- Public launch
- Paid tiers
- Marketing

---

**Build Status:** ✅ Ready to build
**Git Status:** ✅ Commit `5c0f4e0` pushed
**Next:** Run build commands above on system with Flutter installed