import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/store_controller.dart';
import '../../services/update_service.dart';
import 'progress_bars.dart';

const _cyan = Color(0xFF00E5FF);

/// İndir / Güncelle / Aç / Mağazaya git düğmeleri ve ilerleme. Kart ve detay
/// sayfası aynı widget'ı kullanır.
class AppActions extends StatelessWidget {
  final AppController c;

  const AppActions({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (!UpdateService.isDesktop) {
      final url = c.app.mobile[c.os];
      children.add(
        _button(
          url == null ? 'Bu platformda yok' : 'Mağazaya git',
          Icons.storefront_outlined,
          url == null ? null : () => _openStore(context, url),
        ),
      );
    } else if (c.variant == null || c.target == null) {
      children.add(_button('${c.os} için sürüm yok', Icons.block, null));
    } else if (c.busy) {
      children.addAll([
        Text(c.message, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 8),
        CyberProgressBar(progress: c.total),
        const SizedBox(height: 8),
        FileProgressBar(progress: c.file),
      ]);
    } else {
      switch (c.status) {
        case null:
          children.add(_button('Kontrol ediliyor...', Icons.sync, null));
        case AppStatus.notInstalled:
          children.add(_button('İndir', Icons.download, c.install));
        case AppStatus.updateAvailable:
          children.add(_button('Güncelle', Icons.system_update_alt, c.install));
          children.add(const SizedBox(height: 6));
          children.add(_button('Aç', Icons.play_arrow, c.open, outlined: true));
        case AppStatus.upToDate:
          children.add(_button('Aç', Icons.play_arrow, c.open));
        case AppStatus.offline:
          children.add(_button('Aç', Icons.play_arrow, c.open));
          children.add(const SizedBox(height: 6));
          children.add(_button('Yeniden dene', Icons.refresh, c.refresh, outlined: true));
      }
    }

    if (c.error != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(c.error!, style: const TextStyle(color: Color(0xFFFF5370), fontSize: 11)),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Future<void> _openStore(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) messenger.showSnackBar(SnackBar(content: Text('Mağaza açılamadı: $url')));
  }

  Widget _button(String label, IconData icon, VoidCallback? onPressed, {bool outlined = false}) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Icon(icon, size: 16), const SizedBox(width: 8), Text(label)],
    );
    return outlined
        ? OutlinedButton(onPressed: onPressed, child: child)
        : FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.black),
            onPressed: onPressed,
            child: child,
          );
  }
}
