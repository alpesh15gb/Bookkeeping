// Unit tests for Product model — parse, serialize, enum roundtrip.
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';

void main() {
  group('Product Model', () {
    test('fromJson parses full response', () {
      final json = {
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'tenant_id': 'tenant-1',
        'name': 'Steel Rod 12mm',
        'sku': 'SR-12',
        'hsn_sac': '72141000',
        'product_type': 'GOODS',
        'uom': 'PCS',
        'sales_price': '150.00',
        'purchase_price': '120.00',
        'gst_rate': '18.00',
        'opening_stock': '100.00',
        'current_stock': '40.00',
        'reorder_level': '20.00',
        'is_active': true,
        'created_at': '2025-07-01T10:00:00+00:00',
        'updated_at': '2025-07-02T10:00:00+00:00',
      };
      final p = const Product(id: '', name: '').fromJson(json);
      expect(p.id, '550e8400-e29b-41d4-a716-446655440000');
      expect(p.name, 'Steel Rod 12mm');
      expect(p.sku, 'SR-12');
      expect(p.hsnSac, '72141000');
      expect(p.productType, ProductType.goods);
      expect(p.uom, 'PCS');
      expect(p.salesPrice, 150.0);
      expect(p.purchasePrice, 120.0);
      expect(p.gstRate, 18.0);
      expect(p.openingStock, 100.0);
      expect(p.currentStock, 40.0);
      expect(p.reorderLevel, 20.0);
      expect(p.isActive, true);
      expect(p.createdAt, '2025-07-01T10:00:00+00:00');
    });

    test('fromJson handles minimal response', () {
      final json = {
        'id': 'abc-123',
        'name': 'Consulting Service',
        'product_type': 'SERVICE',
      };
      final p = const Product(id: '', name: '').fromJson(json);
      expect(p.id, 'abc-123');
      expect(p.name, 'Consulting Service');
      expect(p.productType, ProductType.service);
      expect(p.sku, isNull);
      expect(p.uom, 'PCS'); // default
      expect(p.salesPrice, 0);
      expect(p.isActive, true);
    });

    test('fromJson parses SERVICE product type', () {
      final json = {
        'id': 'p1',
        'name': 'Audit Service',
        'hsn_sac': '998321',
        'product_type': 'SERVICE',
      };
      final p = const Product(id: '', name: '').fromJson(json);
      expect(p.productType, ProductType.service);
    });

    test('toJson produces correct create payload', () {
      const p = Product(
        id: '',
        name: 'Cement Bag',
        sku: 'CEM-50',
        hsnSac: '25232900',
        productType: ProductType.goods,
        uom: 'BAG',
        salesPrice: 350,
        purchasePrice: 300,
        gstRate: 28,
        openingStock: 50,
        reorderLevel: 10,
      );
      final json = p.toJson();
      expect(json['name'], 'Cement Bag');
      expect(json['sku'], 'CEM-50');
      expect(json['hsn_sac'], '25232900');
      expect(json['product_type'], 'GOODS');
      expect(json['uom'], 'BAG');
      expect(json['sales_price'], '350.00');
      expect(json['purchase_price'], '300.00');
      expect(json['gst_rate'], '28.00');
      expect(json['opening_stock'], '50.00');
      expect(json['reorder_level'], '10.00');
      // is_active omitted when true (default)
      expect(json.containsKey('is_active'), false);
    });

    test(
      'toJson omits empty SKU and includes is_active=false when inactive',
      () {
        const p = Product(
          id: 'x-1',
          name: 'No SKU Item',
          hsnSac: '000000',
          productType: ProductType.goods,
          uom: 'NOS',
          isActive: false,
        );
        final json = p.toJson();
        expect(json.containsKey('sku'), false);
        expect(json['is_active'], false);
      },
    );

    test('ProductType enum fromApi and apiValue roundtrip', () {
      for (final type in ProductType.values) {
        expect(ProductType.fromApi(type.apiValue), type);
      }
    });

    test('ProductType.fromApi falls back to goods on unknown', () {
      expect(ProductType.fromApi('UNKNOWN'), ProductType.goods);
    });

    test('needsReorder true when stock at or below reorder level (goods)', () {
      const low = Product(
        id: '1',
        name: 'X',
        hsnSac: '123456',
        productType: ProductType.goods,
        currentStock: 5,
        reorderLevel: 10,
      );
      expect(low.needsReorder, true);

      const ok = Product(
        id: '2',
        name: 'Y',
        hsnSac: '123456',
        productType: ProductType.goods,
        currentStock: 50,
        reorderLevel: 10,
      );
      expect(ok.needsReorder, false);

      // Services never need reorder.
      const svc = Product(
        id: '3',
        name: 'Z',
        hsnSac: '998321',
        productType: ProductType.service,
        currentStock: 0,
        reorderLevel: 10,
      );
      expect(svc.needsReorder, false);
    });

    test('marginPercent computes sales over purchase', () {
      const p = Product(
        id: '1',
        name: 'M',
        hsnSac: '123456',
        productType: ProductType.goods,
        salesPrice: 150,
        purchasePrice: 100,
      );
      expect(p.marginPercent, 50.0);
    });

    test('marginPercent is 0 when purchase price is 0', () {
      const p = Product(
        id: '1',
        name: 'M',
        hsnSac: '123456',
        productType: ProductType.goods,
        salesPrice: 100,
        purchasePrice: 0,
      );
      expect(p.marginPercent, 0);
    });
  });
}
