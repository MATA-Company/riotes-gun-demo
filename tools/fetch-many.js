const https = require('https');
const fs = require('fs');
const path = require('path');

const manifest = process.argv[2];
const root = process.argv[3];

function download(url, out, depth = 0) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { 'User-Agent': 'dsh-rojo-sync' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && depth < 5) {
          res.resume();
          return download(res.headers.location, out, depth + 1).then(resolve, reject);
        }
        if (res.statusCode !== 200) {
          res.resume();
          return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          fs.mkdirSync(path.dirname(out), { recursive: true });
          fs.writeFileSync(out, Buffer.concat(chunks));
          resolve({ out, bytes: Buffer.concat(chunks).length });
        });
      })
      .on('error', reject);
  });
}

(async () => {
  const entries = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  let total = 0;
  for (const entry of entries) {
    const out = path.join(root, entry.out);
    try {
      const result = await download(entry.url, out);
      total += result.bytes;
      console.log(`ok   ${entry.out} (${result.bytes} bytes)`);
    } catch (error) {
      console.log(`FAIL ${entry.out}: ${error.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`total ${total} bytes`);
})();
