// Trinity's desktop actions: the only things she can do on the computer. Each
// is a function tool the agent may call; the service runs it with Omarchy's
// own commands or Hyprland's, and hands back the result.
//
// Safety:
// - Actions that are safe and easy to undo run at once.
// - Actions that can lose work or are hard to undo ask first. The first call
//   returns a question and a confirmation id; the action runs only when called
//   again with that id after the user has spoken or typed since (their yes),
//   so the agent can't confirm on its own.
// - Files are only touched inside the home folder.
// - Every action is logged to ~/.local/state/trinity/actions.log.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile, spawn } from "node:child_process";
import { remember, memories, find, forget, forgetAll } from "./memory.mjs";

const HOME = os.homedir();
const LOG = path.join(process.env.XDG_STATE_HOME || path.join(HOME, ".local", "state"), "trinity", "actions.log");
const TERMINALS = /alacritty|foot|kitty|ghostty|wezterm|terminal|konsole|xterm|org\.omarchy\./i;

// ---------------------------------------------------------------- running

function run(cmd, args = [], timeout = 10000) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout, encoding: "utf8" }, (err, stdout, stderr) => {
      resolve({ ok: !err, out: String(stdout || "").trim(), err: String(stderr || (err && err.message) || "").trim() });
    });
  });
}

// For programs that keep running (apps, a recording): started, not waited on.
function launch(cmd, args) {
  const child = spawn(cmd, args, { detached: true, stdio: "ignore" });
  child.on("error", () => {});
  child.unref();
}

async function dispatch(lua) {
  const r = await run("hyprctl", ["dispatch", lua]);
  if (!r.ok || (r.out && r.out !== "ok")) throw new Error(r.out || r.err || "Hyprland refused it");
}

async function json(cmd, args) {
  const r = await run(cmd, args);
  if (!r.ok) throw new Error(r.err || `${cmd} failed`);
  return JSON.parse(r.out);
}

const lua = (s) => JSON.stringify(String(s));

// Herdr is installed through mise, whose shims aren't on the service's PATH.
const HERDR = fs.existsSync(path.join(HOME, ".local", "share", "mise", "shims", "herdr")) ? path.join(HOME, ".local", "share", "mise", "shims", "herdr") : "herdr";

async function herdr(args) {
  const r = await run(HERDR, args);
  if (!r.ok) throw new Error(r.err || "Herdr isn't running.");
  return JSON.parse(r.out).result || {};
}

// What's on the desktop board (the decoding feed the orb draws on the
// wallpaper): the service passes it on to the orb.
let showBoard = () => {};
export function onBoard(fn) {
  showBoard = fn;
}

// The video on the desktop: the service passes {type: "play", video} and
// {type: "control", command, seconds} on to the orb's player.
let videoHook = () => {};
export function onVideo(fn) {
  videoHook = fn;
}

// A YouTube video, found with yt-dlp: a link or id as is, else the first
// search result, or with newest the latest upload of that result's channel
// (this yt-dlp has no newest-first search). {id, title, channel, duration}.
async function ytJson(target, extra = []) {
  const r = await run("/usr/bin/yt-dlp", ["--flat-playlist", "-J", "--no-warnings", ...extra, "--", target], 40000);
  if (!r.ok) throw new Error((r.err || "YouTube didn't answer.").split("\n").pop());
  return JSON.parse(r.out);
}

async function findVideo(query, newest) {
  if (!query) throw new Error("Nothing to play.");
  const id = (query.match(/(?:youtu\.be\/|[?&]v=|\/shorts\/|\/live\/)([A-Za-z0-9_-]{11})/) || [])[1] || (/^[A-Za-z0-9_-]{11}$/.test(query) ? query : "");
  let entry;
  if (id) {
    entry = await ytJson("https://www.youtube.com/watch?v=" + id);
  } else {
    const found = ((await ytJson("ytsearch1:" + query)).entries || [])[0];
    if (!found) throw new Error(`Nothing on YouTube matches "${query}".`);
    entry = found;
    if (newest) {
      const channel = found.channel_url || (found.channel_id ? "https://www.youtube.com/channel/" + found.channel_id : "");
      const latest = channel ? ((await ytJson(channel + "/videos", ["--playlist-end", "1"])).entries || [])[0] : null;
      if (latest) entry = { ...latest, channel: latest.channel || found.channel || found.uploader };
    }
  }
  if (!entry || !/^[A-Za-z0-9_-]{11}$/.test(entry.id || "")) throw new Error("That isn't a video that can be played.");
  return { id: entry.id, title: entry.title || "YouTube video", channel: entry.channel || entry.uploader || "", duration: Number(entry.duration) || 0 };
}

// Everything Herdr's CLI offers a voice agent (Herdscope, its window, shows the
// same server), as "group command": null runs at once; a function words the
// question for the ones that ask first: closing, removing, deleting or
// stopping something, running a command or typing or pressing keys in a pane
// or agent, giving an agent a task, and installing or removing integrations.
// Left out: attaching to a terminal, the reports agents make about
// themselves, pane input routing, and server upkeep.
const herdrLine = (command, args) => ["herdr", command, ...args].join(" ");
const HERDR_COMMANDS = {
  "workspace list": null, "workspace get": null, "workspace create": null, "workspace focus": null, "workspace rename": null,
  "workspace close": (a) => `Close the Herdr workspace ${a[0] || ""} and everything running in it?`,
  "tab list": null, "tab get": null, "tab create": null, "tab focus": null, "tab rename": null,
  "tab close": (a) => `Close the Herdr tab ${a[0] || ""} and what's running in it?`,
  "pane list": null, "pane get": null, "pane layout": null, "pane process-info": null, "pane neighbor": null, "pane edges": null,
  "pane focus": null, "pane resize": null, "pane zoom": null, "pane read": null, "pane rename": null, "pane split": null,
  "pane swap": null, "pane move": null, "pane wait-output": null,
  "pane close": (a) => `Close the Herdr pane ${a[0] || ""} and what's running in it?`,
  "pane run": (a) => `Run this in a Herdr pane: ${herdrLine("pane run", a)}?`,
  "pane send-text": (a) => `Type this into a Herdr pane: ${herdrLine("pane send-text", a)}?`,
  "pane send-keys": (a) => `Press these keys in a Herdr pane: ${herdrLine("pane send-keys", a)}?`,
  "agent list": null, "agent get": null, "agent read": null, "agent rename": null, "agent focus": null, "agent wait": null,
  "agent start": null, "agent explain": null,
  "agent prompt": (a) => `Give the agent ${a[0] || ""} this task: "${a[1] || ""}"?`,
  "agent send-keys": (a) => `Press these keys in the agent ${a[0] || ""}: ${a.slice(1).join(" ")}?`,
  "worktree list": null, "worktree create": null, "worktree open": null,
  "worktree remove": (a) => `Remove the worktree checkout: ${herdrLine("worktree remove", a)}?`,
  "notification show": null,
  "session list": null,
  "session stop": (a) => `Stop the Herdr session ${a[0] || ""}? Everything running in it stops.`,
  "session delete": (a) => `Delete the stopped Herdr session ${a[0] || ""}?`,
  "integration status": null,
  "integration install": (a) => `Install the Herdr integration ${a[0] || ""}?`,
  "integration uninstall": (a) => `Remove the Herdr integration ${a[0] || ""}?`,
};
// The ones that bring Herdr's window to the front when they succeed.
const HERDR_SHOWS = ["workspace focus", "workspace create", "tab focus", "tab create", "agent focus", "pane focus"];

// Herdr's window to the front: the Herdscope app, or else a terminal running
// herdr. Returns its app name, or "".
async function raiseHerdr() {
  const list = await windows();
  const w = list.find((x) => /herdscope|herdr/i.test(x.app)) || list.find((x) => /herdr/i.test(x.title) && TERMINALS.test(x.app));
  if (w) await dispatch(`hl.dsp.focus({ window = ${lua("address:" + w.address)} })`);
  return w ? w.app : "";
}

const shortPath = (p) => (p && p.startsWith(HOME) ? "~" + p.slice(HOME.length) : p || "");

