import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/catalog.dart';
import '../../services/store_controller.dart';
import '../../services/update_service.dart';
import '../app_detail_page.dart';
import 'app_actions.dart';
import 'app_logo.dart';

class AppCard extends StatelessWidget {
  final AppController c;

  const AppCard({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final app = c.app;
        final version = c.info?.installedVersion;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF13161E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x2E00E5FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => AppDetailPage(c: c)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppLogo(url: app.logoUrl),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                app.name,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (app.category != null || version != null)
                                Text(
                                  [?app.category, if (version != null) 'v$version'].join(' · '),
                                  style: const TextStyle(color: Color(0xFF7A8BAA), fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        if (c.hasUpdate)
                          const Icon(Icons.system_update_alt, color: Colors.amberAccent, size: 18),
                        if (UpdateService.isDesktop && c.isInstalled && !c.busy)
                          IconButton(
                            tooltip: 'Kaldır',
                            iconSize: 18,
                            color: const Color(0xFFFF5370),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => confirmUninstall(context, c),
                          ),
                      ],
                    ),
                    if (app.description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        app.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF9AA8C0), fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (UpdateService.isDesktop && app.variants.length > 1) ...[
                VariantPicker(c: c),
                const SizedBox(height: 10),
              ],
              AppActions(c: c),
            ],
          ),
        );
      },
    );
  }
}

class VariantPicker extends StatelessWidget {
  final AppController c;
  final bool needInfo;

  const VariantPicker({super.key, required this.c, this.needInfo = false});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<Variant>(
      value: c.variant,
      isExpanded: true,
      dropdownColor: const Color(0xFF1B1F2B),
      items: [
        for (final v in c.app.variants) DropdownMenuItem(value: v, child: Text(v.name)),
      ],
      onChanged: c.busy ? null : (v) => c.selectVariant(v!, needInfo: needInfo),
    );
  }
}
