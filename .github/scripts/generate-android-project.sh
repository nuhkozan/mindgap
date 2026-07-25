#!/usr/bin/env bash
# ============================================================================
# MIND GAP — TWA (Trusted Web Activity) Android projesi üretici
#
# NEDEN BU SCRIPT VAR:
# Bubblewrap CLI'nin `init` komutu CI ortamında interaktif sorular sorup
# takılıyor (GoogleChromeLabs/bubblewrap#806 — hâlâ açık bir hata).
# Bubblewrap'in ürettiği şey aslında STANDART bir Android Gradle projesi.
# Bu script o projeyi doğrudan üretiyor; sonrasında sadece Gradle çalışıyor
# ve Gradle hiçbir soru sormuyor. Böylece build %100 deterministik oluyor.
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

PROJ="android-project"
rm -rf "$PROJ"
mkdir -p "$PROJ/app/src/main/res/values"
mkdir -p "$PROJ/app/src/main/res/mipmap-xxxhdpi"
mkdir -p "$PROJ/app/src/main/res/drawable"

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
        minSdk 21
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
    implementation 'com.google.androidbrowserhelper:androidbrowserhelper:2.5.0'
}
EOF

# ---------- AndroidManifest.xml ----------
cat > "$PROJ/app/src/main/AndroidManifest.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true">

        <meta-data
            android:name="asset_statements"
            android:resource="@string/asset_statements" />

        <activity
            android:name="com.google.androidbrowserhelper.trusted.LauncherActivity"
            android:exported="true"
            android:label="@string/app_name">

            <meta-data
                android:name="android.support.customtabs.trusted.DEFAULT_URL"
                android:value="@string/launch_url" />

            <meta-data
                android:name="android.support.customtabs.trusted.STATUS_BAR_COLOR"
                android:resource="@color/theme_color" />

            <meta-data
                android:name="android.support.customtabs.trusted.NAVIGATION_BAR_COLOR"
                android:resource="@color/theme_color" />

            <meta-data
                android:name="android.support.customtabs.trusted.SPLASH_IMAGE_DRAWABLE"
                android:resource="@drawable/splash" />

            <meta-data
                android:name="android.support.customtabs.trusted.SPLASH_SCREEN_BACKGROUND_COLOR"
                android:resource="@color/background_color" />

            <meta-data
                android:name="androidx.browser.trusted.SCREEN_ORIENTATION"
                android:value="portrait" />

            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>

            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data
                    android:scheme="https"
                    android:host="$HOST"
                    android:pathPrefix="$PATH_PREFIX" />
            </intent-filter>
        </activity>

        <activity
            android:name="com.google.androidbrowserhelper.trusted.FocusActivity"
            android:exported="false" />

        <activity
            android:name="com.google.androidbrowserhelper.trusted.WebViewFallbackActivity"
            android:configChanges="orientation|screenSize|screenLayout|keyboard|keyboardHidden"
            android:exported="false"
            android:label="@string/app_name" />

        <service
            android:name="com.google.androidbrowserhelper.trusted.DelegationService"
            android:exported="true">
            <intent-filter>
                <action android:name="android.support.customtabs.trusted.TRUSTED_WEB_ACTIVITY_SERVICE" />
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
        </service>
    </application>
</manifest>
EOF

# ---------- strings.xml ----------
# asset_statements: TWA'nın adres çubuğunu gizlemesi için domain doğrulaması.
# Not: Bunun çalışması için siteye .well-known/assetlinks.json da eklenmeli.
cat > "$PROJ/app/src/main/res/values/strings.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">$APP_NAME</string>
    <string name="launch_url">$LAUNCH_URL</string>
    <string name="asset_statements">[{ \\"relation\\": [\\"delegate_permission/common.handle_all_urls\\"], \\"target\\": { \\"namespace\\": \\"web\\", \\"site\\": \\"https://$HOST\\" }}]</string>
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

# ---------- İkon ve splash görselleri ----------
# Canlı siteden indiriyoruz — repoda binary tutmaya gerek kalmıyor.
echo "==> İkon indiriliyor: $ICON_URL"
curl -fsSL "$ICON_URL" -o "$PROJ/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
cp "$PROJ/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" "$PROJ/app/src/main/res/drawable/splash.png"

echo "==> Oluşturulan dosyalar:"
find "$PROJ" -type f | sort

echo "==> Android projesi hazır."
