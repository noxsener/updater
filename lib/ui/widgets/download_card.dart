import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/catalog.dart';
import '../../services/download_controller.dart';
import '../format.dart';
import 'app_logo.dart';
import 'progress_bars.dart';

const _cyan = Color(0xFF00E5FF);

/// "İşletim Sistemleri" sekmesindeki kart: dosya seç → İndir (durdur/devam) → klasörde göster.
class DownloadCard extends StatelessWidget {
  final DownloadController c;

  const DownloadCard({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final e = c.entry;
        final f = c.file;
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
              Row(
                children: [
                  AppLogo(url: e.logoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.name,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        if (e.category != null || e.version != null)
                          Text(
                            [?e.category, if (e.version != null) 'v${e.version}'].join(' · '),
                            style: const TextStyle(color: Color(0xFF7A8BAA), fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (e.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  e.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF9AA8C0), fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              if (e.files.length > 1)
                DropdownButton<DownloadFile>(
                  value: f,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1B1F2B),
                  items: [for (final x in e.files) DropdownMenuItem(value: x, child: Text(x.name))],
                  onChanged: c.busy ? null : (x) => c.select(x!),
                ),
              if (f != null) ...[_info(f), const SizedBox(height: 12), _actions(context, f)],
              if (f == null) const Text('Dosya tanımlı değil.', style: TextStyle(color: Color(0xFF7A8BAA))),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(c.error!, style: const TextStyle(color: Color(0xFFFF5370), fontSize: 11)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _info(DownloadFile f) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        [f.fileName, if (f.size != null) formatBytes(f.size!)].join(' · '),
        style: const TextStyle(color: Color(0xFF9AA8C0), fontSize: 11),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              'sha256: ${f.sha256.substring(0, 16)}…',
              style: const TextStyle(color: Color(0xFF7A8BAA), fontSize: 11),
            ),
          ),
          IconButton(
            tooltip: 'sha256 değerini kopyala',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => Clipboard.setData(ClipboardData(text: f.sha256)),
          ),
        ],
      ),
    ],
  );

  Widget _actions(BuildContext context, DownloadFile f) {
    switch (c.state) {
      case DownloadState.downloading:
        final p = c.progress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.total == null
                  ? formatBytes(c.received)
                  : '${formatBytes(c.received)} / ${formatBytes(c.total!)}',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 8),
            if (p == null) const LinearProgressIndicator() else CyberProgressBar(progress: p),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: c.cancel,
              icon: const Icon(Icons.pause, size: 16),
              label: const Text('Durdur'),
            ),
          ],
        );
      case DownloadState.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: _cyan),
                SizedBox(width: 6),
                Text('İndirildi', style: TextStyle(color: _cyan, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.black),
              onPressed: c.reveal,
              icon: const Icon(Icons.folder_open_outlined, size: 16),
              label: const Text('Klasörde göster'),
            ),
          ],
        );
      case DownloadState.idle:
      case DownloadState.error:
        return FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.black),
          onPressed: c.start,
          icon: const Icon(Icons.download, size: 16),
          label: const Text('İndir'),
        );
    }
  }
}