// ---------------------------------------------------------------- reading the screen

// Where Omarchy's screenshot tool saves.
const SCREENSHOTS = process.env.OMASNAP_SCREENSHOT_DIR || process.env.OMARCHY_SCREENSHOT_DIR || path.join(HOME, "Pictures", "Screenshots");

// Runs a program with `input` on its stdin and resolves with its stdout as a
// Buffer.
function pipe(cmd, args, input) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ["pipe", "pipe", "pipe"] });
    const out = [];
    let err = "";
    child.stdout.on("data", (d) => out.push(d));
    child.stderr.on("data", (d) => (err += d));
    child.on("error", reject);
    child.on("close", (code) => (code === 0 ? resolve(Buffer.concat(out)) : reject(new Error(err.trim() || `${cmd} failed`))));
    child.stdin.on("error", () => {});
    child.stdin.end(input || undefined);
  });
}

// The text in an image (PNG, JPEG...), recognized on this computer by
// tesseract. Only the text goes anywhere; the picture stays here.
async function readImage(image) {
  const text = (await pipe("tesseract", ["stdin", "stdout", "--psm", "3"], image)).toString("utf8");
  const clean = text.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
  if (!clean) return { text: "", note: "No readable text was found." };
  return { text: clean.length > LONG ? clean.slice(0, LONG) + "\n… (cut)" : clean };
}

