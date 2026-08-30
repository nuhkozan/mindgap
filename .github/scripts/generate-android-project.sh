#!/usr/bin/env bash
# ============================================================================
# MIND GAP — WebView tabanlı native Android projesi üretici
#
# NEDEN TWA DEĞİL DE WEBVIEW:
# Gerçek AdMob ödüllü reklamlarını JavaScript'ten tetikleyebilmek için
# native kod ile web tarafı arasında bir köprü (JS bridge) gerekiyor.
# TWA (Trusted Web Activity), Chrome Custom Tabs üzerinden çalıştığı için
# bu köprüyü kurmaya izin vermiyor. Bu yüzden mimari WebView + MainActivity
# + addJavascriptInterface köprüsüne geçirildi.
#
# Yan fayda: WebView hiçbir zaman adres çubuğu göstermediği için artık
# assetlinks.json / Digital Asset Links doğrulamasına ihtiyaç yok.
#
# NEDEN BU SCRIPT VAR (Gradle projesi neden elle üretiliyor):
# Bubblewrap CLI'nin `init` komutu CI ortamında interaktif sorular sorup
# takılıyor (GoogleChromeLabs/bubblewrap#806 — hâlâ açık bir hata).
# Bu script standart bir Android Gradle projesini doğrudan üretiyor;
# sonrasında sadece Gradle çalışıyor ve hiçbir soru sormuyor. Böylece
# build %100 deterministik oluyor.
# ============================================================================
set -euo pipefail

APP_NAME="MIND GAP"
PACKAGE_ID="com.mindgap.app"
HOST="nuhkozan.github.io"
LAUNCH_URL="https://nuhkozan.github.io/mindgap/"
PATH_PREFIX="/mindgap/"
THEME_COLOR="#060A10"
BG_COLOR="#060A10"
VERSION_NAME="1.2.1"
VERSION_CODE="6"
ICON_URL="https://nuhkozan.github.io/mindgap/icons/icon-512.png"

# ── AdMob ──
# ✅ Test build başarıyla doğrulandı (gerçek test reklamı tam ekran gösterildi).
# Artık gerçek (production) ID'ler kullanılıyor.
ADMOB_APP_ID="ca-app-pub-5226177276862447~4336706536"
ADMOB_REWARDED_AD_UNIT_ID="ca-app-pub-5226177276862447/2037846257"

PROJ="android-project"
rm -rf "$PROJ"
mkdir -p "$PROJ/app/src/main/res/values"
mkdir -p "$PROJ/app/src/main/res/mipmap-xxxhdpi"
mkdir -p "$PROJ/app/src/main/res/drawable"
mkdir -p "$PROJ/app/src/main/java/com/mindgap/app"

echo "==> Proje iskeleti oluşturuluyor: $PROJ"

# ---------- settings.gradle ----------
cat > "$PROJ/settings.gradle" << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "MindGap"
include ':app'
EOF

# ---------- root build.gradle ----------
cat > "$PROJ/build.gradle" << 'EOF'
plugins {
    id 'com.android.application' version '8.10.0' apply false
}
EOF

# ---------- gradle.properties ----------
cat > "$PROJ/gradle.properties" << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
EOF

# ---------- app/build.gradle ----------
cat > "$PROJ/app/build.gradle" << EOF
plugins {
    id 'com.android.application'
}

