import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/service_catalog.dart';
import 'auth_service.dart';

/// Catalog Storage — now via backend API (A4 fix)
/// Per-account catalog with multi-tenant isolation
class CatalogStorage {
  /// Load catalog from backend, falling back to local defaults
  static Future<List<ServiceItem>> load([AuthService? auth]) async {
    // Try backend first
    if (auth != null && auth.isAuthenticated) {
      try {
        final response = await http.get(
          Uri.parse('${auth.apiUrl}/api/catalog'),
          headers: auth.authHeaders,
        );

        if (response.statusCode == 200) {
          final List data = jsonDecode(response.body);
          if (data.isNotEmpty) {
            return data.map((item) => ServiceItem(
              id: item['id'] ?? '',
              name: item['name'] ?? '',
              category: item['category'] ?? 'General',
              description: item['description'] ?? '',
              automation: item['automation'] ?? '',
              timeSaved: item['time_saved'] ?? '',
              monthlyCost: item['monthly_cost'] ?? '',
              icon: item['icon'] ?? 'auto_awesome',
            )).toList();
          }
        }
      } catch (_) {
        // Server unreachable — fall through to defaults
      }
    }

    // Default catalog (matches backend seed)
    return DefaultCatalog.brandboost();
  }

  /// Save a catalog item to backend
  static Future<bool> addItem(ServiceItem item, AuthService auth) async {
    if (!auth.isAuthenticated) return false;

    try {
      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/catalog'),
        headers: auth.authHeaders,
        body: jsonEncode({
          'id': item.id,
          'name': item.name,
          'category': item.category,
          'description': item.description,
          'automation': item.automation,
          'time_saved': item.timeSaved,
          'monthly_cost': item.monthlyCost,
          'icon': item.icon,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Delete a catalog item from backend
  static Future<bool> deleteItem(String itemId, AuthService auth) async {
    if (!auth.isAuthenticated) return false;

    try {
      final response = await http.delete(
        Uri.parse('${auth.apiUrl}/api/catalog/$itemId'),
        headers: auth.authHeaders,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}