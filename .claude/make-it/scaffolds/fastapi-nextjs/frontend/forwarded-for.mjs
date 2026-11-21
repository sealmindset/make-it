// Adds the address that connected to X-Forwarded-For, as a proxy should, before Next.js sees the
// request. The /api rewrite in next.config.ts passes request headers to the backend unchanged and
// adds no address of its own, so without this the backend sees only this container's address, or
// an address the caller wrote into the header. The backend believes the header only from proxies
// named in TRUSTED_PROXIES, and takes the right-most address that is not one of them.
// Loaded before the server starts: node --import ./forwarded-for.mjs server.js (see the Dockerfile).
import http from "node:http";

function withForwardedFor(listener) {
  return function (req, res) {
    let address = req.socket?.remoteAddress;
    if (address) {
      if (address.startsWith("::ffff:")) address = address.slice(7); // an IPv4 address, IPv6-mapped
      const earlier = req.headers["x-forwarded-for"];
      req.headers["x-forwarded-for"] = earlier ? `${earlier}, ${address}` : address;
    }
    return listener.call(this, req, res);
  };
}

const createServer = http.createServer;

http.createServer = function (...args) {
  return createServer.apply(
    this,
    args.map((arg) => (typeof arg === "function" ? withForwardedFor(arg) : arg))
  );
};