android {
    namespace '$PACKAGE_ID'
    compileSdk 36

    defaultConfig {
        applicationId "$PACKAGE_ID"
        minSdk 23
        targetSdk 36
        versionCode $VERSION_CODE
        versionName "$VERSION_NAME"
    }

    signingConfigs {
        release {
            storeFile file(System.getenv("KEYSTORE_PATH") ?: "../../android.keystore")
            storePassword System.getenv("KEYSTORE_PASSWORD") ?: ""
            keyAlias System.getenv("KEY_ALIAS") ?: "mindgap"
            keyPassword System.getenv("KEY_PASSWORD") ?: ""
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled false
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

dependencies {
    implementation 'com.google.android.gms:play-services-ads:25.4.0'
    implementation 'com.google.android.ump:user-messaging-platform:4.0.0'
}
EOF

# ---------- AndroidManifest.xml ----------
cat > "$PROJ/app/src/main/AndroidManifest.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:theme="@style/AppTheme"
        android:supportsRtl="true">

        <!-- AdMob: bu olmadan MobileAds.initialize() hata verir -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="$ADMOB_APP_ID" />

        <activity
            android:name="com.mindgap.app.MainActivity"
            android:exported="true"
            android:label="@string/app_name"
            android:configChanges="orientation|screenSize|screenLayout|keyboard|keyboardHidden|uiMode"
            android:screenOrientation="portrait">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- Sunucusuz, tamamen cihaz-üzerinde günlük "geri dön" hatırlatması.
             Kullanıcı uygulamadan çıkınca ~24 saat sonrası için planlanır;
             tekrar açarsa iptal edilir. Firebase Cloud Functions / ücretli
             plan / push sunucusu GEREKTİRMEZ. -->
        <receiver
            android:name="com.mindgap.app.ReminderReceiver"
            android:exported="false" />
    </application>
</manifest>
EOF

# ---------- styles.xml ----------
# Tam ekran, başlık çubuğu yok, açılışta arka plan tema rengiyle uyumlu.
cat > "$PROJ/app/src/main/res/values/styles.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">@color/background_color</item>
        <item name="android:statusBarColor">@color/theme_color</item>
        <item name="android:navigationBarColor">@color/theme_color</item>
        <item name="android:windowFullscreen">false</item>
    </style>
</resources>
EOF

# ---------- strings.xml (varsayılan: Türkçe) ----------
cat > "$PROJ/app/src/main/res/values/strings.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">$APP_NAME</string>
    <string name="launch_url">$LAUNCH_URL</string>
    <string name="admob_rewarded_ad_unit_id">$ADMOB_REWARDED_AD_UNIT_ID</string>
    <string name="reminder_channel_name">Günlük Hatırlatma</string>
    <string name="reminder_title">🧠 Beynin seni bekliyor!</string>
    <string name="reminder_body">Serini bozma — bugün bir bulmaca daha çöz.</string>
</resources>
EOF

# ---------- strings.xml (İngilizce) ----------
mkdir -p "$PROJ/app/src/main/res/values-en"
cat > "$PROJ/app/src/main/res/values-en/strings.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="reminder_channel_name">Daily Reminder</string>
    <string name="reminder_title">🧠 Your brain is waiting!</string>
    <string name="reminder_body">Don\'t break your streak — solve one more puzzle today.</string>
</resources>
EOF

# ---------- strings.xml (İspanyolca) ----------
mkdir -p "$PROJ/app/src/main/res/values-es"
cat > "$PROJ/app/src/main/res/values-es/strings.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="reminder_channel_name">Recordatorio diario</string>
    <string name="reminder_title">🧠 ¡Tu cerebro te espera!</string>
    <string name="reminder_body">No rompas tu racha — resuelve un rompecabezas más hoy.</string>
</resources>
EOF

# ---------- strings.xml (Arapça) ----------
mkdir -p "$PROJ/app/src/main/res/values-ar"
cat > "$PROJ/app/src/main/res/values-ar/strings.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="reminder_channel_name">تذكير يومي</string>
    <string name="reminder_title">🧠 عقلك في انتظارك!</string>
    <string name="reminder_body">لا تكسر سلسلتك — حل لغزاً آخر اليوم.</string>
</resources>
EOF

# ---------- strings.xml (Rusça) ----------
mkdir -p "$PROJ/app/src/main/res/values-ru"
cat > "$PROJ/app/src/main/res/values-ru/strings.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="reminder_channel_name">Ежедневное напоминание</string>
    <string name="reminder_title">🧠 Твой мозг ждёт!</string>
    <string name="reminder_body">Не теряй серию — реши ещё одну головоломку сегодня.</string>
</resources>
EOF

# ---------- colors.xml ----------
cat > "$PROJ/app/src/main/res/values/colors.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="theme_color">$THEME_COLOR</color>
    <color name="background_color">$BG_COLOR</color>
</resources>
EOF

# ---------- İkon ----------
# Canlı siteden indiriyoruz — repoda binary tutmaya gerek kalmıyor.
# GitHub Actions runner'ında ara sıra görülen geçici ağ kesintilerine
# (ör. "Recv failure: Connection reset by peer") karşı yeniden dener.
echo "==> İkon indiriliyor: $ICON_URL"
curl -fsSL \
  --retry 5 --retry-delay 3 --retry-all-errors \
  --connect-timeout 10 --max-time 30 \
  "$ICON_URL" -o "$PROJ/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

# ---------- MainActivity.java ----------
# WebView + AdMob ödüllü reklam köprüsü + UMP (GDPR/rıza) akışı.
# index.html içindeki "window.AndroidBridge.showRewardedAd()" ve
# "window.AndroidBridge.showPrivacyOptionsForm()" çağrılarını burada karşılıyoruz.
cat > "$PROJ/app/src/main/java/com/mindgap/app/MainActivity.java" << 'JAVAEOF'
package com.mindgap.app;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.AdValue;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.OnPaidEventListener;
import com.google.android.gms.ads.OnUserEarnedRewardListener;
import com.google.android.gms.ads.rewarded.RewardItem;
import com.google.android.gms.ads.rewardedinterstitial.RewardedInterstitialAd;
import com.google.android.gms.ads.rewardedinterstitial.RewardedInterstitialAdLoadCallback;

import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.UserMessagingPlatform;

/**
 * MIND GAP — WebView tabanlı native kabuk.
 *
 * Neden TWA (Trusted Web Activity) yerine bu var:
 * TWA, Chrome Custom Tabs üzerinden çalışır ve JavaScript ile native kod
 * arasında köprü kurmaya izin vermez. Gerçek AdMob ödüllü reklamlarını
 * web tarafından tetikleyebilmek için WebView + addJavascriptInterface
 * köprüsüne ihtiyaç var. Bu geçişin bir yan faydası: WebView zaten
 * hiçbir zaman adres çubuğu göstermez, yani assetlinks.json / Digital
 * Asset Links doğrulamasına artık ihtiyaç yok.
 *
 * UMP (User Messaging Platform) akışı:
 * AdMob'u başlatmadan/reklam yüklemeden önce Google'ın UMP SDK'sı ile
 * kullanıcının rıza durumu kontrol edilir (AB/İngiltere/İsviçre gibi
 * bölgelerde GDPR gereği zorunlu). Rıza gerekiyorsa form otomatik
 * gösterilir; ancak rıza alındıktan/gerekmediği anlaşıldıktan SONRA
 * MobileAds.initialize() çağrılır ve reklam yüklenir.
 */
public class MainActivity extends Activity {

    private WebView webView;
    private RewardedInterstitialAd rewardedAd;
    private boolean isAdCurrentlyShowing = false; // native-taraflı ek güvenlik: JS sinyali ulaşana kadarki
                                                    // kısa pencerede de ikinci bir show() çağrısını engeller
    private boolean adIsLoading = false;
    private boolean isMobileAdsInitialized = false;
    private ConsentInformation consentInformation;
    private String lastAdDebugInfo = "init bekleniyor";

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        hideSystemBars();

        webView = new WebView(this);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        webView.setWebViewClient(new WebViewClient());
        webView.setWebChromeClient(new WebChromeClient());
        webView.addJavascriptInterface(new AndroidBridge(), "AndroidBridge");

        webView.loadUrl(getString(R.string.launch_url));

        requestConsentAndInitAds();

        createReminderNotificationChannel();
        requestNotificationPermissionIfNeeded();
    }

    // ═══════════════════════════════════════════════════════
    // GÜNLÜK "GERİ DÖN" HATIRLATMASI — tamamen cihaz üzerinde, sunucusuz.
    // Kullanıcı uygulamadan çıkınca (onPause) ~24 saat sonrası için bir
    // bildirim planlanır; uygulamayı tekrar açarsa (onResume) o bildirim
    // iptal edilir. Firebase Cloud Functions / ücretli plan / push
    // sunucusu gerektirmez — AlarmManager + BroadcastReceiver yeterli.
    // ═══════════════════════════════════════════════════════
    private static final String REMINDER_CHANNEL_ID = "mindgap_daily_reminder";
    private static final int REMINDER_REQUEST_CODE = 4201;
    private static final long REMINDER_DELAY_MS = 24L * 60 * 60 * 1000; // 24 saat

    private void createReminderNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    REMINDER_CHANNEL_ID,
                    getString(R.string.reminder_channel_name),
                    NotificationManager.IMPORTANCE_DEFAULT);
            NotificationManager nm = getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(channel);
        }
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 9001);
            }
        }
    }

    private PendingIntent reminderPendingIntent() {
        Intent intent = new Intent(this, ReminderReceiver.class);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT
                | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
        return PendingIntent.getBroadcast(this, REMINDER_REQUEST_CODE, intent, flags);
    }

    /** Kullanıcı uygulamadan ayrılırken çağrılır — ertesi gün için hatırlatma planlar. */
    private void scheduleReminder() {
        try {
            AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (am == null) return;
            long triggerAt = System.currentTimeMillis() + REMINDER_DELAY_MS;
            // setAndAllowWhileIdle: Doze modunda bile (yaklaşık olarak) tetiklenir.
            // Tam saniyesinde tetiklenmesi kritik değil — kesin alarm izni
            // (SCHEDULE_EXACT_ALARM) istemeye gerek yok, "yaklaşık yarın" yeterli.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, reminderPendingIntent());
        } catch (Exception e) {
            // Sessizce vazgeç — hatırlatma opsiyonel bir özellik, oyunu asla bozmamalı.
        }
    }

    /** Kullanıcı uygulamayı tekrar açtığında çağrılır — bekleyen hatırlatmayı iptal eder. */
    private void cancelReminder() {
        try {
            AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            if (am != null) am.cancel(reminderPendingIntent());
        } catch (Exception e) {
            // yoksay
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        scheduleReminder();
    }

    @Override
    protected void onResume() {
        super.onResume();
        cancelReminder();
    }

    /** Her açılışta çağrılır: rıza durumunu günceller, gerekiyorsa formu gösterir. */
    private void requestConsentAndInitAds() {
        consentInformation = UserMessagingPlatform.getConsentInformation(this);
        ConsentRequestParameters params = new ConsentRequestParameters.Builder().build();
        lastAdDebugInfo = "rıza bilgisi isteniyor...";

        consentInformation.requestConsentInfoUpdate(
                this,
                params,
                () -> UserMessagingPlatform.loadAndShowConsentFormIfRequired(
                        MainActivity.this,
                        formError -> {
                            if (formError != null) {
                                lastAdDebugInfo = "rıza formu hatası: " + formError.getMessage();
                            } else if (consentInformation.canRequestAds()) {
                                initializeMobileAdsSdk();
                            } else {
                                lastAdDebugInfo = "canRequestAds() false (rıza formu sonrası)";
                            }
                        }),
                requestConsentError -> {
                    // Rıza bilgisi güncellenemedi (ör. ağ hatası). Google'ın resmi
                    // UMP dokümantasyonu bu durumda da canRequestAds() kontrol
                    // edilmesini söylüyor — önceki oturumdan geçerli bir rıza
                    // durumu varsa yine de reklam gösterilebilir. Bu kontrol
                    // olmadan, tek bir ağ hatası o oturumda reklamları TAMAMEN
                    // devre dışı bırakıyordu (asıl hata buydu).
                    lastAdDebugInfo = "consent update hatası " + requestConsentError.getErrorCode()
                            + ": " + requestConsentError.getMessage();
                    if (consentInformation.canRequestAds()) {
                        initializeMobileAdsSdk();
                    }
                });

        // Önceki oturumdan geçerli bir rıza zaten varsa (ikinci ve sonraki
        // açılışlarda genelde böyle), yukarıdaki asenkron güncellemeyi
        // beklemeden hemen reklamları başlat.
        if (consentInformation.canRequestAds()) {
            initializeMobileAdsSdk();
        }
    }

    private void initializeMobileAdsSdk() {
        if (isMobileAdsInitialized) return;
        isMobileAdsInitialized = true;
        lastAdDebugInfo = "Ads SDK başlatılıyor...";
        MobileAds.initialize(this, initializationStatus -> {
            lastAdDebugInfo = "Ads SDK başlatıldı, reklam yükleniyor...";
            evalJs("window.onAdsSdkInitialized && window.onAdsSdkInitialized()");
        });
        loadRewardedAd();
    }

    private void loadRewardedAd() {
        if (adIsLoading || rewardedAd != null) return;
        adIsLoading = true;
        AdRequest adRequest = new AdRequest.Builder().build();
        RewardedInterstitialAd.load(this, getString(R.string.admob_rewarded_ad_unit_id), adRequest,
                new RewardedInterstitialAdLoadCallback() {
                    @Override
                    public void onAdLoaded(RewardedInterstitialAd ad) {
                        rewardedAd = ad;
                        adIsLoading = false;
                        lastAdDebugInfo = "reklam yüklendi, hazır";

                        // ÖNEMLİ: AdMob geliri, Google Ads'te "değer bazlı" teklif
                        // stratejisi (Dönüşüm değerini en üst düzeye çıkar) kurabilmek
                        // için gerekli. Native Firebase Analytics SDK'sı (ve
                        // google-services.json) eklemek yerine, zaten çalışan JS/WebView
                        // katmanındaki Firebase Analytics örneğine köprü kuruyoruz —
                        // aynı altyapı, ekstra bağımlılık/config dosyası gerekmiyor.
                        ad.setOnPaidEventListener(new OnPaidEventListener() {
                            @Override
                            public void onPaidEvent(AdValue adValue) {
                                double valueInCurrencyUnits = adValue.getValueMicros() / 1000000.0;
                                String currencyCode = adValue.getCurrencyCode();
                                String adUnitId = getString(R.string.admob_rewarded_ad_unit_id);
                                evalJs("window.onAdPaidEvent && window.onAdPaidEvent("
                                        + valueInCurrencyUnits + "," + jsStr(currencyCode) + "," + jsStr(adUnitId) + ")");
                            }
                        });
                    }

                    @Override
                    public void onAdFailedToLoad(LoadAdError error) {
                        rewardedAd = null;
                        adIsLoading = false;
                        lastAdDebugInfo = "load hata " + error.getCode() + ": " + error.getMessage();
                        // Sessizce vazgeç; bir sonraki showRewardedAd() çağrısı yeniden dener.
                    }
                });
    }

    private void evalJs(final String js) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                webView.evaluateJavascript(js, null);
            }
        });
    }

    /** Bir Java string'ini güvenli bir JS string literal'ine çevirir (tek tırnaklarla). */
    private static String jsStr(String s) {
        if (s == null) s = "";
        String escaped = s.replace("\\", "\\\\").replace("'", "\\'")
                .replace("\n", " ").replace("\r", " ");
        return "'" + escaped + "'";
    }

    /** index.html içinden "AndroidBridge.xxx()" ile çağrılan native köprü. */
    private class AndroidBridge {

        @JavascriptInterface
        public void showRewardedAd() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if (isAdCurrentlyShowing) {
                        // Zaten bir reklam ekranda — JS tarafının 2sn'lik yeniden deneme
                        // döngüsü henüz "showing" sinyalini almamış olabilir; burada da
                        // sessizce vazgeçerek ikinci bir reklamın kuyruğa girmesini engelle.
                        return;
                    }
                    if (!isMobileAdsInitialized) {
                        // Rıza henüz alınmadı/tamamlanmadı — reklam sistemi hazır değil.
                        evalJs("window.onRewardedAdNotReady && window.onRewardedAdNotReady(" 
                                + jsStr("Ads SDK henüz başlatılmadı (rıza/UMP bekleniyor)") + ")");
                        return;
                    }
                    if (rewardedAd == null) {
                        evalJs("window.onRewardedAdNotReady && window.onRewardedAdNotReady("
                                + jsStr(lastAdDebugInfo) + ")");
                        loadRewardedAd();
                        return;
                    }

                    // ÖNEMLİ: ödülün kazanılıp kazanılmadığını burada sadece BİR BAYRAKLA
                    // işaretliyoruz. JS'e haber vermeyi (window.onRewardEarned) reklam
                    // GERÇEKTEN kapanana kadar (onAdDismissedFullScreenContent) ERTELİYORUZ.
                    // Önceki sürümde bildirim onUserEarnedReward() içinde yapılıyordu — bu
                    // callback reklam HÂLÂ TAM EKRAN AÇIKKEN (genellikle izlemenin belirli
                    // bir yüzdesinde) tetiklenir. Bunun sonucunda JS tarafındaki çözüm
                    // animasyonu reklam hâlâ ekranı kaplarken arka planda çalışıp bitiyor,
                    // kullanıcı reklamdan döndüğünde bulmacayı "zaten dolu" görüyordu.
                    final boolean[] rewardEarned = {false};

                    rewardedAd.setFullScreenContentCallback(new FullScreenContentCallback() {
                        @Override
                        public void onAdShowedFullScreenContent() {
                            isAdCurrentlyShowing = true;
                            // Reklam artık GERÇEKTEN ekranda görünüyor — JS'e hemen haber ver ki
                            // 2 saniyede bir tekrar deneyen döngüyü DURDURSUN. Aksi hâlde ilk
                            // reklamın yüklenip görünmesi 2 saniyeden uzun sürerse, JS tarafı
                            // showRewardedAd()'ı BİR DAHA çağırıyor ve arka arkaya İKİNCİ bir
                            // reklam kuyruğa giriyordu ("2 reklam çıkıyor" şikayetinin kök nedeni).
                            evalJs("window.onRewardedAdShowing && window.onRewardedAdShowing()");
                        }

                        @Override
                        public void onAdDismissedFullScreenContent() {
                            isAdCurrentlyShowing = false;
                            rewardedAd = null;
                            loadRewardedAd(); // Bir sonraki gösterim için önceden yükle
                            if (rewardEarned[0]) {
                                // Reklam artık GERÇEKTEN kapandı — JS'e ancak ŞİMDİ haber ver.
                                evalJs("window.onRewardEarned && window.onRewardEarned()");
                            } else {
                                // Kullanıcı ödülü kazanmadan reklamı erken kapattı. JS artık
                                // (onAdShowedFullScreenContent sinyaliyle) 10sn'lik zaman aşımı
                                // güvenlik ağını iptal ettiği için, burada JS'e haber
                                // VERMEZSEK "Çöz" butonu sonsuza kadar kilitli kalır.
                                evalJs("window.onRewardedAdClosedWithoutReward && window.onRewardedAdClosedWithoutReward()");
                            }
                        }

                        @Override
                        public void onAdFailedToShowFullScreenContent(AdError adError) {
                            isAdCurrentlyShowing = false;
                            rewardedAd = null;
                            loadRewardedAd();
                            evalJs("window.onRewardedAdFailed && window.onRewardedAdFailed("
                                    + jsStr("show hata: " + adError.getMessage()) + ")");
                        }
                    });

                    rewardedAd.show(MainActivity.this, new OnUserEarnedRewardListener() {
                        @Override
                        public void onUserEarnedReward(RewardItem rewardItem) {
                            // Sadece bayrağı işaretle — JS'e burada HABER VERME (yukarıdaki nota bakın).
                            rewardEarned[0] = true;
                        }
                    });
                }
            });
        }

        @JavascriptInterface
        public boolean isRewardedAdReady() {
            return isMobileAdsInitialized && rewardedAd != null;
        }

        /** Teşhis amaçlı: reklam sisteminin şu anki durumunu okunabilir metin olarak döner. */
        @JavascriptInterface
        public String getAdDebugInfo() {
            return "init=" + isMobileAdsInitialized + " | ready=" + (rewardedAd != null)
                    + " | " + lastAdDebugInfo;
        }

        /** Kullanıcı daha sonra GDPR rıza tercihini değiştirmek isterse çağrılır. */
        @JavascriptInterface
        public void showPrivacyOptionsForm() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    UserMessagingPlatform.showPrivacyOptionsForm(
                            MainActivity.this,
                            formError -> { /* form kapandı, ekstra işlem gerekmiyor */ });
                }
            });
        }

        /** Ayarlar menüsünde "Gizlilik Tercihleri" butonunun gösterilip gösterilmeyeceği. */
        @JavascriptInterface
        public boolean isPrivacyOptionsRequired() {
            return consentInformation != null &&
                    consentInformation.getPrivacyOptionsRequirementStatus()
                            == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED;
        }

        /**
         * Play Store gibi harici bir bağlantıyı GÜVENLİ şekilde açar — Android'in
         * kendi Intent sistemini (ACTION_VIEW) doğrudan kullanır. WebView'a "şu
         * adrese git" demek YERİNE, işletim sistemine "bu URL'yi aç" diyoruz.
         * ÖNEMLİ: Play Store'un web sayfası, WebView'dan geldiğini anlayınca
         * kendi sunucusunda "intent://..." şemasına yönlendirir — çıplak bir
         * WebView bileşeni bu şemayı TANIMAZ ve donmuş bir hata sayfasında
         * takılı kalır (kullanıcı uygulamayı kapatmak zorunda kalır). Bu metot
         * WebView'ı hiç devreye sokmadığı için o soruna hiç girmiyor.
         */
        @JavascriptInterface
        public void openExternalUrl(final String url) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    try {
                        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                    } catch (Exception e) {
                        // Sessizce vazgeç — bu opsiyonel bir kolaylık, oyunu asla bozmamalı.
                    }
                }
            });
        }
    }

    private void hideSystemBars() {
        View decorView = getWindow().getDecorView();
        decorView.setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}

