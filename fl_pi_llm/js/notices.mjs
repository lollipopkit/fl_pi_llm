// Writes THIRD_PARTY_NOTICES.md from the bundle's metafile: the licence of
// every package that has code in `rust/js/fl_pi_llm.js`, and nothing else.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const meta = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const roots = new Set();
for (const input of Object.keys(meta.inputs)) {
  const m = input.match(/^(.*node_modules\/(?:@[^/]+\/)?[^/]+)/);
  if (m) roots.add(m[1]);
}

const out = ['# Third-party notices', '', 'Code from these packages is bundled into `rust/js/fl_pi_llm.js`.', ''];
for (const root of [...roots].sort((a, b) => a.split('node_modules/').pop().localeCompare(b.split('node_modules/').pop()))) {
  const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
  const license = typeof pkg.license === 'string' ? pkg.license : pkg.license?.type ?? 'UNKNOWN';
  out.push(`## ${pkg.name}@${pkg.version}`, '', `License: ${license}`, '');
  const file = readdirSync(root).find((f) => /^(licen[cs]e|copying)(\.|$)/i.test(f));
  if (file) out.push('```', readFileSync(join(root, file), 'utf8').trim(), '```', '');
}
writeFileSync(new URL('../THIRD_PARTY_NOTICES.md', import.meta.url), out.join('\n'));
console.log(`${roots.size} packages`);
