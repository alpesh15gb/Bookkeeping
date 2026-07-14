import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../data/models/product.dart';
import 'product_controller.dart';

/// Keyboard-wedge barcode entry shared by stock and document workflows.
///
/// USB/Bluetooth scanners on Windows, Android and iOS type into this field and
/// send Enter. Camera scanners can feed the same callback without duplicating
/// any product-resolution logic.
class BarcodeProductField extends ConsumerStatefulWidget {
  const BarcodeProductField({
    super.key,
    required this.onProduct,
    this.label = 'Scan barcode',
    this.autofocus = false,
  });

  final ValueChanged<Product> onProduct;
  final String label;
  final bool autofocus;

  @override
  ConsumerState<BarcodeProductField> createState() =>
      _BarcodeProductFieldState();
}

class _BarcodeProductFieldState extends ConsumerState<BarcodeProductField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _lookingUp = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final code = value.trim();
    if (code.isEmpty || _lookingUp) return;
    setState(() {
      _lookingUp = true;
      _error = null;
    });
    final result = await ref
        .read(productRepositoryProvider)
        .lookupBarcode(code);
    if (!mounted) return;
    if (result is Success<Product>) {
      widget.onProduct(result.value);
      _controller.clear();
    } else if (result is Failure<Product>) {
      _error = result.error.message;
    }
    setState(() => _lookingUp = false);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.done,
      onSubmitted: _submit,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'Scan or type a barcode, then press Enter',
        errorText: _error,
        prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
        suffixIcon: _lookingUp
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: 'Look up barcode',
                onPressed: () => _submit(_controller.text),
                icon: const Icon(Icons.keyboard_return_rounded),
              ),
      ),
    );
  }
}
