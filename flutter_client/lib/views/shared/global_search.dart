import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'dart:convert';

class GlobalSearchDelegate extends SearchDelegate<String> {
  @override
  List<Widget> buildActions(BuildContext context) {
    return [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, ''));
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearch(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearch(context);

  Widget _buildSearch(BuildContext context) {
    if (query.length < 2) {
      return Center(
        child: Text('Type to search...', style: AppTextStyles.bodySmall),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _search(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return const Center(child: Text('No results found'));
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item = results[index];
            return ListTile(
              leading: Icon(_iconForType(item['type']), size: 20),
              title: Text(item['name'] ?? '', style: AppTextStyles.bodyMedium),
              subtitle: Text(item['type'] ?? '', style: AppTextStyles.caption),
              onTap: () => close(context, item['id'] ?? ''),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _search(String query) async {
    final client = ApiClient();
    final results = <Map<String, dynamic>>[];

    try {
      // Search contacts
      final contacts = await client.get(Uri.parse('${ApiClient.baseUrl}/contacts?search=$query'));
      if (contacts.statusCode == 200) {
        for (final c in jsonDecode(contacts.body)) {
          results.add({'type': 'Contact', 'name': c['name'], 'id': c['id']});
        }
      }

      // Search products
      final products = await client.get(Uri.parse('${ApiClient.baseUrl}/products?search=$query'));
      if (products.statusCode == 200) {
        for (final p in jsonDecode(products.body)) {
          results.add({'type': 'Product', 'name': p['name'], 'id': p['id']});
        }
      }

      // Search invoices
      final invoices = await client.get(Uri.parse('${ApiClient.baseUrl}/invoices?search=$query'));
      if (invoices.statusCode == 200) {
        final data = jsonDecode(invoices.body);
        for (final inv in (data['items'] ?? [])) {
          results.add({'type': 'Invoice', 'name': inv['invoice_number'], 'id': inv['id']});
        }
      }
    } catch (_) {}

    return results;
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'Contact':
        return Icons.people;
      case 'Product':
        return Icons.inventory_2;
      case 'Invoice':
        return Icons.description;
      default:
        return Icons.search;
    }
  }
}
