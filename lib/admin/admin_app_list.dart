import 'package:flutter/material.dart';

import '../ui/widgets/app_logo.dart';

/// Katalogdaki uygulamaların aranabilir, kategoriye göre süzülebilir listesi.
/// Yüzlerce kayıtta da akıcı olması için tembel (`ListView.builder`) çizilir.
class AdminAppList extends StatefulWidget {
  final List<Map<String, dynamic>> apps;
  final String? selectedId;
  final bool creating;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;

  const AdminAppList({
    super.key,
    required this.apps,
    required this.selectedId,
    required this.creating,
    required this.onSelect,
    required this.onNew,
  });

  @override
  State<AdminAppList> createState() => _AdminAppListState();
}

class _AdminAppListState extends State<AdminAppList> {
  final _search = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _s(Map<String, dynamic> a, String key) => (a[key] as String?) ?? '';

  List<String> get _categories =>
      ({for (final a in widget.apps) if (_s(a, 'category').isNotEmpty) _s(a, 'category')}.toList()..sort());

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final a in widget.apps)
        if ((_category == null || _s(a, 'category') == _category) &&
            (q.isEmpty ||
                [_s(a, 'id'), _s(a, 'name'), _s(a, 'category'), _s(a, 'description')]
                    .any((v) => v.toLowerCase().contains(q))))
          a,
    ]..sort((x, y) => _s(x, 'name').toLowerCase().compareTo(_s(y, 'name').toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final categories = _categories;
    // Kategori silinmiş/yeniden adlandırılmışsa süzgeç sıfırlanır.
    if (_category != null && !categories.contains(_category)) _category = null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _search,
            style: const TextStyle(fontSize: 13.5, color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Ara: ad, id, kategori, açıklama',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
        if (categories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonFormField<String?>(
              initialValue: _category,
              isDense: true,
              style: const TextStyle(fontSize: 13.5, color: Colors.white),
              dropdownColor: const Color(0xFF1B1F2B),
              decoration: const InputDecoration(labelText: 'Kategori', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tümü')),
                for (final c in categories) DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${items.length} / ${widget.apps.length} uygulama',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
              FilledButton.icon(
                onPressed: widget.onNew,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Yeni'),
              ),
            ],
          ),
        ),
        if (widget.creating)
          const ListTile(
            dense: true,
            selected: true,
            leading: Icon(Icons.add_box_outlined),
            title: Text('Yeni uygulama'),
          ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Eşleşen uygulama yok.', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final a = items[i];
                    final id = _s(a, 'id');
                    final cat = _s(a, 'category');
                    return ListTile(
                      dense: true,
                      selected: !widget.creating && id == widget.selectedId,
                      selectedTileColor: const Color(0x2200E5FF),
                      leading: AppLogo(url: a['logoUrl'] as String?, size: 32),
                      title: Text(
                        _s(a, 'name').isEmpty ? id : _s(a, 'name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(cat.isEmpty ? id : '$id · $cat', maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => widget.onSelect(id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
