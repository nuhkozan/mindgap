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
VERSION_NAME="1.0.0"
VERSION_CODE="1"
ICON_URL="https://nuhkozan.github.io/mindgap/icons/icon-512.png"

# ── AdMob ──
# ⚠️ Şu an TEST ID'leri kullanılıyor (Google'ın resmi test reklam birimleri).
# İlk build ve test başarılı olduktan sonra bunları gerçek ID'lerinle değiştir:
#   ADMOB_APP_ID              -> ca-app-pub-5226177276862447~4336706536
#   ADMOB_REWARDED_AD_UNIT_ID -> ca-app-pub-5226177276862447/2037846257
ADMOB_APP_ID="ca-app-pub-3940256099942544~3347511713"
ADMOB_REWARDED_AD_UNIT_ID="ca-app-pub-3940256099942544/5224354917"

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
    id 'com.android.application' version '8.1.4' apply false
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
    compileSdk 34

    defaultConfig {
        applicationId "$PACKAGE_ID"
        minSdk 23
        targetSdk 34
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
}
EOF

# ---------- AndroidManifest.xml ----------
cat > "$PROJ/app/src/main/AndroidManifest.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

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

# ---------- strings.xml ----------
cat > "$PROJ/app/src/main/res/values/strings.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">$APP_NAME</string>
    <string name="launch_url">$LAUNCH_URL</string>
    <string name="admob_rewarded_ad_unit_id">$ADMOB_REWARDED_AD_UNIT_ID</string>
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
echo "==> İkon indiriliyor: $ICON_URL"
curl -fsSL "$ICON_URL" -o "$PROJ/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

# ---------- MainActivity.java ----------
# WebView + AdMob ödüllü reklam köprüsü. index.html içindeki
# "window.AndroidBridge.showRewardedAd()" çağrısını burada karşılıyoruz.
cat > "$PROJ/app/src/main/java/com/mindgap/app/MainActivity.java" << 'JAVAEOF'
package com.mindgap.app;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.OnUserEarnedRewardListener;
import com.google.android.gms.ads.initialization.InitializationStatus;
import com.google.android.gms.ads.initialization.OnInitializationCompleteListener;
import com.google.android.gms.ads.rewarded.RewardItem;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;

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
 */
public class MainActivity extends Activity {

    private WebView webView;
    private RewardedAd rewardedAd;
    private boolean adIsLoading = false;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        MobileAds.initialize(this, new OnInitializationCompleteListener() {
            @Override
            public void onInitializationComplete(InitializationStatus initializationStatus) {
                loadRewardedAd();
            }
        });

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
    }

    private void loadRewardedAd() {
        if (adIsLoading || rewardedAd != null) return;
        adIsLoading = true;
        AdRequest adRequest = new AdRequest.Builder().build();
        RewardedAd.load(this, getString(R.string.admob_rewarded_ad_unit_id), adRequest,
                new RewardedAdLoadCallback() {
                    @Override
                    public void onAdLoaded(RewardedAd ad) {
                        rewardedAd = ad;
                        adIsLoading = false;
                    }

                    @Override
                    public void onAdFailedToLoad(LoadAdError error) {
                        rewardedAd = null;
                        adIsLoading = false;
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

    /** index.html içinden "AndroidBridge.xxx()" ile çağrılan native köprü. */
    private class AndroidBridge {

        @JavascriptInterface
        public void showRewardedAd() {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    if (rewardedAd == null) {
                        evalJs("window.onRewardedAdNotReady && window.onRewardedAdNotReady()");
                        loadRewardedAd();
                        return;
                    }

                    rewardedAd.setFullScreenContentCallback(new FullScreenContentCallback() {
                        @Override
                        public void onAdDismissedFullScreenContent() {
                            rewardedAd = null;
                            loadRewardedAd(); // Bir sonraki gösterim için önceden yükle
                        }

                        @Override
                        public void onAdFailedToShowFullScreenContent(AdError adError) {
                            rewardedAd = null;
                            loadRewardedAd();
                            evalJs("window.onRewardedAdFailed && window.onRewardedAdFailed()");
                        }
                    });

                    rewardedAd.show(MainActivity.this, new OnUserEarnedRewardListener() {
                        @Override
                        public void onUserEarnedReward(RewardItem rewardItem) {
                            evalJs("window.onRewardEarned && window.onRewardEarned()");
                        }
                    });
                }
            });
        }

        @JavascriptInterface
        public boolean isRewardedAdReady() {
            return rewardedAd != null;
        }
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
JAVAEOF

echo "==> Oluşturulan dosyalar:"
find "$PROJ" -type f | sort

echo "==> Android projesi hazır."
