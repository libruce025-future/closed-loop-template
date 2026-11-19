import { cp, mkdir, rm, writeFile } from 'node:fs/promises';

const sha = process.env.SHA || 'dev';

await rm('dist', { recursive: true, force: true });
await mkdir('dist', { recursive: true });
await cp('app', 'dist', { recursive: true });
await writeFile(
  'dist/version.json',
  `${JSON.stringify({ sha, builtAt: new Date().toISOString() }, null, 2)}\n`,
);

console.log(`built dist/ sha=${sha}`);
