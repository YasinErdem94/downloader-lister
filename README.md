# DownloaderLister

[Türkçe](#türkçe) · [English](#english)

## Türkçe

SwiftUI ile geliştirilen bir macOS uygulaması. Bağlantıları tek tek veya metin içinden ekleyip bir kuyrukta seçebilir ve MP3’e dönüştürebilirsin.

![Örnek kayıtlarla DownloaderLister indirme kuyruğu.](docs/downloader-lister.png)

### Kurulum

macOS 14 veya sonrası, Swift 6 (Xcode 16 veya sonrası) ve Homebrew gerekir.

```sh
brew install yt-dlp ffmpeg
swift run
```

### Kullanım

1. İki veya daha fazla bağlantıyı ayrı satırlara yapıştır veya **Metinden linkleri ayıkla** modunu seç.
2. **Link ekle** düğmesine bas. Bir oynatma listesi eklediğinde videolar ayrı ayrı görünür.
3. Kuyruktan istediklerini seç, kayıt klasörünü belirle ve **İndirmeyi başlat** düğmesine bas.

Aynı anda en fazla iki indirme çalışır. Çerez kaynağı seçersen uygulama ilgili tarayıcı profilini `yt-dlp` aracına iletir. İndirme hakkına sahip olduğun içerikleri kullan.

## English

A SwiftUI macOS app for adding links individually or extracting them from text, selecting items in a queue, and converting audio to MP3.

![DownloaderLister download queue with sample entries. The app interface is in Turkish.](docs/downloader-lister.png)

### Setup

Requires macOS 14 or later, Swift 6 (Xcode 16 or later), and Homebrew.

```sh
brew install yt-dlp ffmpeg
swift run
```

### Usage

1. Paste two or more links on separate lines, or select **Metinden linkleri ayıkla** to extract links from text.
2. Click **Link ekle** to add the links. Adding a playlist expands it into individual entries.
3. Select the entries you want, choose a destination folder, and click **İndirmeyi başlat**.

Up to two downloads run at a time. If you select a cookie source, the app passes the selected browser profile to `yt-dlp`. Use content you are allowed to download.
