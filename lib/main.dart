import 'dart:io';

import 'package:codenfast_updater/generator/generator.dart';
import 'package:codenfast_updater/admin/admin_app.dart';
import 'package:codenfast_updater/ui/app_theme.dart';
import 'package:codenfast_updater/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _trustedCerts = [
  'assets/trusted-certs/lets-encrypt-r3.pem',
  'assets/trusted-certs/SectigoRSADomainValidationSecureServerCA.crt',
  'assets/trusted-certs/SectigoRSAExtendedValidationSecureServerCA.crt',
  'assets/trusted-certs/SectigoRSAOrganizationValidationSecureServerCA.crt',
];

Future<void> main(List<String> args) async {
  HttpOverrides.global = MyHttpOverrides();

  if (args.contains('--generate') || args.contains('-g')) {
    await runGenerator(args);
    exit(0);
  }
  WidgetsFlutterBinding.ensureInitialized();

  for (final asset in _trustedCerts) {
    final data = await PlatformAssetBundle().load(asset);
    SecurityContext.defaultContext.setTrustedCertificatesBytes(
      data.buffer.asUint8List(),
    );
  }

  runApp(args.contains('--admin') ? const AdminApp() : const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codenfast Uygulamalar',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
