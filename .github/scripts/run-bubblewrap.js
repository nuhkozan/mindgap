#!/usr/bin/env node
/** * Bubblewrap CLI'yi gerçek bir pseudo-terminal (PTY) üzerinden çalıştırıp, * sorduğu sorulara çıktıyı canlı izleyerek doğru cevabı gönderir. * * NEDEN GEREKLİ: `bubblewrap init`/`build` komutları interaktif bir prompt * kütüphanesi (muhtemelen inquirer/enquirer) kullanıyor. `yes "n" | cmd` gibi * pipe'lar TTY olmadığından bu kütüphaneler bazen soruları yanlış sırayla * okuyor, aynı soruyu tekrar tekrar soruyor ya da varsayılan cevabı (Yes) * kabul ediyor. Gerçek bir PTY vermek, komutun normal bir terminalde * çalıştığını sanmasını sağlar ve bu tutarsızlığı ortadan kaldırır. * * Kullanım: node run-bubblewrap.js "<komut ve argümanlar>" [cwd] * Örnek: node run-bubblewrap.js "bubblewrap init --manifest=... --directory=./twa-project" */
const pty = require("node-pty");
const path = require("path");

const fullCommand = process.argv[2];
const cwd = process.argv[3] || process.cwd();

if (!fullCommand) {
  console.error('Kullanım: node run-bubblewrap.js "<komut>" [cwd]');
  process.exit(1);
}

// Komutu shell üzerinden çalıştırıyoruz (env değişkenleri, PATH vs. doğru çözülsün diye)
const shell = "/bin/bash";
const args = ["-c", fullCommand];

const ptyProcess = pty.spawn(shell, args, {
  name: "xterm-color",
  cols: 120,
  rows: 30,
  cwd: cwd,
  env: process.env,
});

let outputBuffer = "";
let finished = false;

// Bilinen soru kalıpları -> gönderilecek cevap (regex sırayla denenir)
// ÖNEMLİ: cevaplar Enter tuşuyla (\r) gönderilir, PTY'de \n değil \r kullanılır.
const RULES = [
  // JDK/SDK otomatik kurulum soruları -> Hayır (zaten kurulu, biz sağlıyoruz)
  { pattern: /install the JDK/i, answer: "n\r" },
  { pattern: /install.*Android SDK/i, answer: "n\r" },
  {
    pattern: /Path to your existing JDK/i,
    answer: (process.env.JAVA_HOME || "") + "\r",
  },
  {
    pattern: /Path to your existing Android SDK/i,
    answer: (process.env.ANDROID_HOME || "") + "\r",
  },

  // Checksum / proje yeniden oluşturma sorusu -> Hayır, mevcut projeyle devam et
  { pattern: /regenerate your project/i, answer: "n\r" },
  { pattern: /checksum/i, answer: "n\r" },

  // Genel onay soruları (Y/n) -> varsayılanı kabul et (Enter)
  { pattern: /\(Y\/n\)\s*$/i, answer: "\r" },
  { pattern: /\(y\/N\)\s*$/i, answer: "n\r" },

  // Genel "Enter" ile devam et kalıpları
  { pattern: /Press.*to continue/i, answer: "\r" },
];

// Aynı soruya kısa sürede tekrar cevap vermemek için basit bir "son cevap zamanı" takibi
let lastAnswerTime = 0;
const MIN_GAP_MS = 300;

ptyProcess.onData((data) => {
  process.stdout.write(data); // gerçek zamanlı log için GitHub Actions çıktısına da yazdır
  outputBuffer += data;

  // Sadece son birkaç satırı kontrol et (performans + eski eşleşmeleri tekrar tetiklememek için)
  const tail = outputBuffer.slice(-400);
  const now = Date.now();

  if (now - lastAnswerTime < MIN_GAP_MS) return;

  for (const rule of RULES) {
    if (rule.pattern.test(tail)) {
      const answer =
        typeof rule.answer === "function" ? rule.answer() : rule.answer;
      ptyProcess.write(answer);
      lastAnswerTime = now;
      outputBuffer = ""; // eşleşen kısmı temizle, tekrar tetiklenmesin
      break;
    }
  }
});

ptyProcess.onExit(({ exitCode }) => {
  finished = true;
  console.log(`\n---- Komut bitti, exit code: ${exitCode} ----`);
  process.exit(exitCode);
});

// Güvenlik ağı: 10 dakika içinde bitmezse zorla sonlandır
setTimeout(() => {
  if (!finished) {
    console.error(
      "\n---- ZAMAN AŞIMI: komut 10 dakikada bitmedi, sonlandırılıyor ----"
    );
    ptyProcess.kill();
    process.exit(1);
  }
}, 10 * 60 * 1000);
