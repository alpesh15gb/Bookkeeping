# Production Checklist

- [x] Run `flutter analyze` – no errors or warnings.
- [x] Run `flutter test` – all unit/widget tests pass.
- [x] Build debug APK – `flutter build apk --debug` succeeds.
- [x] Verify routes in `app_router.dart` cover all new screens.
- [x] Confirm repository calls are wired in all form actions (`_save`, `_delete`, etc.).
- [x] Confirm duplicate submit guard present on invoice and bill forms.
- [x] Confirm API error handling (`on ApiError catch`) displays user‑friendly SnackBar.
- [x] Confirm dark‑mode compliance on new screens (uses `AppTheme` colors).
- [x] Confirm responsive layout (`ConstrainedBox(maxWidth: 900)`).
- [x] Verify empty states (icons, titles, subtitles, clear‑filter) on list screens.
- [x] Verify date‑range filter on Expenses screen works.
- [x] Verify search + pagination on all list screens.
- [x] Verify export buttons present on report screens.
- [x] Verify GST E‑Invoice button and IRN generation on Invoice Detail.
- [x] Verify E‑Way Bill integration UI.
- [x] Verify final QA steps documented in `FINAL_QA_REPORT.md`.

All items verified – ready for release.
