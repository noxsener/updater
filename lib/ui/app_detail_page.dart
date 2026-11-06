import 'package:flutter/material.dart';

import '../services/store_controller.dart';
import '../services/update_service.dart';
import 'format.dart';
import 'widgets/app_actions.dart';
import 'widgets/app_card.dart';
import 'widgets/app_logo.dart';
import '../theme.dart';

class AppDetailPage extends StatefulWidget {
  final AppController c;

  const AppDetailPage({super.key, required this.c});

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  @override
  void initState() {
    super.initState();
    // Sürüm ve boyut bilgisi için manifest'i kurulu olmasa da çek.
    widget.c.refresh(needInfo: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Scaffold(
      appBar: AppBar(title: Text(c.app.name)),
      body: CodenfastTheme().getBody(
        ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final info = c.info;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        AppLogo(url: c.app.logoUrl, size: 72),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(c.app.name, style: Theme.of(context).textTheme.titleLarge),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (c.app.description.isNotEmpty)
                      Text(c.app.description, style: const TextStyle(color: Color(0xFF9AA8C0))),
                    const SizedBox(height: 16),
                    if (c.app.category != null) _row('Kategori', c.app.category!),
                    if (info?.installedVersion != null) _row('Kurulu sürüm', info!.installedVersion!),
                    if (info?.availableVersion != null) _row('Son sürüm', info!.availableVersion!),
                    if (info?.sizeBytes != null) _row('İndirme boyutu', formatBytes(info!.sizeBytes!)),
                    if (UpdateService.isDesktop && c.app.variants.length > 1) ...[
                      const SizedBox(height: 8),
                      VariantPicker(c: c, needInfo: true),
                    ],
                    const SizedBox(height: 16),
                    AppActions(c: c),
                    if (UpdateService.isDesktop && c.isInstalled && !c.busy) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF5370)),
                        onPressed: () => confirmUninstall(context, c),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Kaldır'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Color(0xFF7A8BAA), fontSize: 12))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}
