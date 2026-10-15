/// UI language of the example app.
///
/// Only the example's own text follows this setting. The native liveness
/// screen follows the device language.
enum AppLanguage {
  en('English'),
  tr('Türkçe');

  const AppLanguage(this.label);

  final String label;
}

/// The example app's text in [AppLanguage].
class Strings {
  const Strings(this.language);

  final AppLanguage language;

  bool get _tr => language == AppLanguage.tr;

  String get title => _tr ? 'Yüz canlılık örneği' : 'Face Liveness example';
  String get backend => 'Backend';
  String get backendUrl => _tr ? 'Backend adresi' : 'Backend URL';
  String get backendUrlHint => 'http://localhost:8787';
  String get token => _tr ? 'Erişim anahtarı' : 'Access token';
  String get save => _tr ? 'Kaydet' : 'Save';
  String get saved => _tr ? 'Kaydedildi' : 'Saved';
  String get invalidSettings => _tr
      ? 'Geçerli bir http(s) adresi ve anahtar girin.'
      : 'Enter a valid http(s) URL and a token.';
  String get options => _tr ? 'Seçenekler' : 'Options';
  String get challenge => _tr ? 'Görev' : 'Challenge';
  String get challengeServer => _tr ? 'Sunucu seçsin' : 'Server default';
  String get challengeMovement => 'FaceMovement';
  String get challengeMovementLight => 'FaceMovementAndLight';
  String get photosensitivity => _tr
      ? 'FaceMovementAndLight ekranda renkli ışıklar yakıp söndürür.'
      : 'FaceMovementAndLight flashes coloured light on screen.';
  String get camera => _tr ? 'Kamera (FaceMovement)' : 'Camera (FaceMovement)';
  String get front => _tr ? 'Ön' : 'Front';
  String get back => _tr ? 'Arka' : 'Back';
  String get startView => _tr ? 'Giriş ekranını göster' : 'Show start view';
  String get theme => _tr ? 'Tema' : 'Theme';
  String get system => _tr ? 'Sistem' : 'System';
  String get light => _tr ? 'Açık' : 'Light';
  String get dark => _tr ? 'Koyu' : 'Dark';
  String get languageLabel => _tr ? 'Dil' : 'Language';
  String get start => _tr ? 'Kontrolü başlat' : 'Start check';
  String get tryAgain => _tr ? 'Yeniden dene' : 'Try again';
  String get checkAvailability =>
      _tr ? 'Kullanılabilirliği kontrol et' : 'Check availability';
  String get available => _tr ? 'Kullanılabilir' : 'Available';
  String get unavailable => _tr ? 'Kullanılamıyor' : 'Unavailable';
  String get openSettings => _tr ? 'Ayarları aç' : 'Open settings';
  String get creatingSession =>
      _tr ? 'Oturum oluşturuluyor…' : 'Creating session…';
  String get checking => _tr ? 'Kontrol sürüyor…' : 'Check in progress…';
  String get readingResult => _tr
      ? 'Sonuç backend’den alınıyor…'
      : 'Reading the result from the backend…';
  String get live => _tr ? 'Canlı' : 'Live';
  String get notLive => _tr ? 'Canlı değil' : 'Not live';
  String get decidedByBackend =>
      _tr ? 'Karar backend tarafından verildi.' : 'Decided by the backend.';
  String get status => _tr ? 'Durum' : 'Status';
  String get confidence => _tr ? 'Güven' : 'Confidence';
  String get cancelled => _tr ? 'İptal edildi' : 'Cancelled';
  String get byUser => _tr ? 'kullanıcı' : 'user';
  String get byApp => _tr ? 'uygulama' : 'app';
  String get failed => _tr ? 'Başarısız' : 'Failed';
  String get category => _tr ? 'Kategori' : 'Category';
  String get retryable => _tr ? 'Yeniden denenebilir' : 'Retryable';
  String get yes => _tr ? 'evet' : 'yes';
  String get no => _tr ? 'hayır' : 'no';
  String get recovery => _tr ? 'Öneri' : 'Recovery';
  String get nativeDetails => _tr ? 'Native ayrıntılar' : 'Native details';
  String get backendError => _tr ? 'Backend hatası' : 'Backend error';
}
