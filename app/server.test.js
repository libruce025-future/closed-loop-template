const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('./server');

let server;
let base;

before(async () => {
  server = createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => new Promise((resolve) => server.close(resolve)));

test('GET /health returns 200 ok', async () => {
  const res = await fetch(`${base}/health`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: 'ok' });
});

test('GET /version returns a sha string', async () => {
  const res = await fetch(`${base}/version`);
  assert.equal(res.status, 200);
  assert.equal(typeof (await res.json()).sha, 'string');
});

test('unknown path returns 404', async () => {
  const res = await fetch(`${base}/nope`);
  assert.equal(res.status, 404);
});

test('non-GET returns 405', async () => {
  const res = await fetch(`${base}/health`, { method: 'POST' });
  assert.equal(res.status, 405);
});
