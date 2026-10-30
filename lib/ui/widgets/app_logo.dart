import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final String? url;
  final double size;

  const AppLogo({super.key, required this.url, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.apps, color: const Color(0xFF00E5FF), size: size * 0.65);
    return SizedBox(
      width: size,
      height: size,
      child: url == null
          ? fallback
          : Image.network(url!, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback),
    );
  }
}