// The newest file in the screenshot folder, or null.
function latestScreenshot() {
  try {
    return fs
      .readdirSync(SCREENSHOTS)
      .filter((f) => /\.(png|jpe?g)$/i.test(f))
      .map((f) => ({ file: path.join(SCREENSHOTS, f), at: fs.statSync(path.join(SCREENSHOTS, f)).mtimeMs }))
      .sort((a, b) => b.at - a.at)[0] || null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------- finding apps and windows

// The apps the launcher lists: desktop entries by id, with their names.
function desktopEntries() {
  const dirs = [path.join(HOME, ".local", "share")].concat((process.env.XDG_DATA_DIRS || "/usr/local/share:/usr/share").split(":"));
  const entries = new Map();
  for (const dir of dirs) {
    const appsDir = path.join(dir, "applications");
    let files = [];
    try {
      files = fs.readdirSync(appsDir).filter((f) => f.endsWith(".desktop"));
    } catch {
      continue;
    }
    for (const file of files) {
      const id = file.slice(0, -".desktop".length);
      if (entries.has(id)) continue;
      let text = "";
      try {
        text = fs.readFileSync(path.join(appsDir, file), "utf8");
      } catch {
        continue;
      }
      const section = text.split(/^\[/m).find((s) => s.startsWith("Desktop Entry]")) || "";
      const field = (key) => (section.match(new RegExp(`^${key}=(.*)$`, "m")) || [])[1] || "";
      if (field("NoDisplay") === "true" || field("Hidden") === "true" || (field("Type") || "Application") !== "Application") continue;
      entries.set(id, { id, name: field("Name") || id, wmClass: field("StartupWMClass") });
    }
  }
  return [...entries.values()];
}

// The best match for a spoken name: exact, then starts with, then contains.
function best(items, name, keys) {
  const want = String(name || "").toLowerCase().trim();
  if (!want) return null;
  const score = (item) => {
    let top = 0;
    for (const key of keys) {
      const value = String(item[key] || "").toLowerCase();
      if (!value) continue;
      if (value === want) top = Math.max(top, 3);
      else if (value.startsWith(want)) top = Math.max(top, 2);
      else if (value.includes(want)) top = Math.max(top, 1);
    }
    return top;
  };
  let found = null;
  let foundScore = 0;
  for (const item of items) {
    const s = score(item);
    if (s > foundScore) {
      found = item;
      foundScore = s;
    }
  }
  return found;
}

async function windows() {
  const clients = await json("hyprctl", ["clients", "-j"]);
  const active = await json("hyprctl", ["activewindow", "-j"]).catch(() => ({}));
  return clients
    .filter((c) => c.mapped !== false && c.workspace && c.workspace.id > 0)
    .map((c) => ({
      address: c.address,
      app: c.class || c.initialClass,
      title: c.title,
      workspace: c.workspace.id,
      floating: c.floating,
      focused: c.address === active.address,
    }));
}

// A window by app name or title, or the focused one when no app is named.
async function findWindow(app) {
  const list = await windows();
  if (!app) {
    const focused = list.find((w) => w.focused);
    if (!focused) throw new Error("No window is focused.");
    return focused;
  }
  const entry = best(desktopEntries(), app, ["name"]);
  const byName = best(list, app, ["app", "title"]);
  if (byName) return byName;
  if (entry) {
    const wanted = [entry.wmClass, entry.id].filter(Boolean).map((s) => s.toLowerCase());
    const match = list.find((w) => wanted.some((n) => String(w.app).toLowerCase().includes(n) || n.includes(String(w.app).toLowerCase())));
    if (match) return match;
  }
  throw new Error(`No open window matches "${app}".`);
}

// A path inside the home folder, from what the user said ("notes/plan.md",
// "~/Documents/x.txt", or a full path).
function homePath(p) {
  let full = String(p || "").trim();
  if (!full) throw new Error("No file was named.");
  if (full === "~" || full.startsWith("~/")) full = path.join(HOME, full.slice(1));
  if (!path.isAbsolute(full)) full = path.join(HOME, full);
  full = path.resolve(full);
  if (full !== HOME && !full.startsWith(HOME + path.sep)) throw new Error("Trinity only works with files inside your home folder.");
  return full;
}

// A key combination ("ctrl+shift+t", "enter") as wtype arguments: modifiers
// held, the key pressed, modifiers let go.
const MODIFIERS = { ctrl: "ctrl", control: "ctrl", shift: "shift", alt: "alt", super: "logo", win: "logo", meta: "logo" };
const KEYS = {
  enter: "Return", return: "Return", tab: "Tab", escape: "Escape", esc: "Escape", backspace: "BackSpace",
  delete: "Delete", del: "Delete", space: "space", up: "Up", down: "Down", left: "Left", right: "Right",
  home: "Home", end: "End", pageup: "Prior", pagedown: "Next", insert: "Insert",
};

export function comboArgs(combo) {
  const parts = String(combo || "").toLowerCase().split("+").map((p) => p.trim()).filter(Boolean);
  const key = parts.pop();
  const mods = parts.map((m) => {
    if (!MODIFIERS[m]) throw new Error(`"${m}" isn't a modifier key.`);
    return MODIFIERS[m];
  });
  let name = KEYS[key];
  if (!name && /^f([1-9]|1[0-2])$/.test(key)) name = key.toUpperCase();
  if (!name && /^[a-z0-9]$/.test(key)) name = key;
  if (!name) throw new Error(`"${combo}" isn't a key Trinity can press.`);
  return [...mods.flatMap((m) => ["-M", m]), "-k", name, ...mods.reverse().flatMap((m) => ["-m", m])];
}

// ---------------------------------------------------------------- Uber Notebook and Uber TV

// Each app's commands Trinity may use, with their arguments in order. FILE is
// Markdown she writes (the `text` argument), put in a file for the command.
// The ones marked confirm ask the user first.
const NOTES = {
  find: { args: ["words"] },
  list: { args: [] },
  read: { args: ["page id"] },
  blocks: { args: ["page id"] },
  tagged: { args: ["tag"] },
  projects: { args: [] },
  templates: { args: [] },
  add: { args: ["title", "FILE"] },
  addTo: { args: ["parent page id (\"\" for the top)", "title", "FILE"] },
  append: { args: ["page id", "FILE"] },
  check: { args: ["page id", "block id", "true|false"] },
  fromTemplate: { args: ["template name or id", "title", "parent page id"] },
  events: { args: ["from (2026-10-05 or \"\")", "to"] },
  addEvent: { args: ["what and when, e.g. \"Dentist oct 12 3pm\"", "repeat (daily, weekdays, weekly, monthly, yearly or \"\")"] },
  editEvent: { args: ["event id", "field (title, when, start, end, ...)", "value"] },
  contacts: { args: ["words (\"\" for everyone)"] },
  contact: { args: ["id or name"] },
  addContact: { args: ["name", "phone", "email"] },
  open: { args: ["page id"] },
  trashed: { args: [] },
  restore: { args: ["page id"] },
  history: { args: ["page id"] },
  profiles: { args: [] },
  trash: { args: ["page id"], confirm: (a) => `Move the page ${a[0]} (and the pages in it) to the trash?` },
  removeEvent: { args: ["event id"], confirm: (a) => `Remove the event ${a[0]} from the calendar (all of it, if it repeats)?` },
  removeContact: { args: ["contact id"], confirm: (a) => `Remove ${a[0]} from People?` },
  restoreVersion: { args: ["page id", "version name"], confirm: (a) => `Put page ${a[0]} back to the version "${a[1]}"? The page as it is now is kept in its history.` },
  profile: { args: ["profile name or id"], confirm: (a) => `Switch Uber Notebook to the profile "${a[0]}"?` },
};

const TV = {
  help: { args: [] },
  state: { args: [] },
  open: { args: [] },
  display: { args: ["full | window"] },
  close: { args: [] },
  watch: { args: ["channel number"] },
  multiview: { args: ["channel numbers with commas, up to 4"] },
  record: { args: ["channel number", "length (\"\" for to the show's end)"] },
  pauseLive: { args: [] },
  seekLive: { args: ["seconds (negative goes back)"] },
  goLive: { args: [] },
  recordUntil: { args: ["recording id", "minutes | HH:MM"] },
  stopRecording: { args: ["recording id"] },
  recordings: { args: [] },
  recordShow: { args: ["channel number", "HH:MM | YYYY-MM-DD HH:MM | next"] },
  recordSeries: { args: ["channel number", "HH:MM | YYYY-MM-DD HH:MM | now | next"] },
  cancelRecording: { args: ["recording id"], confirm: (a) => `Cancel the recording ${a[0]}?` },
  playRecording: { args: ["recording id"] },
  startOver: { args: ["recording or video id"] },
  shows: { args: ["<number>", "<words>"] },
  removeRecording: { args: ["recording id"], confirm: (a) => `Delete the recording ${a[0]} and its file?` },
  recordingDrives: { args: [] },
  recordingSettings: { args: [] },
  setRecordingSettings: { args: ["<json>"] },
  libraryTabs: { args: [] },
  setLibraryTabs: { args: ["<keys>"] },
  multiviewAdd: { args: ["channel number"] },
  multiviewRemove: { args: ["channel number"] },
  multiviewLayout: { args: ["side | featured | grid | row"] },
  multiviewSound: { args: ["channel number"] },
  multiviewClose: { args: [] },
  themes: { args: [] },
  remoteTemplates: { args: [] },
  remoteTemplate: { args: ["<id>"] },
  remoteControls: { args: [] },
  addRemoteTemplate: { args: ["<json>"] },
  setRemoteTemplate: { args: ["id", "phone"] },
  setRemotePrefs: { args: ["phone", "json"] },
  removeRemoteTemplate: { args: ["<id>"], confirm: (a) => `Delete the phone remote template ${a[0]}?` },
  theme: { args: ["theme id"] },
  addTheme: { args: ["<json>"] },
  saveTheme: { args: ["<name>", "<description>"] },
  removeTheme: { args: ["theme id"], confirm: (a) => `Delete the Uber TV theme ${a[0]}?` },
  slots: { args: [] },
  style: { args: [] },
  setColor: { args: ["<key>", "<#hex>"] },
  reset: { args: ["theme | original | undo"], confirm: (a) => (a[0] === "undo" ? null : `Reset Uber TV's ${a[0] || "look"}, taking your own changes off? "reset undo" brings it back.`) },
  resetColors: { args: [], confirm: () => "Take your own colors off Uber TV, back to the theme's?" },
  images: { args: [] },
  setImage: { args: ["<area>", "<picture>", "<fit>", "<opacity>"] },
  background: { args: ["<none|wallpaper|/path/picture.jpg>", "<dim>"] },
  multiviewBackground: { args: ["<none|#rrggbb|theme|wallpaper|/path/picture.jpg>", "<dim>"] },
  lowerThird: { args: ["<on|off>", "<seconds>"] },
  card: { args: ["<on|off>", "<seconds>"] },
  elements: { args: [""] },
  setStyle: { args: ["<element>", "<json>"] },
  fonts: { args: ["<words>"] },
  snapshot: { args: ["path (\"\" for its own)"] },
  home: { args: [] },
  setHome: { args: ["<json>"] },
  rail: { args: [] },
  setRail: { args: ["<items>", "<always|focus|none>"] },
  videos: { args: ["<words>"] },
  screenSaver: { args: [] },
  setScreenSaver: { args: ["<json>"] },
  setVideos: { args: ["<on|off>", "<folder>"] },
  listings: { args: [] },
  addListings: { args: ["<link or path>"] },
  removeListings: { args: ["<link or path>"], confirm: (a) => `Take the listings source ${a[0]} off Uber TV?` },
  search: { args: ["<words>"] },
  library: { args: ["<words>"] },
  play: { args: ["<id>"] },
  channels: { args: ["<words>"] },
  categories: { args: [] },
  addChannels: { args: ["<text>"] },
  demoChannels: { args: [] },
  loadDemoChannels: { args: [], confirm: () => "Add the demo lineup's channels to your guide? Nothing is removed." },
  status: { args: [] },
  show: { args: ["<both|youtube|iptv>", "<categories>"] },
  rename: { args: ["<number>", "<name>"] },
  setCategory: { args: ["<numbers>", "<category>"] },
  removeChannels: { args: ["<numbers>"], confirm: (a) => `Remove channel${String(a[0]).includes(",") ? "s" : ""} ${a[0]} from Uber TV?` },
  logos: { args: ["<on|off>"] },
  keyHints: { args: ["<on|off>"] },
  touchControls: { args: ["<auto|on|off|\"\">"], confirm: (a) => `Change Uber TV's touch controls to ${a[0]}?` },
  refresh: { args: [] },
  apps: { args: [] },
  appScreen: { args: ["id"] },
  setAppScreen: { args: ["id", "json"] },
  resetAppScreen: { args: ["id"], confirm: (a) => (a[0] === "all" ? "Put every app's screen back to the theme's look?" : `Make the app ${a[0]}'s screen follow the look for every app again?`) },
  openApp: { args: ["id", "handle"] },
  appSnapshot: { args: ["<view>"] },
  appOff: { args: ["<id>"] },
};

const LONG = 16000;

// Runs an app command through omarchy-shell. A long answer comes as a file,
// which is read (and cut to a size she can take in).
// Hill Chart (marcho78.hillchart), the user's projects on a hill on the bar:
// uphill while figuring the work out, downhill while doing it, 100 = done.
const HILL = {
  list: { args: [] },
  toggle: { args: [] },
  peek: { args: [] },
  add: { args: ["name"] },
  addAt: { args: ["name", "percent 0-100"] },
  move: { args: ["project id, whole name or unique start of one", "percent 0-100"] },
  remove: { args: ["project id, whole name or unique start of one"], confirm: (a) => `Remove the project "${a[0]}" from your hill chart?` },
};

// Some answers come in two steps: Uber Notebook reads a given file (or a
// page's history) in the background and asks for the same command again in a
// moment, with the same file. So the command is asked again, a few times,
// before the answer counts; the caller keeps its file until then.
async function appCommand(app, command, args) {
  for (let tries = 0; ; tries++) {
    try {
      return await appCommandOnce(app, command, args);
    } catch (err) {
      if (tries >= 15 || !/again in a moment/i.test(err.message)) throw err;
      await new Promise((resolve) => setTimeout(resolve, 400));
    }
  }
}

async function appCommandOnce(app, command, args) {
  const r = await run("omarchy-shell", [app, command, ...args], 60000);
  let text = r.out;
  try {
    const answer = JSON.parse(text);
    if (answer && answer.file) text = fs.readFileSync(answer.file, "utf8");
    else if (answer && answer.ok === false) throw new Error(answer.error || "The app said no.");
    else return answer;
  } catch (err) {
    if (!(err instanceof SyntaxError)) throw err;
  }
  if (!r.ok && !text) throw new Error(r.err || `${app} ${command} failed.`);
  return { text: text.length > LONG ? text.slice(0, LONG) + "\n… (cut)" : text };
}

function appAction(app, label, commands, extra) {
  const list = Object.entries(commands)
    .map(([name, c]) => `${name}(${c.args.join(", ")})${c.confirm ? " [asks the user first]" : ""}`)
    .join("; ");
  return {
    description: `${label} Commands and their arguments, in order: ${list}.${extra || ""} For anything unusual, read app_guide first.`,
    parameters: {
      command: { type: "string", enum: Object.keys(commands) },
      args: { type: "array", items: { type: "string" }, description: "The command's arguments, in order, as strings. Leave out FILE: give it as text." },
      text: { type: "string", description: "Markdown for a command that takes FILE (the page's or addition's content)." },
      confirmation_id: confirmation,
    },
    required: ["command"],
    confirm: async ({ command, args }) => {
      const c = commands[command];
      return c && c.confirm ? c.confirm(args || []) : null;
    },
    run: async ({ command, args, text }) => {
      const c = commands[command];
      if (!c) throw new Error(`${command} isn't a command Trinity can use.`);
      const given = (args || []).map(String);
      let file = null;
      const full = [];
      let i = 0;
      for (const arg of c.args) {
        if (arg === "FILE") {
          // A new page may start empty; anything else needs text.
          const newPage = app === "uber-notebook" && (command === "add" || command === "addTo");
          if (!text && !newPage) throw new Error(`${command} needs the text to write.`);
          // Uber Notebook puts a new page's title at its top already, so a
          // first heading that repeats it is dropped.
          if (newPage) {
            const title = String(command === "add" ? given[0] ?? "" : given[1] ?? "").trim();
            const lines = String(text || "").split("\n");
            if (title && /^#\s+/.test(lines[0] || "") && lines[0].replace(/^#\s+/, "").trim().toLowerCase() === title.toLowerCase()) lines.shift();
            text = lines.join("\n").replace(/^\n+/, "") || "\n";
          }
          file = path.join(os.tmpdir(), `trinity-${process.pid}-${Date.now()}.md`);
          fs.writeFileSync(file, text);
          full.push(file);
        } else full.push(given[i++] ?? "");
      }
      try {
        return { answer: await appCommand(app, command, full) };
      } finally {
        if (file) fs.rmSync(file, { force: true });
      }
    },
  };
}

// The skill files, for the details the action descriptions leave out.
const GUIDES = {
  notes: path.join(HOME, ".config/omarchy/plugins/marcho78.uber-notebook/skills/uber-notebook/SKILL.md"),
  tv: path.join(HOME, ".config/omarchy/plugins/marcho78.om-pg/skills/program-guide/SKILL.md"),
  hill: path.join(HOME, ".config/omarchy/plugins/marcho78.hillchart-11/README.md"),
};

// ---------------------------------------------------------------- the actions

const ws = { type: "string", description: "Workspace number, 1 to 10." };
const appName = { type: "string", description: "The app's name as the user said it (e.g. Chromium, Obsidian, terminal). Leave out to mean the focused window." };
const confirmation = { type: "string", description: "Only when calling again after the user said yes: the confirmation_id this action returned." };

export const ACTIONS = {
  list_windows: {
    description: "List the open windows: app, title, workspace, and which is focused.",
    parameters: {},
    run: async () => ({ windows: (await windows()).map(({ address, ...w }) => w) }),
  },

  open_app: {
    description: "Open (launch) an app by name.",
    parameters: { name: { type: "string", description: "The app's name, e.g. Chromium, Files, Obsidian." } },
    required: ["name"],
    run: async ({ name }) => {
      const entry = best(desktopEntries(), name, ["name", "id"]);
      if (!entry) throw new Error(`No app called "${name}" is installed.`);
      launch("uwsm-app", ["--", "gtk-launch", `${entry.id}.desktop`]);
      return { opened: entry.name };
    },
  },

  focus_window: {
    description: "Switch to an open app's window (bring it into focus).",
    parameters: { app: appName },
    required: ["app"],
    run: async ({ app }) => {
      const w = await findWindow(app);
      await dispatch(`hl.dsp.focus({ window = ${lua("address:" + w.address)} })`);
      return { focused: w.app, workspace: w.workspace };
    },
  },

  close_window: {
    description: "Close an app's window. Asks the user first, since unsaved work could be lost.",
    parameters: { app: appName, confirmation_id: confirmation },
    confirm: async ({ app }) => {
      const w = await findWindow(app);
      return `Close ${w.app} (${w.title})? Anything unsaved in it could be lost.`;
    },
    run: async ({ app }) => {
      const w = await findWindow(app);
      await dispatch(`hl.dsp.window.close({ window = ${lua("address:" + w.address)} })`);
      return { closed: w.app };
    },
  },

  move_window: {
    description: "Move a window to another workspace.",
    parameters: { app: appName, workspace: ws, follow: { type: "boolean", description: "Go to that workspace with it. Default false." } },
    required: ["workspace"],
    run: async ({ app, workspace, follow }) => {
      const w = await findWindow(app);
      await dispatch(`hl.dsp.window.move({ workspace = ${lua(workspace)}, follow = ${follow ? "true" : "false"}, window = ${lua("address:" + w.address)} })`);
      return { moved: w.app, to_workspace: String(workspace) };
    },
  },

  set_window_state: {
    description: "Maximize, fullscreen, minimize (to the dock), float, or tile a window. maximize and fullscreen toggle.",
    parameters: { app: appName, state: { type: "string", enum: ["maximize", "fullscreen", "minimize", "float", "tile"] } },
    required: ["state"],
    run: async ({ app, state }) => {
      const w = await findWindow(app);
      const target = lua("address:" + w.address);
      if (state === "minimize") {
        const r = await run("omarchy-hyprland-window-minimize", [w.address]);
        if (!r.ok) throw new Error(r.err || "Couldn't minimize it.");
      } else if (state === "maximize" || state === "fullscreen") {
        await dispatch(`hl.dsp.window.fullscreen({ mode = ${lua(state === "maximize" ? "maximized" : "fullscreen")}, action = "toggle", window = ${target} })`);
      } else {
        await dispatch(`hl.dsp.window.float({ action = ${lua(state === "float" ? "on" : "off")}, window = ${target} })`);
      }
      return { window: w.app, state };
    },
  },

  side_by_side: {
    description: "Put two apps' windows side by side on the current workspace, the first on the left.",
    parameters: { left_app: { type: "string" }, right_app: { type: "string" } },
    required: ["left_app", "right_app"],
    run: async ({ left_app, right_app }) => {
      const left = await findWindow(left_app);
      const right = await findWindow(right_app);
      const monitor = (await json("hyprctl", ["monitors", "-j"])).find((m) => m.focused);
      const workspace = String(monitor.activeWorkspace.id);
      for (const w of [left, right]) await dispatch(`hl.dsp.window.move({ workspace = ${lua(workspace)}, follow = false, window = ${lua("address:" + w.address)} })`);
      // On a floating workspace each window is placed by hand; on a tiled one
      // Hyprland splits the screen between them.
      const fresh = await windows();
      const floating = [left, right].every((w) => (fresh.find((f) => f.address === w.address) || {}).floating);
      if (floating) {
        const [l, t, r, b] = monitor.reserved || [0, 0, 0, 0];
        const scale = monitor.scale || 1;
        const width = Math.round(monitor.width / scale) - l - r;
        const height = Math.round(monitor.height / scale) - t - b;
        const gap = 12;
        const half = Math.floor((width - gap * 3) / 2);
        const places = [[left, monitor.x + l + gap], [right, monitor.x + l + gap * 2 + half]];
        for (const [w, x] of places) {
          const target = lua("address:" + w.address);
          await dispatch(`hl.dsp.window.resize({ x = ${half}, y = ${height - gap * 2}, window = ${target} })`);
          await dispatch(`hl.dsp.window.move({ x = ${x}, y = ${monitor.y + t + gap}, window = ${target} })`);
        }
      }
      await dispatch(`hl.dsp.focus({ window = ${lua("address:" + left.address)} })`);
      return { left: left.app, right: right.app, workspace };
    },
  },

  switch_workspace: {
    description: "Go to a desktop (Hyprland) workspace. Not for Herdr workspaces: use herdr_focus for those.",
    parameters: { workspace: ws },
    required: ["workspace"],
    run: async ({ workspace }) => {
      await dispatch(`hl.dsp.focus({ workspace = ${lua(workspace)} })`);
      return { workspace: String(workspace) };
    },
  },

  set_workspace_layout: {
    description: "Set a workspace's layout: tiled, scrolling, or floating. Leave out the workspace for the current one.",
    parameters: { workspace: ws, layout: { type: "string", enum: ["tiled", "scrolling", "floating"] } },
    required: ["layout"],
    run: async ({ workspace, layout }) => {
      const id = String(workspace || (await json("hyprctl", ["activeworkspace", "-j"])).id);
      if (!/^\d+$/.test(id)) throw new Error("That workspace can't take a layout.");
      const mode = layout === "tiled" ? "dwindle" : layout;
      const apply = `o.workspace_mode({ workspace = ${lua(id)}, mode = ${lua(mode)} })`;
      const r = await run("hyprctl", ["eval", apply]);
      if (!r.ok) throw new Error(r.err || "Hyprland didn't take the layout.");
      // Saved the way Omarchy's layout key saves it, so it comes back at login;
      // a workspace on the default layout simply follows the default.
      const dir = path.join(process.env.XDG_STATE_HOME || path.join(HOME, ".local", "state"), "omarchy", "workspace-layouts");
      const def = (await run("omarchy-hyprland-workspace-layout-default")).out;
      if (mode === def) fs.rmSync(path.join(dir, `${id}.lua`), { force: true });
      else {
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, `${id}.lua`), apply + "\n");
      }
      await run("omarchy-shell", ["-q", "omarchy.workspaces", "refresh"]);
      await run("omarchy-shell", ["-q", "omarchy.dock", "refresh"]);
      return { workspace: id, layout };
    },
  },

  set_volume: {
    description: "Set the speaker volume to a level, turn it up or down, or mute/unmute.",
    parameters: {
      level: { type: "number", description: "0 to 100." },
      change: { type: "string", enum: ["up", "down"] },
      mute: { type: "string", enum: ["on", "off", "toggle"] },
    },
    run: async ({ level, change, mute }) => {
      const sink = "@DEFAULT_AUDIO_SINK@";
      if (typeof level === "number") await run("wpctl", ["set-volume", sink, `${Math.max(0, Math.min(100, Math.round(level)))}%`]);
      if (change) await run("omarchy-audio-output-volume", [change === "up" ? "raise" : "lower"]);
      if (mute) await run("wpctl", ["set-mute", sink, mute === "toggle" ? "toggle" : mute === "on" ? "1" : "0"]);
      return { volume: (await run("wpctl", ["get-volume", sink])).out };
    },
  },

  set_brightness: {
    description: "Set the screen brightness to a level, or turn it up or down.",
    parameters: { level: { type: "number", description: "1 to 100." }, change: { type: "string", enum: ["up", "down"] } },
    run: async ({ level, change }) => {
      const arg = typeof level === "number" ? `${Math.max(1, Math.min(100, Math.round(level)))}%` : change === "down" ? "10%-" : "+10%";
      const r = await run("omarchy-brightness-display", [arg]);
      if (!r.ok) throw new Error(r.err || "Couldn't change the brightness.");
      return { brightness: arg };
    },
  },

  set_wifi: {
    description: "Turn Wi-Fi on or off.",
    parameters: { on: { type: "boolean" } },
    required: ["on"],
    run: async ({ on }) => {
      const r = await run("nmcli", ["radio", "wifi", on ? "on" : "off"]);
      if (!r.ok) throw new Error(r.err || "Couldn't switch Wi-Fi.");
      return { wifi: on ? "on" : "off" };
    },
  },

  set_bluetooth: {
    description: "Turn Bluetooth on or off.",
    parameters: { on: { type: "boolean" } },
    required: ["on"],
    run: async ({ on }) => {
      const r = await run("omarchy-bluetooth-power", [on ? "on" : "off"]);
      if (!r.ok) throw new Error(r.err || "Couldn't switch Bluetooth.");
      return { bluetooth: on ? "on" : "off" };
    },
  },

  set_do_not_disturb: {
    description: "Turn do-not-disturb (notifications silenced) on or off.",
    parameters: { on: { type: "boolean" } },
    required: ["on"],
    run: async ({ on }) => ({ do_not_disturb: (await run("omarchy-shell", ["notifications", "setDnd", on ? "on" : "off"])).out || (on ? "on" : "off") }),
  },

  set_night_light: {
    description: "Turn the night light (warmer screen) on or off.",
    parameters: { on: { type: "boolean" } },
    required: ["on"],
    run: async ({ on }) => {
      const now = JSON.parse((await run("omarchy-toggle-nightlight", ["--status"])).out || "{}").enabled === true;
      if (now !== on) await run("omarchy-toggle-nightlight");
      return { night_light: on ? "on" : "off" };
    },
  },

  lock_screen: {
    description: "Lock the screen. Asks the user first.",
    parameters: { confirmation_id: confirmation },
    confirm: async () => "Lock the screen now?",
    run: async () => {
      launch("omarchy-system-lock", []);
      return { locked: true };
    },
  },

  list_themes: {
    description: "List the Omarchy themes that can be switched to, and the current one.",
    parameters: {},
    run: async () => ({
      themes: (await run("omarchy-theme-list")).out.split("\n").filter(Boolean),
      current: (await run("omarchy-theme-current")).out,
    }),
  },

  set_theme: {
    description: "Switch the Omarchy theme. Use list_themes for the names.",
    parameters: { name: { type: "string" } },
    required: ["name"],
    run: async ({ name }) => {
      const themes = (await run("omarchy-theme-list")).out.split("\n").filter(Boolean);
      const theme = best(themes.map((t) => ({ t })), name, ["t"]);
      if (!theme) throw new Error(`No theme called "${name}".`);
      const r = await run("omarchy-theme-set", [theme.t], 60000);
      if (!r.ok) throw new Error(r.err || "The theme didn't apply.");
      return { theme: theme.t };
    },
  },

  next_wallpaper: {
    description: "Switch to the next wallpaper of the current theme.",
    parameters: {},
    run: async () => {
      await run("omarchy-theme-bg-next");
      return { done: true };
    },
  },

  open_app_drawer: {
    description: "Open the app drawer (the grid of all apps).",
    parameters: {},
    run: async () => {
      await run("omarchy-shell", ["-q", "omarchy.dock", "apps"]);
      return { done: true };
    },
  },

  take_screenshot: {
    description: "Take a screenshot of the whole screen and save it. Returns where it was saved.",
    parameters: {},
    run: async () => {
      const started = Date.now() - 1000;
      const r = await run("omarchy-capture-screenshot", ["fullscreen", "save"], 20000);
      if (!r.ok) throw new Error(r.err || "The screenshot failed.");
      // The tool doesn't say where it saved; the newest file in its folder is it.
      const latest = latestScreenshot();
      return { saved: latest && latest.at >= started ? shortPath(latest.file) : `in ${shortPath(SCREENSHOTS)}` };
    },
  },

  screen_recording: {
    description: "Start or stop recording the screen.",
    parameters: { action: { type: "string", enum: ["start", "stop"] } },
    required: ["action"],
    run: async ({ action }) => {
      if (action === "stop") await run("omarchy-capture-screenrecording", ["--stop-recording"], 20000);
      else launch("omarchy-capture-screenrecording", ["--fullscreen"]);
      return { recording: action === "start" };
    },
  },

  write_file: {
    description:
      "Write text to a file in the user's home folder. mode create makes a new file (fails if it exists), append adds to the end (creating it if needed), replace overwrites it (asks the user first). Paths are relative to the home folder unless they start with ~ or /home.",
    parameters: {
      path: { type: "string" },
      text: { type: "string" },
      mode: { type: "string", enum: ["create", "append", "replace"] },
      open: { type: "boolean", description: "Open the file afterwards so the user sees it. Default true." },
      confirmation_id: confirmation,
    },
    required: ["path", "text", "mode"],
    confirm: async ({ path: p, mode }) => (mode === "replace" && fs.existsSync(homePath(p)) ? `Replace everything in ${p}?` : null),
    run: async ({ path: p, text, mode, open }) => {
      const full = homePath(p);
      fs.mkdirSync(path.dirname(full), { recursive: true });
      if (mode === "create" && fs.existsSync(full)) throw new Error(`${p} already exists: append to it, or replace it (which asks first).`);
      if (mode === "create") fs.writeFileSync(full, text, { flag: "wx" });
      else if (mode === "append") fs.appendFileSync(full, (fs.existsSync(full) && fs.statSync(full).size > 0 ? "\n" : "") + text);
      else fs.writeFileSync(full, text);
      if (open !== false) launch("xdg-open", [full]);
      return { file: full.replace(HOME, "~"), mode, characters: text.length };
    },
  },

  open_file: {
    description: "Open a file in the user's home folder with its usual app.",
    parameters: { path: { type: "string" } },
    required: ["path"],
    run: async ({ path: p }) => {
      const full = homePath(p);
      if (!fs.existsSync(full)) throw new Error(`There's no file at ${p}.`);
      launch("xdg-open", [full]);
      return { opened: full.replace(HOME, "~") };
    },
  },

  notes: appAction(
    "uber-notebook",
    "Uber Notebook, the user's notes app: find, read and write pages, to-dos, the calendar and People. To write something down, add a page (it goes in the Inbox) or append to one found with find. To tick a to-do, read its page's blocks for the block id.",
    NOTES,
  ),

  tv: appAction(
    "om-pg",
    "Uber TV, the user's TV and media center for YouTube channels and IPTV: find and play anything (search, the movie and series library, play on demand, the user's own videos), channels (list, add playlists or YouTube channels, rename, categories, what the guide shows), live TV (watch, Multiview, pause and rewind, record), its look (themes, colors, styles, fonts, pictures, snapshots), Home, the nav rail, apps and phone remotes. To watch something by name or topic ('watch news', 'put on CNN'), find the channel yourself with channels \"<words>\" or search \"<words>\" and watch its number: never ask the user for a channel number. open, watch and multiview put the guide over the whole screen; say Esc or Super+Alt+T closes it. After a reset, say reset undo brings it back. Use state to see what is on.",
    TV,
    " Locked channels can only be unlocked by the user with their passcode. For how a command works, search the guide: app_guide with find.",
  ),

  hill: appAction(
    "marcho78.hillchart",
    "Hill Chart, the user's projects as dots on a hill on the bar: 0-49% uphill (figuring the work out), 50% the top (nothing unknown left), 51-99% downhill (doing it), 100% done. list gives each project's progress, phase, stale (hasn't moved for a week: stuck) and when it last moved. toggle opens or closes its panel; peek shows the hover card for a few seconds. To mark a project done, move it to 100.",
    HILL,
  ),

  app_guide: {
    description: "The full guide for Uber Notebook (notes), Uber TV (tv) or Hill Chart (hill): how its commands work, in detail. Read it before an unusual request. find: words to look for, which returns only the sections that have them all (best for a long guide); else part, from 1.",
    parameters: {
      app: { type: "string", enum: ["notes", "tv", "hill"] },
      find: { type: "string", description: "Words the sections must contain, e.g. 'IPTV playlist'." },
      part: { type: "number", description: "Which part, from 1, for a long guide." },
    },
    required: ["app"],
    run: async ({ app, part, find }) => {
      const text = fs.readFileSync(GUIDES[app], "utf8");
      if (find && String(find).trim()) {
        // The sections (from one heading to the next) that have every word.
        const words = String(find).toLowerCase().split(/\s+/).filter(Boolean);
        const sections = text.split(/\n(?=#{1,4} )/);
        const hits = sections.filter((sec) => words.every((w) => sec.toLowerCase().includes(w)));
        if (!hits.length) return { found: 0, text: `Nothing in the guide has all of: ${find}.` };
        const joined = hits.join("\n\n");
        return { found: hits.length, text: joined.length > LONG ? joined.slice(0, LONG) + "\n… (cut; search for something narrower)" : joined };
      }
      const parts = Math.ceil(text.length / LONG);
      const n = Math.max(1, Math.min(parts, Math.round(part || 1)));
      return { part: n, of: parts, text: text.slice((n - 1) * LONG, n * LONG) };
    },
  },

  open_url: {
    description:
      "Open a web address, or search the web, in the user's browser. Give a URL (youtube.com, https://...) or plain words to search Google for.",
    parameters: { target: { type: "string", description: "A web address, or what to search for." } },
    required: ["target"],
    run: async ({ target }) => {
      const text = String(target || "").trim();
      if (!text) throw new Error("Nothing to open.");
      // An address is one word with a dot in it (example.com, docs.x.ai/path)
      // or a full http(s) link; anything else is searched.
      let url;
      if (/^https?:\/\/\S+$/i.test(text)) url = text;
      else if (/^[\w-]+(\.[\w-]+)+(\/\S*)?$/.test(text)) url = `https://${text}`;
      else url = `https://www.google.com/search?q=${encodeURIComponent(text)}`;
      launch("xdg-open", [url]);
      return { opened: url };
    },
  },

  press_keys: {
    description:
      "Press keys or shortcuts in the focused window, in order, e.g. [\"ctrl+l\"] for the address bar, [\"enter\"], [\"ctrl+t\"] for a new tab, [\"tab\",\"tab\"]. Keys: letters, digits, enter, tab, escape, backspace, delete, space, up, down, left, right, home, end, pageup, pagedown, f1 to f12, with ctrl, shift, alt, super. Asks the user first when the focused window is a terminal.",
    parameters: { keys: { type: "array", items: { type: "string" } }, confirmation_id: confirmation },
    required: ["keys"],
    confirm: async () => {
      const w = await findWindow();
      return TERMINALS.test(w.app) ? `The focused window is a terminal (${w.app}); pressing keys there could run commands. Go ahead?` : null;
    },
    run: async ({ keys }) => {
      const list = Array.isArray(keys) ? keys : [keys];
      if (list.length === 0 || list.length > 30) throw new Error("Give between 1 and 30 keys.");
      for (const combo of list) {
        const args = comboArgs(combo);
        const r = await run("wtype", args);
        if (!r.ok) throw new Error(r.err || `Couldn't press ${combo}.`);
      }
      return { pressed: list };
    },
  },

  type_text: {
    description: "Type text into the focused window, as if from the keyboard. Asks the user first when that window is a terminal, where a line could run as a command.",
    parameters: { text: { type: "string" }, confirmation_id: confirmation },
    required: ["text"],
    confirm: async () => {
      const w = await findWindow();
      return TERMINALS.test(w.app) ? `The focused window is a terminal (${w.app}); typing there could run commands. Type it anyway?` : null;
    },
    run: async ({ text }) => {
      const r = await run("wtype", ["--", text], 60000);
      if (!r.ok) throw new Error(r.err || "Typing failed.");
      return { typed: text.length };
    },
  },

  show_on_desktop: {
    description:
      "Put a list on the user's desktop wallpaper, as glowing text that decodes line by line: news, search results, a to-do list, events, agents' tasks. Use it when they ask to see, show, list or put something on screen. Short lines (one sentence each), each with an optional tag (a source or category, e.g. REUTERS, TODO). It replaces what was there and clears itself after 10 minutes unless pin is true. Say a one-line summary out loud, not the whole list.",
    parameters: {
      title: { type: "string", description: "A few words, e.g. 'News brief'." },
      items: {
        type: "array",
        items: { type: "object", properties: { text: { type: "string" }, tag: { type: "string" } }, required: ["text"] },
      },
      pin: { type: "boolean", description: "Keep it until the user clears it." },
    },
    required: ["title", "items"],
    run: async ({ title, items, pin }) => {
      const list = (Array.isArray(items) ? items : [])
        .map((i) => ({ text: String(i?.text || "").trim().slice(0, 160), tag: String(i?.tag || "").trim().toUpperCase().slice(0, 14) }))
        .filter((i) => i.text)
        .slice(0, 12);
      if (!list.length) throw new Error("Nothing to show.");
      showBoard({ title: String(title || "").trim().slice(0, 40) || "Trinity", items: list, pinned: pin === true });
      return { shown: list.length, pinned: pin === true };
    },
  },

  desktop_widgets: {
    description:
      "Show or hide the desktop widgets: system (the HUD's CPU, memory and network panel), usage (the HUD's AI usage and cost panel), hud (both), radar (the Agent Radar: Herdr agents), video (the video on the desktop), list (the list you put on the desktop), or all (everything at once, for a clean screen). A hidden widget leaves a small tab at the screen's edge that brings it back; all hides the tabs too.",
    parameters: {
      widget: { type: "string", enum: ["system", "usage", "hud", "radar", "video", "list", "all"] },
      show: { type: "boolean" },
    },
    required: ["widget", "show"],
    run: async ({ widget, show }) => {
      const tool = path.join(HOME, ".local", "bin", "o-widgets");
      const args = widget === "all" ? ["clean", show ? "off" : "on"] : [show ? "show" : "hide", widget === "list" ? "brief" : widget];
      if (widget === "all" && show) {
        // Bringing everything back also undoes single hides.
        for (const w of ["system", "usage", "radar", "brief", "video"]) await run(tool, ["show", w]);
      }
      const r = await run(tool, args);
      if (!r.ok) throw new Error(r.err || "The widgets didn't change.");
      return { widget, shown: show };
    },
  },

  play_video: {
    description:
      "Play a YouTube video on the user's desktop: a panel between the Agent Radar and the HUD, which can go full screen or pop out into a floating window. query: what to search YouTube for, or a YouTube link. newest: true for the latest upload of the channel the query names ('the newest Kurzgesagt video'). Say the title and how long it is, never the link.",
    parameters: { query: { type: "string" }, newest: { type: "boolean" } },
    required: ["query"],
    run: async ({ query, newest }) => {
      const video = await findVideo(String(query || "").trim(), newest === true);
      videoHook({ type: "play", video });
      return { playing: video.title, channel: video.channel, minutes: Math.round(video.duration / 60) };
    },
  },

  video_control: {
    description:
      "Control the video playing on the desktop: pause, resume, stop, louder, quieter, forward or back (by seconds, default 60), full_screen, window (pop it out into a floating window in front of everything), or panel (back onto the desktop).",
    parameters: {
      command: { type: "string", enum: ["pause", "resume", "stop", "louder", "quieter", "forward", "back", "full_screen", "window", "panel"] },
      seconds: { type: "number" },
    },
    required: ["command"],
    run: async ({ command, seconds }) => {
      videoHook({ type: "control", command, seconds: Math.max(1, Math.round(Number(seconds) || 60)) });
      return { done: command };
    },
  },

  clear_desktop: {
    description: "Take the list Trinity put on the desktop off it ('clear the screen').",
    parameters: {},
    run: async () => {
      showBoard(null);
      return { cleared: true };
    },
  },

  // Reading what's on screen: captured into memory, its text recognized on
  // this computer, and only the text handed back. Not written to the log.
  read_screen: {
    description:
      "Read the text on the screen: the window in front (default) or the whole screen. For 'read my first email', 'what does this say?', 'read this error'. Only what's visible: to read more of a long page, scroll (press_keys) and read again.",
    parameters: { area: { type: "string", enum: ["window", "screen"] } },
    private: true,
    run: async ({ area }) => {
      let args = ["-"];
      let from = "the whole screen";
      if (area !== "screen") {
        const w = await json("hyprctl", ["activewindow", "-j"]).catch(() => null);
        if (w && w.size) {
          args = ["-g", `${w.at[0]},${w.at[1]} ${w.size[0]}x${w.size[1]}`, "-"];
          from = w.class || "the window";
        }
      }
      const image = await pipe("grim", args);
      return { read_from: from, ...(await readImage(image)) };
    },
  },

  read_screenshot: {
    description: "Read the text in a saved screenshot or picture: 'latest' (the newest screenshot, the default) or a file path in the home folder.",
    parameters: { file: { type: "string" } },
    private: true,
    run: async ({ file }) => {
      let full;
      if (!file || file === "latest") {
        const latest = latestScreenshot();
        if (!latest) throw new Error(`There are no screenshots in ${shortPath(SCREENSHOTS)}.`);
        full = latest.file;
      } else full = homePath(file);
      return { file: shortPath(full), ...(await readImage(fs.readFileSync(full))) };
    },
  },

  // Herdr, the terminal workspace manager the user runs coding agents in.
  // Read-only: what each agent is on, and an agent's recent terminal output.
  herdr_overview: {
    description:
      "List the user's Herdr workspaces and the coding agents (Claude, Codex) in each: whether each is working or idle, its project folder and the title of what it's on. For 'what are my agents doing?', 'is anything still working?'.",
    parameters: {},
    run: async () => {
      const workspaces = (await herdr(["workspace", "list"])).workspaces || [];
      const agents = (await herdr(["agent", "list"])).agents || [];
      return {
        workspaces: workspaces.map((w) => ({
          name: w.label,
          number: w.number,
          status: w.agent_status,
          focused: w.focused,
          agents: agents
            .filter((a) => a.workspace_id === w.workspace_id)
            .map((a) => ({ id: a.pane_id, agent: a.agent, status: a.agent_status, task: a.terminal_title_stripped, folder: shortPath(a.cwd) })),
        })),
      };
    },
  },

  herdr_read_agent: {
    description:
      "Read the last part of one Herdr agent's terminal, to tell the user where it got to or what it's asking. agent: its id from herdr_overview, or words from its task, workspace or folder.",
    parameters: { agent: { type: "string" }, lines: { type: "number", description: "How many lines, 10 to 200 (default 40)." } },
    required: ["agent"],
    run: async ({ agent, lines }) => {
      const workspaces = (await herdr(["workspace", "list"])).workspaces || [];
      const agents = ((await herdr(["agent", "list"])).agents || []).map((a) => ({
        ...a,
        workspace: (workspaces.find((w) => w.workspace_id === a.workspace_id) || {}).label || "",
      }));
      const found = agents.find((a) => a.pane_id === agent) || best(agents, agent, ["terminal_title_stripped", "workspace", "cwd"]);
      if (!found) throw new Error(`No Herdr agent matches "${agent}".`);
      const n = Math.max(10, Math.min(200, Math.round(Number(lines) || 40)));
      const r = await run(HERDR, ["agent", "read", found.pane_id, "--lines", String(n)]);
      if (!r.ok) throw new Error(r.err || "Herdr couldn't read it.");
      return {
        agent: { id: found.pane_id, agent: found.agent, status: found.agent_status, task: found.terminal_title_stripped, workspace: found.workspace },
        output: r.out.replace(/[─━]{10,}/g, "").replace(/\n{3,}/g, "\n\n").slice(-6000),
      };
    },
  },

  herdr_focus: {
    description:
      "Switch Herdr to one of its workspaces or agents and bring the Herdr window to the front. For 'focus on nvidia', 'take me to the Lenovo agent'. Herdr workspaces are not desktop workspaces: never use switch_workspace for them. target: a Herdr workspace name or number, an agent id from herdr_overview, or words from an agent's task.",
    parameters: { target: { type: "string" } },
    required: ["target"],
    run: async ({ target }) => {
      const workspaces = (await herdr(["workspace", "list"])).workspaces || [];
      const agents = (await herdr(["agent", "list"])).agents || [];
      const want = String(target || "").trim();
      const workspace = workspaces.find((w) => String(w.number) === want) || best(workspaces, want, ["label"]);
      const agent = agents.find((a) => a.pane_id === want) || (!workspace && best(agents, want, ["terminal_title_stripped", "cwd"]));
      let focused;
      if (agent) {
        await herdr(["agent", "focus", agent.pane_id]);
        focused = { agent: agent.terminal_title_stripped, workspace: (workspaces.find((w) => w.workspace_id === agent.workspace_id) || {}).label };
      } else if (workspace) {
        await herdr(["workspace", "focus", workspace.workspace_id]);
        focused = { workspace: workspace.label };
      } else throw new Error(`No Herdr workspace or agent matches "${target}".`);
      const app = await raiseHerdr();
      return { ...focused, window: app || "no Herdr window found to bring forward" };
    },
  },

  herdr: {
    description:
      "Do anything in Herdr, where the user's coding agents run (Herdscope is its window): create, rename, switch to and close workspaces and tabs; split, read, zoom, resize, move and close panes, run a command or type in one; start an agent (kinds include claude, codex, grok) in a pane, give it a task, read it, press keys in it (e.g. to interrupt), rename it; Git worktrees; notifications; sessions; integrations. command: the group and command, e.g. 'workspace create'; args: everything after it, as Herdr's CLI takes it (e.g. ['--label', 'Video', '--cwd', '/home/user/projects/app']). Check options with herdr_help first when unsure; ids come from herdr_overview or a list command, and a create returns the new pane's id. To start an agent somewhere new: create the workspace or tab, then 'agent start' NAME --kind claude --pane PANE_ID. Closing, removing, deleting or stopping, running or typing in a pane, pressing keys in an agent, giving an agent a task, and installing or removing integrations ask the user first.",
    parameters: {
      command: { type: "string", enum: Object.keys(HERDR_COMMANDS) },
      args: { type: "array", items: { type: "string" } },
      confirmation_id: confirmation,
    },
    required: ["command"],
    confirm: async ({ command, args }) => {
      const ask = HERDR_COMMANDS[command];
      return ask ? ask((args || []).map(String)) : null;
    },
    run: async ({ command, args }) => {
      if (!(command in HERDR_COMMANDS)) throw new Error(`${command} isn't a Herdr command Trinity can use.`);
      const given = (args || []).map(String);
      // Waiting on an agent or for output can take a while.
      const slow = /^(agent (start|prompt|wait)|pane wait-output)$/.test(command);
      const r = await run(HERDR, [...command.split(" "), ...given], slow ? 180000 : 20000);
      const text = (r.out || r.err || "").trim();
      let answer;
      try {
        answer = JSON.parse(text);
      } catch {
        answer = { text: text.length > LONG ? text.slice(0, LONG) + "\n… (cut)" : text };
      }
      if (!r.ok || (answer && answer.error)) throw new Error((answer && answer.error && answer.error.message) || text || `${herdrLine(command, given)} failed.`);
      const result = answer && answer.result !== undefined ? answer.result : answer;
      if (HERDR_SHOWS.includes(command) && !given.includes("--no-focus")) await raiseHerdr();
      return { result };
    },
  },

  herdr_help: {
    description:
      "Herdr's own help. With command (e.g. 'workspace create', 'agent start', 'agent prompt'): its options, from `herdr <command> --help`. Without: Herdr's guide for AI agents, on layouts, panes and agents, starting and prompting an agent, and its safety rules. Read it before a Herdr command whose options you're not sure of.",
    parameters: { command: { type: "string" } },
    run: async ({ command }) => {
      const parts = String(command || "").trim().split(/\s+/).filter(Boolean);
      if (parts.length && !/^[a-z-]+$/.test(parts.join(""))) throw new Error("That isn't a Herdr command.");
      const r = await run(HERDR, parts.length ? [...parts, "--help"] : ["--skill"], 20000);
      const text = (r.out || r.err || "").trim();
      if (!text) throw new Error("Herdr gave no help for that.");
      return { help: text.length > LONG ? text.slice(0, LONG) + "\n… (cut)" : text };
    },
  },

  // Memory (memory.mjs): only what the user asks to keep.
  remember: {
    description:
      "Save something lasting about the user for later conversations: a preference or a fact they want kept. Only when they ask you to remember it, or say yes after you offer (offer when they mention a lasting preference). One short sentence, e.g. 'Prefers short answers'.",
    parameters: { text: { type: "string" } },
    required: ["text"],
    run: async ({ text }) => {
      if (!String(text || "").trim()) throw new Error("Nothing to remember.");
      return { remembered: remember(text) };
    },
  },

  recall: {
    description: "List everything you remember about the user, with ids. For 'what do you remember about me?'.",
    parameters: {},
    run: async () => ({ memories: memories() }),
  },

  forget: {
    description:
      "Forget something you remember. item: 'last' for the last thing saved ('forget that'), an id, or words from it. If several match, ask the user which. all: true forgets everything (asks the user first).",
    parameters: { item: { type: "string" }, all: { type: "boolean" }, confirmation_id: confirmation },
    confirm: async ({ all }) => (all ? `Forget everything I remember about you (${memories().length} ${memories().length === 1 ? "thing" : "things"})?` : null),
    run: async ({ item, all }) => {
      if (all) return { forgotten: forgetAll() };
      const found = find(item);
      if (!found.length) throw new Error(`Nothing I remember matches "${item}".`);
      if (found.length > 1) return { ambiguous: true, matches: found, instructions: "Ask the user which one, then call forget with its id." };
      return { forgotten: forget(found.map((i) => i.id)) };
    },
  },
};

// The tool definitions the agent is given.
export function tools() {
  return Object.entries(ACTIONS).map(([name, a]) => ({
    type: "function",
    name,
    description: a.description,
    parameters: { type: "object", properties: a.parameters, required: a.required || [] },
  }));
}

// ---------------------------------------------------------------- confirmations and the log

// Questions waiting on the user: id -> {name, args, userTurnAt}.
const pending = new Map();
let userTurns = 0;

// Called whenever the user speaks or types, so a yes can count.
export function userSpoke() {
  userTurns++;
}

function log(entry) {
  try {
    fs.mkdirSync(path.dirname(LOG), { recursive: true });
    fs.appendFileSync(LOG, `${new Date().toISOString()} ${JSON.stringify(entry)}\n`);
  } catch {}
}

// Runs an action for the agent and returns what to tell it.
export async function perform(name, rawArgs) {
  const action = ACTIONS[name];
  let args = {};
  try {
    args = rawArgs ? JSON.parse(rawArgs) : {};
  } catch {
    return { error: "The arguments weren't valid JSON." };
  }
  if (!action) return { error: `There's no action called ${name}.` };

  try {
    if (action.confirm) {
      const id = args.confirmation_id;
      const asked = id && pending.get(id);
      if (asked && asked.name === name && userTurns > asked.userTurnAt) {
        pending.delete(id);
      } else {
        const question = await action.confirm(args);
        if (question) {
          const newId = Math.random().toString(36).slice(2, 10);
          pending.set(newId, { name, userTurnAt: userTurns });
          log({ action: name, args: redact(args), result: "asked", question });
          return {
            status: "needs_confirmation",
            question,
            confirmation_id: newId,
            instructions: "Ask the user this question and wait. Only if they clearly say yes, call this action again with the same arguments and this confirmation_id.",
          };
        }
      }
    }
    const result = await action.run(args);
    log({ action: name, args: redact(args), result: "done", detail: action.private ? "(not logged)" : result });
    return { status: "done", ...result };
  } catch (err) {
    log({ action: name, args: redact(args), result: "failed", error: err.message });
    return { status: "failed", error: err.message };
  }
}

// Long text isn't copied into the log whole.
function redact(args) {
  const out = { ...args };
  if (typeof out.text === "string" && out.text.length > 120) out.text = out.text.slice(0, 120) + `… (${args.text.length} characters)`;
  return out;
}
