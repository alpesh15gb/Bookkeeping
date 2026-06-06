/// Feature gate layer for GST-dependent UI elements.
/// Read `tax_mode` from SettingsProvider._company to determine visibility.
class TaxFeatures {
  final String _taxMode;

  TaxFeatures(this._taxMode);

  bool get showGstReports =>
      _taxMode == 'GST_REGULAR' || _taxMode == 'GST_COMPOSITION';
  bool get showGstFields => showGstReports;
  bool get showEWayBills => _taxMode == 'GST_REGULAR';
  bool get showEinvoice => _taxMode == 'GST_REGULAR';

  static TaxFeatures empty() => TaxFeatures('NON_GST');
}
