import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:codenfast_updater/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:process_run/shell.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS  (canonical copies also live in lib/models/ — keep in sync)
// ─────────────────────────────────────────────────────────────────────────────

class FileEntry {
  final String name;
  final int fileSize;
  final String path;
  final String url;

  const FileEntry({
    required this.name,
    required this.fileSize,
    required this.path,
    required this.url,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    name: json['name'] as String,
    fileSize: json['fileSize'] as int,
    path: json['path'] as String,
    url: json['url'] as String,
  );
}

class OsFiles {
  final String os;
  final List<FileEntry> fileList;
  final List<String> runCommands;

  const OsFiles({
    required this.os,
    required this.fileList,
    required this.runCommands,
  });

  factory OsFiles.fromJson(Map<String, dynamic> json) => OsFiles(
    os: json['os'] as String,
    fileList: (json['fileList'] as List)
        .map((i) => FileEntry.fromJson(i as Map<String, dynamic>))
        .toList(),
    runCommands: List<String>.from(json['runCommands'] as List),
  );
}

class RootContext {
  final List<OsFiles> osFileList;

  const RootContext({required this.osFileList});

  factory RootContext.fromJson(Map<String, dynamic> json) => RootContext(
    osFileList: (json['osFileList'] as List)
        .map((i) => OsFiles.fromJson(i as Map<String, dynamic>))
        .toList(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  HttpOverrides.global = MyHttpOverrides();

  if (args.contains('--generate') || args.contains('-g')) {
    await _runGenerator(args);
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();

  ByteData letsEncryptR3 = await PlatformAssetBundle().load(
    'assets/trusted-certs/lets-encrypt-r3.pem',
  );
  ByteData sectigoRSADomainValidationSecureServerCA =
  await PlatformAssetBundle().load(
    'assets/trusted-certs/SectigoRSADomainValidationSecureServerCA.crt',
  );
  ByteData sectigoRSAExtendedValidationSecureServerCA =
  await PlatformAssetBundle().load(
    'assets/trusted-certs/SectigoRSAExtendedValidationSecureServerCA.crt',
  );
  ByteData sectigoRSAOrganizationValidationSecureServerCA =
  await PlatformAssetBundle().load(
    'assets/trusted-certs/SectigoRSAOrganizationValidationSecureServerCA.crt',
  );

  SecurityContext.defaultContext.setTrustedCertificatesBytes(
    letsEncryptR3.buffer.asUint8List(),
  );
  SecurityContext.defaultContext.setTrustedCertificatesBytes(
    sectigoRSADomainValidationSecureServerCA.buffer.asUint8List(),
  );
  SecurityContext.defaultContext.setTrustedCertificatesBytes(
    sectigoRSAExtendedValidationSecureServerCA.buffer.asUint8List(),
  );
  SecurityContext.defaultContext.setTrustedCertificatesBytes(
    sectigoRSAOrganizationValidationSecureServerCA.buffer.asUint8List(),
  );

  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// APP ROOT
// ─────────────────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = CodenfastTheme();
    return MaterialApp(
      title: 'DSigner EImza Updater',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        canvasColor: Colors.black,
        primarySwatch: theme.blackTransparent,
        textTheme: theme.textTheme(),
        primaryTextTheme: theme.textTheme(),
        colorScheme: theme.colorScheme(),
        iconTheme: theme.iconTheme(),
        inputDecorationTheme: theme.inputDecorationTheme(),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF00E5FF),
          linearTrackColor: Color(0xFF252C3D),
        ),
        snackBarTheme: SnackBarThemeData(
          contentTextStyle: theme.textTheme().bodySmall,
          backgroundColor: Colors.black,
        ),
        dialogTheme: DialogThemeData(
          contentTextStyle: theme.textTheme().bodySmall,
          backgroundColor: const Color(0xFF1B1F2B),
          iconColor: Colors.white,
          titleTextStyle: theme.textTheme().titleSmall,
          elevation: 8,
          alignment: Alignment.center,
          actionsPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0x2E00E5FF), width: 1),
          ),
        ),
        focusColor: Colors.cyan,
        appBarTheme: AppBarTheme(
          backgroundColor: theme.cyanTransparent,
          foregroundColor: Colors.white,
          iconTheme: theme.iconTheme(),
          titleTextStyle: theme.textTheme().titleLarge,
          toolbarTextStyle: theme.textTheme().bodySmall,
          centerTitle: true,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOME / LOADING SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // ── Update state ───────────────────────────────────────────────────────────
  String _statusMessage = 'Initializing...';
  double _progress = 0.0;

  static const String _jsonUrl = 'http://dsigner.com.tr/eimza2/files.json';

  // ── Logo animation controllers ─────────────────────────────────────────────
  late final AnimationController _logoFadeCtrl;
  late final AnimationController _logoPulseCtrl;
  late final AnimationController _logoGlowCtrl;
  late final AnimationController _scanCtrl;
  late final AnimationController _progressShimmerCtrl;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoPulse;
  late final Animation<double> _logoGlow;
  late final Animation<double> _scanLine;

  // ── Logo rotation ──────────────────────────────────────────────────────────
  int _logoIndex = 0;
  Timer? _logoSwitchTimer;

  static const List<String> _logoAssets = [
    'assets/images/DeadLineLogo.png',
    'assets/images/codenfast_logo_transparent_2688_1242.webp',
  ];

  // ── Glitch text ────────────────────────────────────────────────────────────
  String _displayStatus = 'Initializing...';
  static const _glitchChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#@!%';
  final _rng = Random();

  @override
  void initState() {
    super.initState();

    // ── Logo fade-in + scale (entrance, one-shot) ──────────────────────────
    _logoFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _logoFadeCtrl, curve: Curves.easeOutCubic),
    );
    _logoScale = Tween<double>(begin: 0.78, end: 1.0).animate(
      CurvedAnimation(parent: _logoFadeCtrl, curve: Curves.easeOutBack),
    );

