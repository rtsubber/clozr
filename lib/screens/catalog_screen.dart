import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/service_catalog.dart';
import '../services/catalog_storage.dart';
import '../services/js_interop.dart';
import '../main.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  List<ServiceItem> _items = [];
  bool _isLoading = true;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final items = await CatalogStorage.load(ref.read(authProvider));
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  List<String> get _categories {
    final cats = _items.map((i) => i.category).toSet().toList();
    cats.sort();
    return ['All', ...cats];
  }

  List<ServiceItem> get _filtered {
    if (_filter == 'All') return _items;
    return _items.where((i) => i.category == _filter).toList();
  }

  IconData _iconForName(String name) {
    return switch (name) {
      'star' => Icons.star,
      'phone_android' => Icons.phone_android,
      'search' => Icons.search,
      'inventory' => Icons.inventory_2_outlined,
      'bar_chart' => Icons.bar_chart,
      'email' => Icons.email_outlined,
      'calendar_today' => Icons.calendar_today,
      'track_changes' => Icons.track_changes,
      'auto_awesome' => Icons.auto_awesome,
      'shopping_cart' => Icons.shopping_cart_outlined,
      'people' => Icons.people_outline,
      'support_agent' => Icons.support_agent,
      'trending_up' => Icons.trending_up,
      'cloud_sync' => Icons.cloud_sync,
      _ => Icons.auto_awesome,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0)),
                  ),
                  const Expanded(
                    child: Text('Service Catalog', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: _resetDefaults,
                    icon: const Icon(Icons.refresh_rounded, size: 22),
                    style: IconButton.styleFrom(foregroundColor: const Color(0xFF8B8BA0)),
                    tooltip: 'Reset to defaults',
                  ),
                  IconButton(
                    onPressed: _showImportDialog,
                    icon: const Icon(Icons.cloud_download_rounded, size: 22),
                    style: IconButton.styleFrom(foregroundColor: const Color(0xFF6C5CE7)),
                    tooltip: 'Import services',
                  ),
                ],
              ),
            ),

            // ── Description ──
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Text(
                'Customize the services Jarvis detects and proposes. These are what clients see in generated proposals.',
                style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0), height: 1.5),
              ),
            ),

            // ── Category Filter ──
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat == _filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _filter = cat),
                      backgroundColor: const Color(0xFF16161D),
                      selectedColor: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? const Color(0xFF6C5CE7) : const Color(0xFF8B8BA0),
                      ),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF6C5CE7) : const Color(0xFF2A2A3A),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // ── Service List ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)))
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF8B8BA0)),
                                const SizedBox(height: 12),
                                const Text('No services yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                const Text('Tap + to add your first service', style: TextStyle(fontSize: 13, color: Color(0xFF8B8BA0))),
                              ],
                            ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) => _serviceCard(_filtered[index]),
                        ),
            ),
          ],
        ),
      ),
      // ── Add Button ──
      floatingActionButton: FloatingActionButton(
        onPressed: _addService,
        backgroundColor: const Color(0xFF6C5CE7),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Widget _serviceCard(ServiceItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editService(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_iconForName(item.icon), color: const Color(0xFF6C5CE7), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(item.category, style: const TextStyle(fontSize: 12, color: Color(0xFF8B8BA0))),
                    ],
                  ),
                ),
                if (item.monthlyCost.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D2D3).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(item.monthlyCost,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF00D2D3))),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Color(0xFF8B8BA0), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addService() {
    _showServiceEditor(null);
  }

  void _editService(ServiceItem item) {
    _showServiceEditor(item);
  }

  void _showServiceEditor(ServiceItem? existing) {
    final isNew = existing == null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final categoryCtrl = TextEditingController(text: existing?.category ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final autoCtrl = TextEditingController(text: existing?.automation ?? '');
    final timeCtrl = TextEditingController(text: existing?.timeSaved ?? '');
    final costCtrl = TextEditingController(text: existing?.monthlyCost ?? '');
    String selectedIcon = existing?.icon ?? 'auto_awesome';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                    color: const Color(0xFF2A2A3A), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text(isNew ? 'Add Service' : 'Edit Service',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),

                // Name
                _field('Service Name', nameCtrl, 'e.g., Review Monitoring'),
                const SizedBox(height: 12),

                // Category
                _field('Category', categoryCtrl, 'e.g., Reputation Management'),
                const SizedBox(height: 12),

                // Description
                _field('Description', descCtrl, 'What this service does for the client', maxLines: 3),
                const SizedBox(height: 12),

                // How we automate it
                _field('How We Automate It', autoCtrl, 'Describe the automation process', maxLines: 2),
                const SizedBox(height: 12),

                // Time saved
                _field('Time Saved', timeCtrl, 'e.g., 45 min/day'),
                const SizedBox(height: 12),

                // Monthly cost
                _field('Monthly Cost', costCtrl, 'e.g., \$299'),
                const SizedBox(height: 20),

                // Icon picker
                const Text('Icon', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF8B8BA0))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['star', 'phone_android', 'search', 'inventory', 'bar_chart',
                      'email', 'calendar_today', 'track_changes', 'auto_awesome', 'shopping_cart',
                      'people', 'support_agent', 'trending_up', 'cloud_sync'].map((icon) {
                    final isSelected = icon == selectedIcon;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedIcon = icon),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF6C5CE7).withValues(alpha: 0.2) : const Color(0xFF0D0D12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? const Color(0xFF6C5CE7) : const Color(0xFF2A2A3A)),
                        ),
                        child: Icon(_iconForName(icon), size: 20,
                            color: isSelected ? const Color(0xFF6C5CE7) : const Color(0xFF8B8BA0)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      final item = ServiceItem(
                        id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameCtrl.text.trim(),
                        category: categoryCtrl.text.trim().isEmpty ? 'General' : categoryCtrl.text.trim(),
                        description: descCtrl.text.trim(),
                        automation: autoCtrl.text.trim(),
                        timeSaved: timeCtrl.text.trim(),
                        monthlyCost: costCtrl.text.trim(),
                        icon: selectedIcon,
                      );
                      if (isNew) {
                        await CatalogStorage.addItem(item, ref.read(authProvider));
                      } else {
                        await CatalogStorage.addItem(item, ref.read(authProvider));  // Update = add with same ID
                      }
                      if (mounted) {
                        Navigator.pop(context);
                        _loadCatalog();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(isNew ? 'Add Service' : 'Save Changes',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),

                if (!isNew) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () async {
                        await CatalogStorage.deleteItem(existing!.id, ref.read(authProvider));
                        if (mounted) {
                          Navigator.pop(context);
                          _loadCatalog();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B6B),
                        side: BorderSide(color: const Color(0xFFFF6B6B).withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Delete Service', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, String hint, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF8B8BA0))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF4A4A5A)),
            filled: true,
            fillColor: const Color(0xFF0D0D12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF6C5CE7)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16161D),
        title: const Text('Reset Catalog?'),
        content: const Text('This will replace your custom catalog with the default BrandBoost services.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Delete all items then reload defaults from server
      final items = await CatalogStorage.load(ref.read(authProvider));
      for (final item in items) {
        await CatalogStorage.deleteItem(item.id, ref.read(authProvider));
      }
      _loadCatalog();
    }
  }

  void _showImportDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ImportSheet(onImport: _loadCatalog),
    );
  }
}