/**
 * AlarmManager tarafından ~24 saat sonra tetiklenir (kullanıcı uygulamadan
 * ayrılıp geri dönmediyse). Basit, sunucusuz "geri dön" bildirimi gösterir.
 */
class ReminderReceiver extends android.content.BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        try {
            Intent launchIntent = new Intent(context, MainActivity.class);
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT
                    | (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ? PendingIntent.FLAG_IMMUTABLE : 0);
            PendingIntent contentIntent = PendingIntent.getActivity(context, 4202, launchIntent, flags);

            android.app.Notification.Builder builder;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder = new android.app.Notification.Builder(context, "mindgap_daily_reminder");
            } else {
                builder = new android.app.Notification.Builder(context);
            }
            builder.setContentTitle(context.getString(context.getResources()
                            .getIdentifier("reminder_title", "string", context.getPackageName())))
                    .setContentText(context.getString(context.getResources()
                            .getIdentifier("reminder_body", "string", context.getPackageName())))
                    .setSmallIcon(context.getApplicationInfo().icon)
                    .setAutoCancel(true)
                    .setContentIntent(contentIntent);

            NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) nm.notify(4203, builder.build());
        } catch (Exception e) {
            // Sessizce vazgeç — hatırlatma opsiyonel, hiçbir koşulda crash'e yol açmamalı.
        }
    }
}
JAVAEOF

echo "==> Oluşturulan dosyalar:"
find "$PROJ" -type f | sort

echo "==> Android projesi hazır."