    // ── Subtle pulse (looping while active) ───────────────────────────────
    _logoPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _logoPulse = Tween<double>(
      begin: 1.0,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _logoPulseCtrl, curve: Curves.easeInOut));

    // ── Cyan glow pulse (looping) ──────────────────────────────────────────
    _logoGlowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
    _logoGlow = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _logoGlowCtrl, curve: Curves.easeInOut));

    // ── Horizontal scan line across logo (looping) ────────────────────────
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _scanLine = Tween<double>(
      begin: -1.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut));

    // ── Progress bar shimmer ───────────────────────────────────────────────
    _progressShimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    // Play entrance, then start update process + logo rotation timer
    _logoFadeCtrl.forward().then((_) {
      WidgetsBinding.instance.addPostFrameCallback(
            (_) => _startUpdateProcess(),
      );
      // Switch logo every 4 seconds with a smooth cross-fade
      _logoSwitchTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) {
          setState(() {
            _logoIndex = (_logoIndex + 1) % _logoAssets.length;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _logoFadeCtrl.dispose();
    _logoPulseCtrl.dispose();
    _logoGlowCtrl.dispose();
    _scanCtrl.dispose();
    _progressShimmerCtrl.dispose();
    _logoSwitchTimer?.cancel();
    super.dispose();
  }

  // ── Status helper with glitch effect ──────────────────────────────────────
  void _setStatus(String message, double progress) {
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _statusMessage = message;
    });
    _runGlitch(message);
  }

  void _runGlitch(String target) async {
    for (int i = 0; i < 6; i++) {
      await Future.delayed(const Duration(milliseconds: 42));
      if (!mounted) return;
      setState(() {
        _displayStatus = target.split('').map((c) {
          if (c == ' ') return ' ';
          return _rng.nextBool()
              ? c
              : _glitchChars[_rng.nextInt(_glitchChars.length)];
        }).join();
      });
    }
    if (mounted) setState(() => _displayStatus = target);
  }

  // ── OS detection ───────────────────────────────────────────────────────────
  String _getOperatingSystem() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'unsupported';
  }

  // ── Error dialog ───────────────────────────────────────────────────────────
  Future<void> _showErrorDialog(String message) async {
    if (!mounted) return;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFFF5370), size: 22),
            SizedBox(width: 10),
            Text('Update Error'),
          ],
        ),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              exit(1);
            },
            child: const Text('EXIT'),
          ),
        ],
      ),
    );
  }

  // ── Core update logic ──────────────────────────────────────────────────────
  Future<void> _startUpdateProcess() async {
    try {
      // 1. Determine OS
      _setStatus('Detecting operating system...', 0.0);
      final osType = _getOperatingSystem();
      if (osType == 'unsupported') {
        throw Exception('Unsupported operating system.');
      }
      _setStatus('OS detected: $osType', 0.02);

      // 2. Fetch configuration
      _setStatus('Fetching configuration...', 0.05);
      final response = await http.get(Uri.parse(_jsonUrl));
      if (response.statusCode != 200) {
        throw Exception(
          'Server returned ${response.statusCode} for configuration.',
        );
      }
      final config = RootContext.fromJson(
        json.decode(response.body) as Map<String, dynamic>,
      );
      final osFiles = config.osFileList.firstWhere(
            (f) => f.os == osType,
        orElse: () => throw Exception('No config found for OS: $osType'),
      );
      _setStatus('Configuration loaded.', 0.10);

      // 3. Process files
      final appDir = Directory.current;
      int filesProcessed = 0;
      final total = osFiles.fileList.length;

      for (final entry in osFiles.fileList) {
        final localDir = Directory('${appDir.path}/${entry.path}');
        if (!await localDir.exists()) {
          await localDir.create(recursive: true);
        }

        final filePath = '${localDir.path}/${entry.name}';
        final file = File(filePath);
        bool downloadRequired = true;

        if (await file.exists() && await file.length() == entry.fileSize) {
          downloadRequired = false;
        }

        if (downloadRequired) {
          _setStatus(
            'Downloading: ${entry.name}',
            0.10 + 0.80 * (filesProcessed / total),
          );
          final dl = await http.get(Uri.parse(entry.url));
          if (dl.statusCode != 200) {
            throw Exception(
              'Failed to download ${entry.name} (HTTP ${dl.statusCode}).',
            );
          }
          await file.writeAsBytes(dl.bodyBytes);
          if (await file.length() != entry.fileSize) {
            throw Exception('Size mismatch for ${entry.name} after download.');
          }
        }

        filesProcessed++;
        _setStatus(
          downloadRequired
              ? '↓ ${entry.name} downloaded.'
              : '✓ ${entry.name} up to date.',
          0.10 + 0.80 * (filesProcessed / total),
        );
      }

      // 4. Run post-update commands
      _setStatus('All files verified.', 0.92);
      if (osFiles.runCommands.isNotEmpty) {
        _setStatus('Executing launch commands...', 0.95);
        final shell = Shell(workingDirectory: appDir.path);
        final commands = osFiles.runCommands;
        for (int i = 0; i < commands.length; i++) {
          if (i < commands.length - 1) {
            await shell.run(commands[i]);
          } else {
            // ignore: unawaited_futures
            shell.run(commands[i]);
          }
        }
      }

      // 5. Done
      _setStatus('Update complete! Launching...', 1.0);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) exit(0);
    } catch (e) {
      if (mounted) {
        _setStatus('Error: ${e.toString()}', 0.0);
        await _showErrorDialog(e.toString());
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = CodenfastTheme();
    return Scaffold(
      // appBar: AppBar(title: const Text('Codenfast Updater')),
      body: theme.getBody(
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Animated logo with cross-fade switching ───────────────
                _AnimatedLogo(
                  fadeOpacity: _logoOpacity,
                  scale: _logoScale,
                  pulse: _logoPulse,
                  glow: _logoGlow,
                  scanLine: _scanLine,
                  logoAssets: _logoAssets,
                  logoIndex: _logoIndex,
                ),
                const SizedBox(height: 40),

                // ── Glitch status text ───────────────────────────────────
                _GlitchStatusText(displayText: _displayStatus),
                const SizedBox(height: 20),

                // ── Themed progress bar ──────────────────────────────────
                _CyberProgressBar(
                  progress: _progress,
                  shimmer: _progressShimmerCtrl,
                ),
                const SizedBox(height: 24),

                // ── URL chips ────────────────────────────────────────────
                const _UrlStrip(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATED LOGO  — fixed shape + cross-fade logo switching
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedLogo extends StatelessWidget {
  final Animation<double> fadeOpacity;
  final Animation<double> scale;
  final Animation<double> pulse;
  final Animation<double> glow;
  final Animation<double> scanLine;
  final List<String> logoAssets;
  final int logoIndex;

  const _AnimatedLogo({
    required this.fadeOpacity,
    required this.scale,
    required this.pulse,
    required this.glow,
    required this.scanLine,
    required this.logoAssets,
    required this.logoIndex,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeOpacity,
      child: ScaleTransition(
        scale: scale,
        child: AnimatedBuilder(
          animation: Listenable.merge([pulse, glow, scanLine]),
          builder: (_, __) {
            return Transform.scale(
              scale: pulse.value,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ambient glow ring (circular, purely decorative)
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF)
                              .withOpacity(0.18 * glow.value),
                          blurRadius: 56,
                          spreadRadius: 16,
                        ),
                      ],
                    ),
                  ),

                  // Logo card — rectangular with rounded corners
                  // FIX: was BoxShape.circle with width≠height, which caused
                  //      the circle to clip the wide logo image incorrectly.
                  Container(
                    width: 320,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: const Color(0xFF13161E),
                      border: Border.all(
                        color: Color.lerp(
                          const Color(0x2200E5FF),
                          const Color(0x9900E5FF),
                          glow.value,
                        )!,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF)
                              .withOpacity(0.12 * glow.value),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: Stack(
                        children: [
                          // Cross-fade between all logo assets
                          for (int i = 0; i < logoAssets.length; i++)
                            AnimatedOpacity(
                              opacity: i == logoIndex ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeInOut,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Image.asset(
                                    logoAssets[i],
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                    const _LogoFallback(),
                                  ),
                                ),
                              ),
                            ),

                          // Scan line overlay
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ScanLinePainter(scanLine.value),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCAN LINE PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _ScanLinePainter extends CustomPainter {
  final double position; // -1 → 1

  const _ScanLinePainter(this.position);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * (position + 1) / 2;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0x0000E5FF), Color(0x4400E5FF), Color(0x0000E5FF)],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromLTWH(0, y - 14, size.width, 28));

    canvas.drawRect(Rect.fromLTWH(0, y - 14, size.width, 28), paint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.position != position;
}

// ─────────────────────────────────────────────────────────────────────────────
// CORNER TICKS  (cyber HUD decoration)
// ─────────────────────────────────────────────────────────────────────────────

class _CornerTicks extends StatelessWidget {
  final double glow;

  const _CornerTicks({required this.glow});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 228,
      height: 228,
      child: CustomPaint(
        painter: _CornerTickPainter(
          Color.lerp(const Color(0x2200E5FF), const Color(0xBB00E5FF), glow)!,
        ),
      ),
    );
  }
}

class _CornerTickPainter extends CustomPainter {
  final Color color;

  const _CornerTickPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const len = 18.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final corner in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      final dx = corner.dx == 0 ? len : -len;
      final dy = corner.dy == 0 ? len : -len;
      canvas.drawLine(corner, Offset(corner.dx + dx, corner.dy), p);
      canvas.drawLine(corner, Offset(corner.dx, corner.dy + dy), p);
    }
  }

  @override
  bool shouldRepaint(_CornerTickPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGO FALLBACK
// ─────────────────────────────────────────────────────────────────────────────

class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF13161E),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.precision_manufacturing_outlined,
            color: Color(0xFF00E5FF),
            size: 64,
          ),
          SizedBox(height: 8),
          Text(
            'Codenfast',
            style: TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLITCH STATUS TEXT
// ─────────────────────────────────────────────────────────────────────────────

class _GlitchStatusText extends StatelessWidget {
  final String displayText;

  const _GlitchStatusText({required this.displayText});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: GoogleFonts.robotoMono(
          color: const Color(0xFFCCDDEE),
          fontSize: 13,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CYBER PROGRESS BAR
// ─────────────────────────────────────────────────────────────────────────────

class _CyberProgressBar extends StatelessWidget {
  final double progress;
  final AnimationController shimmer;

  const _CyberProgressBar({required this.progress, required this.shimmer});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Percentage label
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${(progress * 100).toInt()}%',
              style: GoogleFonts.robotoMono(
                color: const Color(0xFF00E5FF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
              ),
            ),
          ),

          // Track + animated fill
          AnimatedBuilder(
            animation: shimmer,
            builder: (_, __) => SizedBox(
              height: 6,
              child: Stack(
                children: [
                  // Track
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF252C3D),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),

                  // Fill
                  FractionallySizedBox(
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF00B8CC),
                            const Color(0xFF00E5FF),
                            if (progress > 0.9) const Color(0xFF69FF47),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Shimmer highlight on leading edge
                  if (progress > 0.01 && progress < 0.99)
                    FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FractionallySizedBox(
                          widthFactor: 0.12,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0),
                                  Colors.white.withOpacity(0.4 * shimmer.value),
                                  Colors.white.withOpacity(0),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// URL STRIP
// ─────────────────────────────────────────────────────────────────────────────

class _UrlStrip extends StatelessWidget {
  const _UrlStrip();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        InkWell(
          child: _UrlChip(
            label: 'http://dsigner.com.tr',
            icon: Icons.cloud_outlined,
          ),
          onTap: () async => launchUrl(Uri.parse('http://dsigner.com.tr')),
        ),
        InkWell(
          child: _UrlChip(
            label: 'http://deadline.tr',
            icon: Icons.cloud_outlined,
          ),
          onTap: () async => launchUrl(Uri.parse('http://deadline.tr')),
        ),
        InkWell(
          child: _UrlChip(label: 'http://codenfast.com', icon: Icons.language),
          onTap: () async => launchUrl(Uri.parse('http://codenfast.com')),
        ),
      ],
    );
  }
}

class _UrlChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _UrlChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF13161E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x2E00E5FF), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF7A8BAA)),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: const Color(0xFF7A8BAA),
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CLI GENERATOR
// ═════════════════════════════════════════════════════════════════════════════

class _GeneratorArgs {
  final List<String> ignorePatterns;
  final String outputPath;
  final String baseUrl;
  final List<String> runCommands;
  final String? osOverride;

  const _GeneratorArgs({
    required this.ignorePatterns,
    required this.outputPath,
    required this.baseUrl,
    required this.runCommands,
    required this.osOverride,
  });

  factory _GeneratorArgs.parse(List<String> args) {
    final ignorePatterns = <String>[];
    var outputPath = 'files.json';
    var baseUrl = 'http://app.codenfast.com/app';
    final runCommands = <String>[];
    String? osOverride;

    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--ignore':
          if (i + 1 < args.length) {
            final raw = args[++i];
            ignorePatterns.addAll(
              raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
            );
          }
          break;
        case '--output':
          if (i + 1 < args.length) outputPath = args[++i];
          break;
        case '--base-url':
          if (i + 1 < args.length) {
            baseUrl = args[++i].replaceAll(RegExp(r'/$'), '');
          }
          break;
        case '--run':
          if (i + 1 < args.length) runCommands.add(args[++i]);
          break;
        case '--os':
          if (i + 1 < args.length) osOverride = args[++i];
          break;
        case '--generate':
        case '-g':
          break;
      }
    }

    return _GeneratorArgs(
      ignorePatterns: ignorePatterns,
      outputPath: outputPath,
      baseUrl: baseUrl,
      runCommands: runCommands,
      osOverride: osOverride,
    );
  }
}