class _ImportSheet extends ConsumerStatefulWidget {
  final VoidCallback onImport;
  const _ImportSheet({required this.onImport});

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  final _urlController = TextEditingController();
  bool _isImporting = false;
  String _status = '';
  String? _pdfFileName;
  List<Map<String, dynamic>> _imported = [];

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isImporting = true;
      _status = 'Fetching and analyzing...';
      _imported = [];
    });

    try {
      final auth = ref.read(authProvider);
      final response = await http.post(
        Uri.parse('${auth.apiUrl}/api/catalog/import-url'),
        headers: auth.authHeaders,
        body: jsonEncode({'url': url}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _imported = (data['services'] as List?)?.map((s) => s as Map<String, dynamic>).toList() ?? [];
          _status = 'Imported ${data['imported']} services!';
          _isImporting = false;
        });
        widget.onImport();
      } else {
        final error = jsonDecode(response.body);
        setState(() {
          _status = 'Error: ${error['detail'] ?? response.reasonPhrase}';
          _isImporting = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isImporting = false;
      });
    }
  }

  Future<void> _importFromPdf() async {
    // Use HTML file input for web
    if (!kIsWeb) return;

    setState(() {
      _isImporting = true;
      _status = 'Uploading and analyzing...';
      _imported = [];
    });

    try {
      // Create hidden file input via JS
      final result = await _pickFileViaJs();
      if (result == null) {
        setState(() {
          _isImporting = false;
          _status = '';
        });
        return;
      }

      final auth = ref.read(authProvider);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${auth.apiUrl}/api/catalog/import-pdf'),
      );
      request.headers.addAll(auth.authHeaders);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        result['bytes'] as List<int>,
        filename: result['name'] as String,
      ));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        setState(() {
          _imported = (data['services'] as List?)?.map((s) => s as Map<String, dynamic>).toList() ?? [];
          _status = 'Imported ${data['imported']} services!';
          _isImporting = false;
          _pdfFileName = result['name'] as String;
        });
        widget.onImport();
      } else {
        final error = jsonDecode(responseBody);
        setState(() {
          _status = 'Error: ${error['detail'] ?? response.reasonPhrase}';
          _isImporting = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isImporting = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _pickFileViaJs() async {
    // Use JS interop to create a file picker
    final completer = Completer<Map<String, dynamic>?>();

    final jsCode = '''
      (function() {
        var input = document.createElement('input');
        input.type = 'file';
        input.accept = '.pdf,.docx,.doc,.txt';
        input.onchange = function(e) {
          var file = e.target.files[0];
          if (!file) { window._clozrPdfResult = null; return; }
          var reader = new FileReader();
          reader.onload = function(ev) {
            window._clozrPdfResult = {
              name: file.name,
              bytes: Array.from(new Uint8Array(ev.target.result))
            };
          };
          reader.readAsArrayBuffer(file);
        };
        input.click();
      })();
    ''';

    // PDF import is web-only; on mobile, use file picker instead
    if (!kIsWeb) {
      // On mobile, we don't support PDF import yet
      // TODO: Add file picker for PDF on mobile
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF import available on web version'), backgroundColor: Color(0xFF8B8BA0)),
        );
      }
      return null;
    }

    // Web: inject PDF.js and handle import
    // The following code only runs on web where dart:js is available
    // ignore: avoid_web_libraries_in_flutter
    try {
      injectPdfJsScript();
    } catch (_) {}

    // Poll for result
    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final result = getPdfResult();
        if (result != null) {
          clearPdfResult();
          final name = result['name'] as String;
          final bytesList = result['bytes'] as List;
          return {'name': name, 'bytes': bytesList.cast<int>()};
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFF2A2A3A), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Import Services', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Paste your website URL or upload a PDF rate card.\nAI will extract your services and pricing.',
            style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0)),
          ),
          const SizedBox(height: 20),

          // URL import
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Color(0xFFE8E8F0)),
            decoration: InputDecoration(
              hintText: 'yourwebsite.com',
              hintStyle: const TextStyle(color: Color(0xFF4A4A5A)),
              prefixIcon: const Icon(Icons.language, color: Color(0xFF6C5CE7)),
              filled: true,
              fillColor: const Color(0xFF0D0D12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2A2A3A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6C5CE7)),
              ),
            ),
            onSubmitted: _isImporting ? null : (_) => _importFromUrl(),
          ),
          const SizedBox(height: 12),

          // Import button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isImporting ? null : _importFromUrl,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isImporting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Import from URL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),

          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_status, style: TextStyle(
              fontSize: 14,
              color: _status.startsWith('Error') ? const Color(0xFFFF6B6B) : const Color(0xFF00D2D3),
            )),
          ],

          if (_imported.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Imported:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            ..._imported.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Color(0xFF00D2D3)),
                  const SizedBox(width: 8),
                  Text('${s['name']} — ${s['category']}', style: const TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text('${s['price']}', style: const TextStyle(fontSize: 13, color: Color(0xFF8B8BA0))),
                ],
              ),
            )),
          ],

          const SizedBox(height: 20),
          const Divider(color: Color(0xFF2A2A3A)),
          const SizedBox(height: 12),

          // PDF upload
          const Text('Or upload a PDF', style: TextStyle(fontSize: 14, color: Color(0xFF8B8BA0))),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isImporting ? null : _importFromPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: Text(_pdfFileName ?? 'Choose PDF file',
                  style: const TextStyle(fontSize: 14)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C5CE7),
                side: const BorderSide(color: Color(0xFF2A2A3A)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}