/// Sunucudan gelen tüm URL'ler HTTPS olmak zorunda; yalnızca yerel geliştirme
/// sunucusu (localhost / Android emülatörü) için http'ye izin verilir.
Uri requireSecureUri(String url) {
  final uri = Uri.parse(url);
  const devHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
  if (uri.scheme == 'https' || (uri.scheme == 'http' && devHosts.contains(uri.host))) {
    return uri;
  }
  throw Exception('Güvenli olmayan URL reddedildi (https gerekli): $url');
}
