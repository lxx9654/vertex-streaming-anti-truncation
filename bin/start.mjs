#!/usr/bin/env node
import { loadConfig } from "../src/config.mjs";
import { createGatewayServer } from "../src/gateway.mjs";

try {
  const config = await loadConfig();
  const logger = event => process.stdout.write(JSON.stringify(event) + "\n");
  const server = createGatewayServer(config, { logger });
  // Container builds set HOST=0.0.0.0 so the gateway is reachable from outside the container.
  const host = process.env.HOST || "127.0.0.1";
  server.on("error", () => { console.error("Gateway could not bind its port"); process.exitCode = 1; });
  server.listen(config.port, host, () => {
    logger({ event: "listening", host, endpoint: `http://${host}:${config.port}/v1`, model: config.model });
  });
  let stopping = false;
  for (const name of ["SIGINT", "SIGTERM"]) process.on(name, () => {
    if (stopping) return;
    stopping = true;
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000).unref();
  });
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
