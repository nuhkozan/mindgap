#!/usr/bin/env node
/**
 * Bubblewrap CLI'yi gerçek bir pseudo-terminal (PTY) üzerinden çalıştırıp,
 * sorduğu sorulara çıktıyı canlı izleyerek doğru cevabı gönderir.
 *
 * Kullanım: node run-bubblewrap.js "<komut ve argümanlar>" [cwd]
 */
const pty = require('node-pty');

const fullCommand = process.argv[2];
const cwd = process.argv[3] || process.cwd();

if (!fullCommand) {
  console.error('Kullanım: node run-bubblewrap.js "<komut>" [cwd]');
  process.exit(1);
}

// JDK/SDK yolları erkenden kontrol edilsin — boşsa hemen net bir hata verelim,
// sessizce boş cevap gönderip soruyu sonsuz döngüye sokmasın.
const JAVA_HOME = process.env.JAVA_HOME || '';
const ANDROID_HOME = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT || '';
console.log(`[debug] JAVA_HOME=${JAVA_HOME}`);
console.log(`[debug] ANDROID_HOME=${ANDROID_HOME}`);

const shell = '/bin/bash';
const args = ['-c', fullCommand];

const ptyProcess = pty.spawn(shell, args, {
  name: 'xterm-color',
  cols: 200,
  rows: 50,
  cwd: cwd,
  env: process.env,
});

let outputBuffer = '';
let finished = false;
let lastAnswerTime = 0;
const MIN_GAP_MS = 500;

// Bilinen soru kalıpları -> gönderilecek cevap. Sırayla denenir, ilk eşleşen kazanır.
const RULES = [
  { name: 'install-jdk', pattern: /install the JDK/i, answer: () => 'n\r' },
  { name: 'install-sdk', pattern: /install.*Android SDK/i, answer: () => 'n\r' },
  {
    name: 'jdk-path',
    pattern: /Path to your existing JDK/i,
    answer: () => {
      if (!JAVA_HOME) {
        console.error('[HATA] JAVA_HOME boş, JDK yolu sorusuna cevap verilemiyor!');
      }
      return JAVA_HOME + '\r';
    },
  },
  {
    name: 'sdk-path',
    pattern: /Path to your existing Android SDK/i,
    answer: () => {
      if (!ANDROID_HOME) {
        console.error('[HATA] ANDROID_HOME boş, SDK yolu sorusuna cevap verilemiyor!');
      }
      return ANDROID_HOME + '\r';
    },
  },
  { name: 'regenerate', pattern: /regenerate your project/i, answer: () => 'n\r' },
  { name: 'checksum', pattern: /checksum/i, answer: () => 'n\r' },
  { name: 'yn-default', pattern: /\(Y\/n\)\s*$/i, answer: () => '\r' },
  { name: 'ny-default', pattern: /\(y\/N\)\s*$/i, answer: () => 'n\r' },
  { name: 'press-continue', pattern: /Press.*to continue/i, answer: () => '\r' },
];

// Her kural için son ne zaman tetiklendiğini takip ediyoruz — aynı kural
// çok kısa sürede İKİ KEZ tetiklenirse (muhtemel döngü), zorla durduruyoruz.
const ruleLastFired = {};
const REPEAT_LIMIT_MS = 2000;
let sameRuleRepeatCount = 0;

ptyProcess.onData((data) => {
  process.stdout.write(data);
  outputBuffer += data;
  if (outputBuffer.length > 5000) {
    outputBuffer = outputBuffer.slice(-2000); // bellek şişmesin
  }

  const now = Date.now();
  if (now - lastAnswerTime < MIN_GAP_MS) return;

  const tail = outputBuffer.slice(-600);

  for (const rule of RULES) {
    if (rule.pattern.test(tail)) {
      const lastFired = ruleLastFired[rule.name] || 0;
      if (now - lastFired < REPEAT_LIMIT_MS) {
        sameRuleRepeatCount++;
        console.error(`[uyarı] Kural "${rule.name}" çok kısa sürede tekrar tetiklendi (${sameRuleRepeatCount}. kez) — muhtemel döngü.`);
        if (sameRuleRepeatCount >= 4) {
          console.error(`[HATA] Aynı soru 4+ kez tekrarlandı, sonsuz döngü tespit edildi. Sonlandırılıyor.`);
          ptyProcess.kill();
          process.exit(1);
        }
      } else {
        sameRuleRepeatCount = 0;
      }
      ruleLastFired[rule.name] = now;

      const answer = rule.answer();
      console.log(`\n[eşleşti] Kural: "${rule.name}" -> gönderilen: ${JSON.stringify(answer)}`);
      ptyProcess.write(answer);
      lastAnswerTime = now;
      outputBuffer = '';
      break;
    }
  }
});

ptyProcess.onExit(({ exitCode }) => {
  finished = true;
  console.log(`\n---- Komut bitti, exit code: ${exitCode} ----`);
  process.exit(exitCode);
});

setTimeout(() => {
  if (!finished) {
    console.error('\n---- ZAMAN AŞIMI: komut belirlenen sürede bitmedi, sonlandırılıyor ----');
    ptyProcess.kill();
    process.exit(1);
  }
}, 8 * 60 * 1000);
