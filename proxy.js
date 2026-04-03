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
  } else {
    res.writeHead(404);
    res.end('Not Found');
  }
};

const server = http.createServer(requestListener);
server.listen(port, host, () => {
  console.log(`Proxy server is running on http://${host}:${port}`);
});
