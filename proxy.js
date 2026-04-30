const http = require('http');
const https = require('https');

const host = '0.0.0.0';
const port = 8081;

const requestListener = function (req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, PATCH, DELETE');
  res.setHeader('Access-Control-Allow-Headers', 'X-Requested-With,content-type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  if (req.url.startsWith('/mp/')) {
    const mpPath = req.url.replace('/mp/', '/');
    const options = {
      hostname: 'api.mercadopago.com',
      port: 443,
      path: mpPath,
      method: req.method,
      headers: {
        'Authorization': req.headers['authorization'],
        'Content-Type': 'application/json'
      }
    };

    const proxy = https.request(options, function(proxy_res) {
      res.writeHead(proxy_res.statusCode, proxy_res.headers);
      proxy_res.pipe(res, { end: true });
    });

    req.pipe(proxy, { end: true });

  } else if (req.url.startsWith('/clip/')) {
    const clipPath = req.url.replace('/clip/', '/');
    const CLIP_API_KEY    = 'test_d22cc57f-3c03-41a0-876b-a8280133aefb';
    const CLIP_SECRET_KEY = '06470f91-c6d2-440c-87dd-3615a876b381';
    const authHeader = 'Basic ' + Buffer.from(`${CLIP_API_KEY}:${CLIP_SECRET_KEY}`).toString('base64');

    const options = {
      hostname: 'api-checkoutx.clip.mx',
      port: 443,
      path: clipPath,
      method: req.method,
      headers: {
        'Authorization': authHeader,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }
    };

    const proxy = https.request(options, function(proxy_res) {
      res.writeHead(proxy_res.statusCode, { 'Content-Type': 'application/json' });
      proxy_res.pipe(res, { end: true });
    });

    proxy.on('error', (e) => {
      res.writeHead(500);
      res.end(JSON.stringify({ error: e.message }));
    });

    req.pipe(proxy, { end: true });

  } else {
    res.writeHead(404);
    res.end('Not Found');
  }
};

const server = http.createServer(requestListener);
server.listen(port, host, () => {
  console.log(`Proxy server is running on http://${host}:${port}`);
});
