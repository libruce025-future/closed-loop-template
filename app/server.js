const http = require('node:http');

const PORT = Number(process.env.PORT || 3000);
const GIT_SHA = process.env.GIT_SHA || 'dev';

function createServer() {
  return http.createServer((req, res) => {
    const { pathname } = new URL(req.url, 'http://localhost');
    const send = (status, body, type = 'application/json') => {
      res.writeHead(status, { 'content-type': type });
      res.end(body);
    };

    if (req.method !== 'GET') {
      return send(405, JSON.stringify({ error: 'method not allowed' }));
    }
    if (pathname === '/health') {
      return send(200, JSON.stringify({ status: 'ok' }));
    }
    if (pathname === '/version') {
      return send(200, JSON.stringify({ sha: GIT_SHA }));
    }
    if (pathname === '/') {
      return send(200, `closed-loop-template\nsha: ${GIT_SHA}\n`, 'text/plain; charset=utf-8');
    }
    return send(404, JSON.stringify({ error: 'not found' }));
  });
}

if (require.main === module) {
  const server = createServer();
  server.listen(PORT, () => {
    console.log(`listening on :${PORT} sha=${GIT_SHA}`);
  });
  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = { createServer };
