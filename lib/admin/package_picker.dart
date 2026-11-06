import 'package:flutter/material.dart';

import 'installed_packages.dart';

/// Bu makinede kurulu paketlerden çoklu seçim. İptalde null, tamamda seçilen adlar.
Future<List<String>?> showPackagePicker(
  BuildContext context,
  InstalledResult result, {
  Set<String> alreadySelected = const {},
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => _PackagePicker(result: result, preselected: alreadySelected),
);

class _PackagePicker extends StatefulWidget {
  final InstalledResult result;
  final Set<String> preselected;

  const _PackagePicker({required this.result, required this.preselected});

  @override
  State<_PackagePicker> createState() => _PackagePickerState();
}

class _PackagePickerState extends State<_PackagePicker> {
  late final Set<String> _selected = {...widget.preselected};
  String _query = '';
  bool _onlyLibs = false;

  List<InstalledPackage> get _visible => [
    for (final p in widget.result.packages)
      if ((!_onlyLibs || p.isLibrary) && (_query.isEmpty || '${p.name} ${p.summary}'.toLowerCase().contains(_query))) p,
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return AlertDialog(
      title: const Text('Bu makinede elle kurulmuş paketler'),
      content: SizedBox(
        width: 640,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.result.filtered
                  ? 'Temiz imajda zaten bulunanlar elendi. Hedef makinede eksik olabilecekleri işaretleyin.'
                  : 'Temiz imajla karşılaştırılamadı (Docker?); liste temel sistem paketlerini de içerir.',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Ara...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Yalnızca lib*'),
                  selected: _onlyLibs,
                  onSelected: (v) => setState(() => _onlyLibs = v),
                ),
              ],
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _selected.addAll(visible.map((p) => p.name))),
                  child: const Text('Görünenleri seç'),
                ),
                TextButton(onPressed: () => setState(_selected.clear), child: const Text('Seçimi temizle')),
                const Spacer(),
                Text('${_selected.length} seçili', style: const TextStyle(fontSize: 12)),
              ],
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(
                      child: Text('Eşleşen paket yok.', style: TextStyle(color: Colors.white54)),
                    )
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final p = visible[i];
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.contains(p.name),
                          title: Text(p.name),
                          subtitle: Text(
                            [if (p.version.isNotEmpty) p.version, p.summary].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (v) =>
                              setState(() => v == true ? _selected.add(p.name) : _selected.remove(p.name)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('VAZGEÇ')),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected.toList()..sort()),
          child: const Text('LİSTEYE EKLE'),
        ),
      ],
    );
  }
}
