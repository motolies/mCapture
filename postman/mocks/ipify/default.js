// Contract: https://www.ipify.org/ (GET ?format=json -> {ip: string}, no auth).
// Extra paths are local fault fixtures, not provider API routes.
const http = require('http');
http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (req.method !== 'GET' || url.searchParams.get('format') !== 'json') {
    res.writeHead(501); return res.end();
  }
  const count = ((await pm.state.get('ipify.count')) || 0) + 1;
  await pm.state.set('ipify.count', count);
  const responses = {
    '/delayed': [200, '{"ip":"198.51.100.43"}'],
    '/cache': [200, JSON.stringify({ip: '192.0.2.' + (count % 250 + 1)})],
    '/v4': [200, '{"ip":"198.51.100.42"}'],
    '/v6': [200, '{"ip":"2001:db8::42"}'],
    '/invalid': [200, '{"ip":"not-an-ip"}'],
    '/malformed': [200, '<html>proxy error</html>'],
    '/error': [503, '{"error":"unavailable"}'],
    '/slow': [200, '{"ip":"198.51.100.42"}']
  };
  const response = responses[url.pathname];
  if (!response) { res.writeHead(501); return res.end(); }
  const send = () => { res.writeHead(response[0], {'Content-Type': 'application/json'}); res.end(response[1]); };
  if (url.pathname === '/slow') setTimeout(send, 6000);
  else if (url.pathname === '/delayed') setTimeout(send, 200);
  else send();
}).listen(process.env.PORT);