class _IgnoreMatcher {
  final List<String> _patterns;

  _IgnoreMatcher(List<String> patterns)
      : _patterns = patterns.map(_normalise).toList();

  static String _normalise(String p) => p.replaceAll('\\', '/').trim();

  bool matches(String relativePath) {
    final rel = relativePath.replaceAll('\\', '/');
    final name = rel.split('/').last;

    for (final pattern in _patterns) {
      if (!pattern.contains('*') && !pattern.contains('?')) {
        final clean = pattern.replaceAll('/', '');
        if (rel.split('/').contains(clean)) return true;
        if (rel == pattern || rel.startsWith('$pattern/')) return true;
        if (name == pattern) return true;
        continue;
      }
      if (pattern.startsWith('**/')) {
        final suffix = pattern.substring(3);
        if (_globMatch(suffix, name)) return true;
        for (final segment in rel.split('/')) {
          if (_globMatch(suffix, segment)) return true;
        }
        continue;
      }
      if (!pattern.contains('/')) {
        if (_globMatch(pattern, name)) return true;
        continue;
      }
      if (_globMatch(pattern, rel)) return true;
    }
    return false;
  }

  static bool _globMatch(String pattern, String input) {
    final regexStr = pattern.split('').map((c) {
      switch (c) {
        case '*':
          return '[^/]*';
        case '?':
          return '[^/]';
        case '.':
          return r'\.';
        case r'$':
          return r'\$';
        default:
          return RegExp.escape(c);
      }
    }).join();
    return RegExp('^$regexStr\$').hasMatch(input);
  }
}

