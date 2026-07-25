# 🧠 MIND GAP — Brain Blocks Puzzle

255 seviyelik blok bulmaca oyunu. Tek dosyalık PWA (Progressive Web App) olarak
tasarlandı, GitHub Pages üzerinden yayınlanıp PWABuilder/Bubblewrap ile
Android APK'sına dönüştürülebilir.

## Dosya yapısı

```
index.html          → Oyunun tamamı (HTML+CSS+JS, tek dosya)
manifest.json        → PWA manifest (isim, ikonlar, tema rengi)
service-worker.js    → Offline cache stratejisi
icons/                → 192x192, 512x512, 512x512-maskable, apple-touch-icon
```

## Canlıya alma (GitHub Pages)

1. Bu klasörü bir GitHub reposuna push edin
2. Repo → Settings → Pages → Source: `main` branch, `/ (root)` klasör
3. Birkaç dakika içinde `https://<kullanici>.github.io/<repo-adi>/` adresinde yayınlanır

## APK'ya dönüştürme (PWABuilder)

1. https://www.pwabuilder.com adresine gidin
2. GitHub Pages URL'nizi girin, "Start" deyin
3. Manifest ve Service Worker otomatik algılanır (yeşil onay işaretleri görmelisiniz)
4. "Android" sekmesinden APK/AAB indirin (imzalama anahtarını güvenli saklayın)

Detaylı adımlar için konuşma geçmişindeki yönlendirmeye bakın.
