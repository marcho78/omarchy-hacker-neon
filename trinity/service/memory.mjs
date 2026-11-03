// What Trinity remembers about the user between conversations: short items,
// saved only when the user asks her to remember something (or says yes when
// she offers), kept in ~/.local/share/trinity/memory.json on this computer.
// Each session starts with them added to her instructions.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const FILE = path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share"), "trinity", "memory.json");

export function memories() {
  try {
    const items = JSON.parse(fs.readFileSync(FILE, "utf8")).items;
    return Array.isArray(items) ? items : [];
  } catch {
    return [];
  }
}

function save(items) {
  fs.mkdirSync(path.dirname(FILE), { recursive: true, mode: 0o700 });
  const tmp = `${FILE}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ items }, null, 2) + "\n", { mode: 0o600 });
  fs.renameSync(tmp, FILE);
}

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function remember(text) {
  const items = memories();
  const item = { id: items.reduce((max, i) => Math.max(max, i.id), 0) + 1, text: String(text).trim(), saved: today() };
  items.push(item);
  save(items);
  return item;
}

// The items `what` names: "last" (the newest), an id, or words from the item.
// Words match items that contain them, or else the one sharing the most of them.
export function find(what) {
  const items = memories();
  const query = String(what ?? "").trim().toLowerCase();
  if (!query || !items.length) return [];
  if (query === "last") return [items[items.length - 1]];
  if (/^\d+$/.test(query)) return items.filter((i) => i.id === Number(query));
  const containing = items.filter((i) => i.text.toLowerCase().includes(query));
  if (containing.length) return containing;
  const words = query.split(/\W+/).filter((w) => w.length > 2);
  let best = [];
  let bestScore = 0;
  for (const item of items) {
    const text = item.text.toLowerCase();
    const score = words.filter((w) => text.includes(w)).length;
    if (score > bestScore) [best, bestScore] = [[item], score];
    else if (score === bestScore && score > 0) best.push(item);
  }
  return bestScore >= Math.ceil(words.length / 2) ? best : [];
}

export function forget(ids) {
  const items = memories();
  save(items.filter((i) => !ids.includes(i.id)));
  return items.filter((i) => ids.includes(i.id));
}

export function forgetAll() {
  const count = memories().length;
  save([]);
  return count;
}

// The memories as an addition to her instructions, or "" when there are none.
export function memoryInstructions() {
  const items = memories();
  if (!items.length) return "";
  return (
    "\n\nWhat you remember about the user, saved at their request (use it naturally; don't list it unless asked):\n" +
    items.map((i) => `- ${i.text} (saved ${i.saved})`).join("\n")
  );
}
