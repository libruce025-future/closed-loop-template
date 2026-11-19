import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve } from 'node:path';

const rootDir = resolve(process.env.DIST_DIR || 'dist');
const port = Number(process.env.PORT || 3000);

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
};

async function sendFile(res, file) {
  const body = await readFile(file);
  res.writeHead(200, { 'content-type': types[extname(file)] || 'application/octet-stream' });
  res.end(body);
}

createServer(async (req, res) => {
  const { pathname } = new URL(req.url, 'http://localhost');
  const relative = decodeURIComponent(pathname).replace(/^\/+/, '');
  const file = resolve(rootDir, relative || 'index.html');

  if (!file.startsWith(`${rootDir}/`) && file !== rootDir) {
    res.writeHead(403).end();
    return;
  }

  try {
    await sendFile(res, file);
  } catch {
    // SPA fallback: unknown routes serve index.html.
    try {
      await sendFile(res, resolve(rootDir, 'index.html'));
    } catch {
      res.writeHead(404).end('not found');
    }
  }
}).listen(port, '127.0.0.1', () => {
  console.log(`serving ${rootDir} on http://127.0.0.1:${port}`);
});
