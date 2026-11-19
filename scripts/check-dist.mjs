import { access, readFile } from 'node:fs/promises';

const sha = process.env.SHA || 'dev';
const required = [
  'dist/index.html',
  'dist/version.json',
  'dist/src/main.js',
  'dist/src/styles.css',
];

for (const file of required) {
  await access(file);
}

const version = JSON.parse(await readFile('dist/version.json', 'utf8'));
if (version.sha !== sha) {
  throw new Error(`version.json sha=${version.sha} does not match expected ${sha}`);
}
if (!/^(dev|[0-9a-f]{7,40})$/.test(version.sha)) {
  throw new Error(`version.json sha is not a commit sha: ${version.sha}`);
}

const html = await readFile('dist/index.html', 'utf8');
if (!html.includes('/src/main.js')) {
  throw new Error('dist/index.html does not reference /src/main.js');
}

console.log(`dist ok: sha=${version.sha}`);