String _detectOs() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  return 'unknown';
}

Future<void> _runGenerator(List<String> rawArgs) async {
  final args = _GeneratorArgs.parse(rawArgs);
  final matcher = _IgnoreMatcher(args.ignorePatterns);
  final osLabel = args.osOverride ?? _detectOs();
  final root = Directory.current;

  _log('');
  _log('╔══════════════════════════════════════════════╗');
  _log('║   Codenfast Updater — JSON Generator         ║');
  _log('╚══════════════════════════════════════════════╝');
  _log('');
  _log('  Root dir : ${root.path}');
  _log('  OS label : $osLabel');
  _log('  Base URL : ${args.baseUrl}');
  _log('  Output   : ${args.outputPath}');
  if (args.ignorePatterns.isNotEmpty) {
    _log('  Ignoring : ${args.ignorePatterns.join(', ')}');
  }
  if (args.runCommands.isNotEmpty) {
    _log('  Commands : ${args.runCommands.join(' | ')}');
  }
  _log('');

  final fileEntries = <Map<String, dynamic>>[];
  int scanned = 0;
  int ignored = 0;

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;

    final rel = entity.path
        .replaceAll('\\', '/')
        .replaceFirst('${root.path.replaceAll('\\', '/')}/', '');

    if (rel == args.outputPath.replaceAll('\\', '/')) {
      ignored++;
      continue;
    }

    if (matcher.matches(rel)) {
      _log('  SKIP  $rel');
      ignored++;
      continue;
    }

    final stat = await entity.stat();
    final fileSize = stat.size;

    final segments = rel.split('/');
    final name = segments.last;
    final dir = segments.length > 1
        ? segments.sublist(0, segments.length - 1).join('/')
        : '';

    final url = '${args.baseUrl}/$rel';

    fileEntries.add({
      'name': name,
      'fileSize': fileSize,
      'path': dir,
      'url': url,
    });

    scanned++;
    _log('  ADD   $rel  (${_formatSize(fileSize)})');
  }

  _log('');
  _log('  Scanned : $scanned file(s)');
  _log('  Ignored : $ignored file(s)');
  _log('');

  final rootContextJson = {
    'osFileList': [
      {'os': osLabel, 'fileList': fileEntries, 'runCommands': args.runCommands},
    ],
  };

  final outFile = File(args.outputPath);
  final parent = outFile.parent;
  if (!await parent.exists()) await parent.create(recursive: true);

  const encoder = JsonEncoder.withIndent('  ');
  await outFile.writeAsString(encoder.convert(rootContextJson));

  _log('  ✓ Written → ${outFile.path}');
  _log('');
  exit(0);
}

void _log(String msg) => stdout.writeln(msg);

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}