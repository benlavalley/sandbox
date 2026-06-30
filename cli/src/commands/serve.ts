import { randomBytes } from "node:crypto";
import { CONFIG_PATH, readConfig, writeConfig } from "../lib/config.ts";

export async function run(_args: string[]) {
  // If API_KEYS is already set (e.g. via docker-compose env), skip config file
  if (!process.env.API_KEYS) {
    let config = readConfig();

    if (!config) {
      const apiKey = `e2b_${randomBytes(20).toString("hex")}`;
      config = { apiKey };
      writeConfig(config);
      console.log("Generated a new API key.");
    }

    process.env.API_KEYS = config.apiKey;
    if (config.backend) {
      process.env.SANDBOX_BACKEND = config.backend;
    }

    // Surface the key and where it's stored on every start (not just the first
    // run that generated it), so it's always discoverable.
    console.log(`API key: ${config.apiKey}`);
    console.log(`Config:  ${CONFIG_PATH}\n`);
  }

  // Import starts the server via Bun's default export
  await import("../server/index.ts");
}
