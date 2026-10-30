import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _cyan = Color(0xFF00E5FF);

class CyberProgressBar extends StatefulWidget {
  final double progress;

  const CyberProgressBar({super.key, required this.progress});

  @override
  State<CyberProgressBar> createState() => _CyberProgressBarState();
}

class _CyberProgressBarState extends State<CyberProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${(progress * 100).toInt()}%',
            style: GoogleFonts.inter(
              color: _cyan,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _shimmer,
          builder: (_, _) => SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF252C3D),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00B8CC),
                          _cyan,
                          if (progress > 0.9) const Color(0xFF69FF47),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: _cyan.withValues(alpha: 0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
                if (progress > 0.01 && progress < 0.99)
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: 0.12,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.4 * _shimmer.value),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class FileProgressBar extends StatelessWidget {
  final double progress;

  const FileProgressBar({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dosya İndirme: ${(progress * 100).toStringAsFixed(1)}%',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 10),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
          ),
        ),
      ],
    );
  }
}
