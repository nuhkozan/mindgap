#!/usr/bin/env node
/** * Bubblewrap CLI'yi gerçek bir pseudo-terminal (PTY) üzerinden çalıştırıp, * sorduğu sorulara çıktıyı canlı izleyerek doğru cevabı gönderir. * * Kullanım: node run-bubblewrap.js "<komut ve argümanlar>" [cwd] */
const pty = require("node-pty");

const fullCommand = process.argv[2];
const cwd = process.argv[3] || process.cwd();

if (!fullCommand) {
  console.error('Kullanım: node run-bubblewrap.js "<komut>" [cwd]');
  process.exit(1);
}

const JAVA_HOME = process.env.JAVA_HOME || "";
const ANDROID_HOME =
  process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT || "";
console.log(`[debug] JAVA_HOME=${JAVA_HOME}`);
console.log(`[debug] ANDROID_HOME=${ANDROID_HOME}`);

const shell = "/bin/bash";
const args = ["-c", fullCommand];

const ptyProcess = pty.spawn(shell, args, {
  name: "xterm-color",
  cols: 200,
  rows: 50,
  cwd: cwd,
  env: process.env,
});

let outputBuffer = "";
let finished = false;

const RULES = [
  { name: "install-jdk", pattern: /install the JDK/i, answer: () => "n\r" },
  {
    name: "install-sdk",
    pattern: /install.*Android SDK/i,
    answer: () => "n\r",
  },
  {
    name: "jdk-path",
    pattern: /Path to your existing JDK/i,
    answer: () => {
      if (!JAVA_HOME) console.error("[HATA] JAVA_HOME boş!");
      return JAVA_HOME + "\r";
    },
  },
  {
    name: "sdk-path",
    pattern: /Path to your existing Android SDK/i,
    answer: () => {
      if (!ANDROID_HOME) console.error("[HATA] ANDROID_HOME boş!");
      return ANDROID_HOME + "\r";
    },
  },
  {
    name: "regenerate",
    pattern: /regenerate your project/i,
    answer: () => "n\r",
  },
  { name: "checksum", pattern: /checksum/i, answer: () => "n\r" },
  { name: "yn-default", pattern: /\(Y\/n\)\s*$/i, answer: () => "\r" },
  { name: "ny-default", pattern: /\(y\/N\)\s*$/i, answer: () => "n\r" },
  {
    name: "press-continue",
    pattern: /Press.*to continue/i,
    answer: () => "\r",
  },
];

// Her kural için: en son ne zaman tetiklendi VE o tetikleme sırasında
// buffer'da ne vardı (aynı soru metni tekrar görülürse yanıt vermeyiz,
// gerçekten farklı/yeni bir soruysa veririz).
const ruleState = {}; // { [ruleName]: { lastFiredAt, lastMatchedText } }
let sameRuleRepeatCount = 0;

function checkAndAnswer() {
  const tail = outputBuffer.slice(-600);
  const now = Date.now();

  for (const rule of RULES) {
    const match = tail.match(rule.pattern);
    if (!match) continue;

    const matchedText = match[0];
    const state = ruleState[rule.name];

    // Aynı kural, aynı eşleşen metinle, çok kısa sürede (1sn) tekrar geldiyse
    // muhtemelen aynı soruyu tekrar görüyoruz (henüz cevap işlenmedi) — atla.
    if (
      state &&
      state.lastMatchedText === matchedText &&
      now - state.lastFiredAt < 1000
    ) {
      continue;
    }

    // Genel döngü koruması: aynı kural 6 saniye içinde 5+ kez tetiklendiyse dur.
    if (state && now - state.firstFiredAt < 6000) {
      state.count = (state.count || 1) + 1;
      if (state.count >= 5) {
        console.error(
          `[HATA] Kural "${rule.name}" 6sn içinde ${state.count} kez tetiklendi — döngü. Durduruluyor.`
        );
        ptyProcess.kill();
        process.exit(1);
      }
    } else {
      ruleState[rule.name] = { firstFiredAt: now, count: 1 };
    }

    ruleState[rule.name].lastFiredAt = now;
    ruleState[rule.name].lastMatchedText = matchedText;

    const answer = rule.answer();
    console.log(
      `\n[eşleşti] Kural: "${rule.name}" -> gönderilen: ${JSON.stringify( answer )}`
    );
    ptyProcess.write(answer);
    outputBuffer = "";
    return true;
  }
  return false;
}

ptyProcess.onData((data) => {
  process.stdout.write(data);
  outputBuffer += data;
  if (outputBuffer.length > 5000) {
    outputBuffer = outputBuffer.slice(-2000);
  }
  checkAndAnswer();
});

ptyProcess.onExit(({ exitCode }) => {
  finished = true;
  console.log(`\n---- Komut bitti, exit code: ${exitCode} ----`);
  process.exit(exitCode);
});

setTimeout(() => {
  if (!finished) {
    console.error(
      "\n---- ZAMAN AŞIMI: komut belirlenen sürede bitmedi, sonlandırılıyor ----"
    );
    ptyProcess.kill();
    process.exit(1);
  }
}, 8 * 60 * 1000);
