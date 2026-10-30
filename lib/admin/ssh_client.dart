import 'dart:io';

import 'admin_config.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

Future<ProcessResult> _defaultRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.run(executable, arguments, workingDirectory: workingDirectory);

/// Uzak yollar uzak kabukta yorumlanabildiği için (eski scp, `ssh komut`)
/// kısıtlı bir karakter kümesi dışında hiçbir şey kabul edilmez.
String requireSafeRemotePath(String path) {
  if (!RegExp(r'^/?[A-Za-z0-9._/-]+$').hasMatch(path) || path.split('/').contains('..')) {
    throw Exception('Güvenli olmayan uzak yol reddedildi: $path');
  }
  return path;
}

/// Sistemin `ssh`/`scp` komutlarını kullanır. Etkileşimsiz çalışır (BatchMode):
/// parolalı anahtarlar için ssh-agent gerekir.
class SshClient {
  final AdminConfig config;
  final ProcessRunner _run;

  SshClient(this.config, {ProcessRunner? runner}) : _run = runner ?? _defaultRunner;

  String get _target => '${config.user}@${config.host}';

  List<String> get _common => [
    '-o', 'BatchMode=yes',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', 'ConnectTimeout=15',
    if (config.keyPath.isNotEmpty) ...['-i', config.keyPath],
  ];

  Future<ProcessResult> _exec(String exe, List<String> args, {String? workingDirectory}) async {
    try {
      return await _run(exe, args, workingDirectory: workingDirectory);
    } on ProcessException {
      throw Exception('`$exe` komutu bulunamadı. OpenSSH istemcisi kurulu olmalı.');
    }
  }

  Never _fail(String what, ProcessResult r) {
    final err = '${r.stderr}'.trim();
    final hint = err.contains('Permission denied')
        ? '\nAnahtar dosyasını ve kullanıcıyı kontrol edin; parolalı anahtar için ssh-agent gerekir.'
        : '';
    throw Exception('$what başarısız (kod ${r.exitCode}): $err$hint');
  }

  Future<ProcessResult> _ssh(String command) =>
      _exec('ssh', ['-p', '${config.port}', ..._common, _target, command]);

  Future<void> test() async {
    final r = await _ssh('echo ok');
    if (r.exitCode != 0) _fail('Bağlantı', r);
  }

  Future<void> mkdirs(List<String> dirs) async {
    if (dirs.isEmpty) return;
    final r = await _ssh('mkdir -p ${dirs.map(requireSafeRemotePath).join(' ')}');
    if (r.exitCode != 0) _fail('Uzak klasör oluşturma', r);
  }

  Future<bool> fileExists(String remotePath) async {
    final r = await _ssh('test -f ${requireSafeRemotePath(remotePath)}');
    if (r.exitCode == 0) return true;
    if (r.exitCode == 1) return false;
    _fail('Uzak dosya kontrolü', r);
  }

  Future<void> download(String remotePath, File local) async {
    final r = await _exec('scp', [
      '-P', '${config.port}', ..._common,
      '$_target:${requireSafeRemotePath(remotePath)}',
      local.path,
    ]);
    if (r.exitCode != 0) _fail('İndirme ($remotePath)', r);
  }

  /// [localDir] içindeki [names] dosyalarını uzak [remoteDir] klasörüne yükler.
  /// Kaynaklar çalışma dizinine göre `./ad` biçiminde verilir; böylece `-` ile
  /// başlayan veya `:` içeren adlar seçenek/uzak sunucu sanılmaz.
  Future<void> upload(String localDir, List<String> names, String remoteDir) async {
    if (names.isEmpty) return;
    final r = await _exec(
      'scp',
      [
        '-P', '${config.port}', ..._common,
        for (final n in names) './$n',
        '$_target:${requireSafeRemotePath(remoteDir)}/',
      ],
      workingDirectory: localDir,
    );
    if (r.exitCode != 0) _fail('Yükleme ($remoteDir)', r);
  }

  /// Önce `.tmp` olarak yükler, sonra yerine taşır; istemciler yarım dosya görmez.
  Future<void> uploadAtomic(File local, String remotePath) async {
    requireSafeRemotePath(remotePath);
    final tmp = '$remotePath.tmp';
    final dir = remotePath.substring(0, remotePath.lastIndexOf('/'));
    final r = await _exec(
      'scp',
      ['-P', '${config.port}', ..._common, './${local.uri.pathSegments.last}', '$_target:$tmp'],
      workingDirectory: local.parent.path,
    );
    if (r.exitCode != 0) _fail('Yükleme ($remotePath)', r);
    final m = await _ssh('mv -f ${requireSafeRemotePath(tmp)} ${requireSafeRemotePath(remotePath)}');
    if (m.exitCode != 0) _fail('Taşıma ($dir)', m);
  }

  Future<void> copyRemote(String from, String to) async {
    final r = await _ssh('cp -f ${requireSafeRemotePath(from)} ${requireSafeRemotePath(to)}');
    if (r.exitCode != 0) _fail('Yedekleme', r);
  }
}
