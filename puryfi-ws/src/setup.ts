import fs from "node:fs";
import path from "node:path";
import readline from "node:readline/promises";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function main() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const backend =
    (await rl.question("URL backend BG (ex: https://bg-backend.fly.dev): ")).trim() ||
    "https://bg-backend.fly.dev";
  rl.close();

  const root = path.join(__dirname, "..");
  const envPath = path.join(root, ".env");
  const env = `BG_BACKEND_URL=${backend.replace(/\/$/, "")}\n`;
  fs.writeFileSync(envPath, env, "utf8");
  console.log("Écrit:", envPath);
  console.log(
    "\nSur ton dashboard beta (section PuryFi), copie l’URL wss://…/ws/… et colle-la dans le client PuryFi. L’identification est dans l’URL (plus besoin de token appareil sur Fly).",
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
