// Widget tests for ApexDataTable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/theme/app_theme.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/tables/apex_data_table.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';

class _TestModel extends BaseModel {
  const _TestModel({required this.id, required this.name, required this.value});
  @override
  final String id;
  final String name;
  final double value;
  @override
  _TestModel fromJson(Map<String, dynamic> json) => this;
  @override
  Map<String, dynamic> toJson() => {};
}

void main() {
  testWidgets('ApexDataTable renders rows', (tester) async {
    final tableCtrl = ApexTableController();
    await tester.pumpWidget(
      MaterialApp(
        theme: apexLightTheme(),
        home: Scaffold(
          body: ApexDataTable<_TestModel>(
            columns: [
              ApexColumn(
                id: 'name',
                label: 'Name',
                value: (r) => r.name,
                sortable: true,
                width: 200,
              ),
              ApexColumn(
                id: 'value',
                label: 'Value',
                value: (r) => r.value.toString(),
                alignment: Alignment.centerRight,
                width: 120,
              ),
            ],
            rows: const Paged<_TestModel>(
              items: [
                _TestModel(id: '1', name: 'Alpha', value: 100),
                _TestModel(id: '2', name: 'Beta', value: 200),
              ],
              total: 2,
              page: 1,
              limit: 20,
            ),
            controller: tableCtrl,
            isLoading: false,
            error: null,
            onRetry: null,
          ),
        ),
      ),
    );

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });
}
