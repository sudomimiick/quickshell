pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.common

// The app launcher (replaces fuzzel).
//
// Why it's fast: nothing happens on a keystroke except string compares in memory.
// Desktop entries are indexed once (again only when apps are installed or removed),
// lowercased and pre-split for word boundaries. Typing forward only re-scores what
// the previous keystroke matched; anything typed before (and "" plus a–z, worked
// out in the background) is a lookup. The window has a fixed set of rows that just
// re-bind — no delegates to create, no model diffs, no disk, no processes. Opening
// costs no process either: Hyprland pings the shell over the global-shortcuts protocol.
//
// Hyprland (hyprland.lua):
//   hl.bind("SUPER + D", hl.dsp.global("quickshell:launcher"))
// Anywhere else (a bar button, a script):
//   qs ipc call launcher toggle
//   qs ipc call launcher search "="     straight into the calculator
//   qs ipc call launcher search ">"     straight into run-a-command
//
// Ranking is fzf-style on the name (exact > whole word > prefix > word start > fuzzy,
// where fuzzy rewards initials like "vsc"), plus the desktop id, generic name, keywords,
// binary and comment — then nudged by how often and how recently you launched each app
// (kept in ~/.local/state/quickshell/…; seeded from fuzzel's history on first start).
Singleton {
    id: root

    // ── what the window shows ───────────────────────────────────────────────
    property bool active: false
    property string screenName: ""
    property string query: ""
    property string mode: "apps"                 // apps | calc | run
    property var results: []
    property int selected: 0
    property int scroll: 0
    readonly property int lines: Math.max(1, Config.launcher.lines)

    // ── the index ───────────────────────────────────────────────────────────
    property var apps: []                         // one record per desktop entry, see makeApp()
    property var actions: []                      // desktop actions, searchable on their own
    property var icons: []                        // every icon the index uses (for the warm-up)
    property var pool: []                         // apps + actions, what a query searches
    property var memo: ({})                       // query → results (kept until a launch or an hour)
    property int memoCount: 0
    property real memoAt: 0
    property var narrow: null                     // the last search, to narrow the next one
    property int warmIndex: 26                    // a–z precomputed in the background (26 = done)
    readonly property int total: apps.length

    // ── memory ──────────────────────────────────────────────────────────────
    property var stats: ({})                      // key → { n: launches, t: last launch, unix s }
    property var runs: []                         // "> commands", newest first
    property bool importFuzzel: false

    property string detectedTerminal: ""
    readonly property string home: String(Quickshell.env("HOME") ?? "")
    readonly property string fuzzelCache: String(Quickshell.env("XDG_CACHE_HOME") || root.home + "/.cache") + "/fuzzel"
    readonly property string hlColor: "#c4b9ec" // matched letters: soft lavender and bold, against the softer rest

    // scratch space for the fuzzy matcher, reused on every call (32 query × 64 text chars)
    readonly property var dpScore: new Float64Array(32 * 64)
    readonly property var dpFrom: new Int16Array(32 * 64)

    // ── open / close ────────────────────────────────────────────────────────

    function open(text) {
        Drawers.close();
        Session.close();
        if (!root.apps.length)
            root.rebuild();
        root.screenName = root.focusedScreenName();
        root.query = String(text ?? "");
        // results only change when you launch something (or apps change), so keep the
        // memo across openings — but let recency catch up after an hour
        if (Date.now() - root.memoAt > 3600000 || root.memoCount > 400)
            root.forget();
        root.narrow = null;
        root.compute();
        root.active = true;
    }

    function close() {
        root.active = false;
    }

    function toggle() {
        if (root.active)
            root.close();
        else
            root.open("");
    }

    function setQuery(q) {
        if (q === root.query)
            return;
        root.query = q;
        root.compute();
    }

    function focusedScreenName() {
        const want = Hyprland.focusedMonitor?.name ?? "";
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === want)
                return want;
        return Scaling.primary?.name ?? (screens.length ? screens[0].name : "");
    }

    // ── results ─────────────────────────────────────────────────────────────

    function compute() {
        const q = root.query;
        const cfg = Config.launcher;
        let mode = "apps";
        let res;
        if (cfg.runCommands && q.startsWith(">")) {
            mode = "run";
            res = root.runRows(q.slice(1).trim());
        } else if (cfg.calculator && q.startsWith("=")) {
            mode = "calc";
            res = root.calcRows(q.slice(1), true);
        } else {
            res = root.calcRows(q, false).concat(root.search(q));
        }
        root.mode = mode;
        root.results = res;
        root.selected = 0;
        root.scroll = 0;
    }

    // Typing forward only ever narrows the list, so each keystroke re-scores just the
    // previous matches; backspace, and any query you've typed before, is a lookup.
    function search(q) {
        const ql = q.toLowerCase().trim();
        const hit = root.memo[ql];
        if (hit) {
            root.narrow = hit;
            return hit.out;
        }
        const toks = ql.split(/\s+/).filter(t => t.length > 0);
        const nowS = Date.now() / 1000;
        const out = [];
        const matched = [];
        if (!toks.length) {
            // empty query: everything, most used first (fuzzel order), then A→Z
            for (const a of root.apps)
                out.push(root.row(a, [], root.boost(a, nowS)));
        } else {
            // (comments are only searched for words of 3+ letters, so the keystroke that
            // makes a word 3 long has to look at everything once more)
            const prev = root.narrow;
            const narrowed = prev && prev.n > 0 && ql.startsWith(prev.q) && !(prev.lastLen < 3 && toks[prev.n - 1].length >= 3);
            const pool = narrowed ? prev.matched : Config.launcher.showActions ? root.pool : root.apps;
            for (const a of pool) {
                const m = root.scoreItem(a, toks);
                if (!m)
                    continue;
                matched.push(a); // still a candidate for the next keystroke…
                if (a.needsName && !m.nameHit)
                    continue; // …but an action shows only once a word hits its own name
                out.push(root.row(a, m.pos, m.score * (a.kind === "action" ? 0.92 : 1) + root.boost(a, nowS)));
            }
        }
        // ties: the shorter name is the closer match; with no query, plain A→Z
        const byName = (x, y) => x.ref.nameL < y.ref.nameL ? -1 : x.ref.nameL > y.ref.nameL ? 1 : 0;
        if (toks.length)
            out.sort((x, y) => y.score - x.score || x.ref.nameL.length - y.ref.nameL.length || byName(x, y));
        else
            out.sort((x, y) => y.score - x.score || byName(x, y));
        const entry = {
            q: ql,
            out: out,
            matched: matched,
            n: toks.length,
            lastLen: toks.length ? toks[toks.length - 1].length : 0
        };
        root.memo[ql] = entry;
        root.memoCount++;
        root.narrow = entry;
        return out;
    }

    function forget() {
        root.memo = {};
        root.memoCount = 0;
        root.memoAt = Date.now();
        root.narrow = null;
        root.warmIndex = 0;
    }

    function row(a, pos, score) {
        return {
            kind: a.kind,
            title: a.name,
            sub: a.sub,
            icon: a.icon,
            glyph: "",
            accent: a.accent,
            pos: pos,
            score: score,
            ref: a
        };
    }

    // Every query word must match somewhere; the best field wins for each word.
    // Letters matched in the name are highlighted even when another field scored
    // higher ("vsc" lights up V·S·C although the keyword "vscode" is the better hit).
    function scoreItem(a, toks) {
        let total = 0;
        let nameHit = false;
        let pos = [];
        for (const t of toks) {
            let best = 0;
            const r = root.matchField(a.nameL, a.nameB, t, true);
            if (r) {
                best = r.score;
                pos = pos.concat(r.pos ?? root.range(r.at, t.length));
                nameHit = true;
            }
            for (const f of a.fields) {
                if (best >= 1000 * f.w || (f.wordOnly && t.length < 3))
                    continue;
                const x = root.matchField(f.s, null, t, false);
                if (x && (!f.wordOnly || x.word) && x.score * f.w > best)
                    best = x.score * f.w;
            }
            if (best <= 0)
                return null;
            total += best;
        }
        return {
            score: total / toks.length,
            pos: pos,
            nameHit: nameHit
        };
    }

    // 1000 exact · 850–940 prefix · 700–790 word start · then, for the name, an fzf-style
    // fuzzy score of 100–600 (initials like "vsc" score high, a stray mid-word run low);
    // other fields have no fuzzy step and take a mid-word substring as 500+.
    function matchField(s, b, t, fuzzyOk) {
        if (!s)
            return null;
        // +40 when the query is a whole word ("obs" → OBS Studio before Obsidian)
        const whole = k => k >= s.length || " -_./:,;|+()[]".includes(s[k]) || (b && k < b.length && b[k] > 0) ? 40 : 0;
        let i = s.indexOf(t);
        if (i === 0)
            return {
                score: s.length === t.length ? 1000 : 850 + 50 * t.length / s.length + whole(t.length),
                at: 0,
                word: true
            };
        if (i > 0) {
            const first = i;
            for (; i >= 0; i = s.indexOf(t, i + 1))
                if (root.wordAt(s, i, b))
                    return {
                        score: 700 + 50 * t.length / s.length - Math.min(i, 20) + whole(i + t.length),
                        at: i,
                        word: true
                    };
            if (!fuzzyOk)
                return {
                    score: 500 + 50 * t.length / s.length - Math.min(first, 30),
                    at: first,
                    word: false
                };
        }
        if (!fuzzyOk)
            return null;
        const f = root.fuzzy(s, t, b);
        if (!f)
            return null;
        const norm = f.score / (36 + 26 * (t.length - 1));
        return {
            score: 100 + 500 * Math.max(0, Math.min(1, norm)),
            pos: f.pos,
            word: false
        };
    }

    function wordAt(s, i, b) {
        if (b && i < b.length)
            return b[i] > 0;
        return i === 0 || " -_./:,;|+()[]".includes(s[i - 1]);
    }

    function range(at, len) {
        const out = [];
        for (let i = 0; i < len; i++)
            out.push(at + i);
        return out;
    }

    // Word-boundary bonus per character (fzf's numbers): after a space 10,
    // after punctuation 9, camelCase / digit start 7.
    function bonuses(text) {
        const n = Math.min(text.length, 64);
        const b = new Uint8Array(n);
        for (let j = 0; j < n; j++) {
            const c = text[j];
            const p = j ? text[j - 1] : " ";
            if (p === " " || p === "\t")
                b[j] = 10;
            else if ("-_./:,;|+()[]".includes(p))
                b[j] = 9;
            else if ((p >= "a" && p <= "z" && c >= "A" && c <= "Z") || (!(p >= "0" && p <= "9") && c >= "0" && c <= "9"))
                b[j] = 7;
        }
        return b;
    }

    // fzf v2-style alignment: the best placement of t's letters inside s, rewarding
    // word starts and runs, penalising gaps. Returns { score, pos } or null.
    function fuzzy(s, t, b) {
        const n = Math.min(s.length, 64);
        const m = t.length;
        if (m === 0 || m > 32 || m > n)
            return null;
        let k = 0;
        for (let j = 0; j < n && k < m; j++)
            if (s.charCodeAt(j) === t.charCodeAt(k))
                k++;
        if (k < m)
            return null;

        const NEG = -1e9;
        const H = root.dpScore;
        const P = root.dpFrom;
        for (let i = 0; i < m; i++) {
            const tc = t.charCodeAt(i);
            const row = i * 64;
            const prev = row - 64;
            let gap = NEG;
            let gapFrom = -1;
            for (let j = 0; j < n; j++) {
                if (i > 0 && j >= 2) {
                    const opened = H[prev + j - 2] - 3;      // gap of one starts after column j-2
                    if (opened >= gap - 1) {
                        gap = opened;
                        gapFrom = j - 2;
                    } else {
                        gap -= 1;                             // the gap grows by one
                    }
                }
                let best = NEG;
                let from = -1;
                if (s.charCodeAt(j) === tc) {
                    const bonus = b && j < b.length ? b[j] : 0;
                    if (i === 0) {
                        best = 16 + bonus * 2 - Math.min(j, 10) * 0.25;
                    } else {
                        if (j >= 1 && H[prev + j - 1] > NEG / 2) {
                            best = H[prev + j - 1] + 16 + Math.max(bonus, 4);
                            from = j - 1;
                        }
                        if (gap > NEG / 2 && gap + 16 + bonus > best) {
                            best = gap + 16 + bonus;
                            from = gapFrom;
                        }
                    }
                }
                H[row + j] = best;
                P[row + j] = from;
            }
        }
        const last = (m - 1) * 64;
        let end = -1;
        let top = NEG;
        for (let j = 0; j < n; j++)
            if (H[last + j] > top) {
                top = H[last + j];
                end = j;
            }
        if (top <= NEG / 2)
            return null;
        const pos = new Array(m);
        for (let i = m - 1, j = end; i >= 0; i--) {
            pos[i] = j;
            j = P[i * 64 + j];
        }
        return {
            score: top,
            pos: pos
        };
    }

    // ── frecency ────────────────────────────────────────────────────────────

    function statFor(a) {
        return root.stats[a.key] ?? root.stats["~" + a.idL] ?? root.stats["~" + a.nameL] ?? null;
    }

    // up to +160: 1 launch ≈ 32, 3 ≈ 64, 15 ≈ 128; fades over weeks of not using it
    function boost(a, nowS) {
        const s = root.statFor(a);
        if (!s || !(s.n > 0))
            return 0;
        const days = (nowS - (s.t || 0)) / 86400;
        const recency = days < 1 ? 1 : days < 7 ? 0.85 : days < 30 ? 0.65 : days < 90 ? 0.45 : 0.3;
        return Math.min(160, 32 * Math.log2(1 + s.n) * recency);
    }

    function bump(a) {
        const s = root.statFor(a);
        const st = Object.assign({}, root.stats);
        delete st["~" + a.idL];
        delete st["~" + a.nameL];
        st[a.key] = {
            n: (s?.n ?? 0) + 1,
            t: Math.floor(Date.now() / 1000)
        };
        root.stats = st;
        root.forget();
        root.save();
    }

    // Shift+Delete: forget the selected entry's launch count (or history line)
    function expunge(i) {
        const r = root.results[i];
        if (!r)
            return;
        if (r.kind === "run") {
            root.runs = root.runs.filter(h => h !== r.cmd);
        } else if (r.ref) {
            const st = Object.assign({}, root.stats);
            delete st[r.ref.key];
            delete st["~" + r.ref.idL];
            delete st["~" + r.ref.nameL];
            root.stats = st;
        } else {
            return;
        }
        root.forget();
        root.save();
        root.compute();
        root.select(i);
    }

    function save() {
        store.setText(JSON.stringify({
            version: 1,
            apps: root.stats,
            runs: root.runs
        }));
    }

    function loadState(text) {
        try {
            const o = JSON.parse(text || "{}");
            root.stats = o && typeof o.apps === "object" && o.apps ? o.apps : {};
            root.runs = Array.isArray(o?.runs) ? o.runs.filter(x => typeof x === "string") : [];
        } catch (err) {
            console.warn("launcher: ignoring unreadable state file", store.path);
        }
    }

    // fuzzel keeps "<id>|<count>" lines; accept a few spellings of that
    function mergeFuzzel(text) {
        const st = Object.assign({}, root.stats);
        const t = Math.floor(Date.now() / 1000);
        let count = 0;
        for (const raw of String(text ?? "").split("\n")) {
            const line = raw.trim();
            let m = /^(.+?)[|\t ]+(\d+)$/.exec(line);
            let key = "";
            let n = 0;
            if (m) {
                key = m[1];
                n = Number(m[2]);
            } else if ((m = /^(\d+)[|\t ]+(.+)$/.exec(line))) {
                key = m[2];
                n = Number(m[1]);
            } else {
                continue;
            }
            key = key.trim().toLowerCase().replace(/\.desktop$/, "");
            if (!key || !(n > 0))
                continue;
            st["~" + key] = {
                n: n,
                t: t
            };
            count++;
        }
        root.stats = st;
        if (count)
            console.info(`launcher: imported ${count} launch counts from fuzzel`);
        return count;
    }

    // ── selection ───────────────────────────────────────────────────────────

    function select(i) {
        const n = root.results.length;
        if (!n) {
            root.selected = 0;
            root.scroll = 0;
            return;
        }
        const s = Math.max(0, Math.min(n - 1, i));
        let top = root.scroll;
        if (s < top)
            top = s;
        else if (s >= top + root.lines)
            top = s - root.lines + 1;
        root.scroll = Math.max(0, Math.min(top, n - root.lines));
        root.selected = s;
    }

    function move(d, wrap) {
        const n = root.results.length;
        if (!n)
            return;
        let i = root.selected + d;
        if (wrap)
            i = ((i % n) + n) % n;
        root.select(i);
    }

    // ── launching ───────────────────────────────────────────────────────────

    function activate(i, inTerminal) {
        const r = root.results[i];
        if (!r)
            return false;
        if (r.kind === "calc") {
            if (r.value === null)
                return false;
            root.close();
            Quickshell.execDetached(["wl-copy", "--", r.value]);
            return true;
        }
        root.close();
        if (r.kind === "run") {
            root.runCommand(r.cmd, inTerminal);
        } else {
            root.spawn(r.ref.cmd, r.ref.cwd, r.ref.term || inTerminal);
            root.bump(r.ref);
        }
        return true;
    }

    // Shift+Enter (fuzzel's execute-input): run what's typed as a command
    function executeInput(inTerminal) {
        const c = root.query.replace(/^>/, "").trim();
        if (!c || !Config.launcher.runCommands)
            return false;
        root.close();
        root.runCommand(c, inTerminal);
        return true;
    }

    function runCommand(cmd, inTerminal) {
        const c = String(cmd ?? "").trim();
        if (!c)
            return;
        root.runs = [c].concat(root.runs.filter(h => h !== c)).slice(0, 30);
        root.save();
        if (inTerminal)
            root.spawn(["sh", "-c", c + '; exec "${SHELL:-sh}"'], "", true);
        else
            root.spawn(["sh", "-c", c], "", false);
    }

    function spawn(argv, cwd, inTerminal) {
        if (!argv || !argv.length)
            return;
        const cmd = root.list(Config.launcher.launchPrefix).concat(inTerminal ? root.terminalArgv() : [], argv);
        if (cwd)
            Quickshell.execDetached({
                command: cmd,
                workingDirectory: cwd
            });
        else
            Quickshell.execDetached(cmd);
    }

    // Terminal=true apps: Quickshell's execute() ignores that flag, so wrap them ourselves.
    function terminalArgv() {
        const cfg = root.list(Config.launcher.terminal);
        if (cfg.length)
            return cfg;
        const env = String(Quickshell.env("TERMINAL") ?? "").trim();
        const base = env ? env.split(/\s+/) : [root.detectedTerminal || "xterm"];
        if (base.length > 1)
            return base; // $TERMINAL already carries its own flags
        const flags = {
            "xdg-terminal-exec": [],
            "kitty": [],
            "foot": [],
            "footclient": [],
            "ghostty": ["-e"],
            "alacritty": ["-e"],
            "wezterm": ["start", "--"],
            "konsole": ["-e"],
            "gnome-terminal": ["--"],
            "xterm": ["-e"]
        };
        return base.concat(flags[base[0].split("/").pop()] ?? ["-e"]);
    }

    // ── calculator ──────────────────────────────────────────────────────────

    function calcRows(src, forced) {
        if (!Config.launcher.calculator)
            return [];
        const e = src.trim();
        if (!forced && !root.looksLikeMath(e))
            return [];
        const v = e ? root.calc(e) : null;
        const base = {
            kind: "calc",
            icon: "",
            glyph: "󰃬",
            accent: Theme.colors.text,
            pos: [],
            score: 0,
            ref: null,
            value: null
        };
        if (v === null) {
            if (!forced)
                return [];
            return [Object.assign(base, {
                    title: e ? "= …" : "Calculator",
                    sub: e ? "Not a complete expression yet" : "2^10 · sqrt(2)*3 · (1+5)/2 · 15% * 80 · pi*2"
                })];
        }
        const out = root.formatNumber(v);
        return [Object.assign(base, {
                title: "= " + out,
                sub: e + "   ·   Enter copies it",
                value: out
            })];
    }

    function looksLikeMath(e) {
        if (!/\d/.test(e) || !/^[\d\s.+\-*\/%^()a-z×÷]+$/i.test(e))
            return false;
        const known = ["sqrt", "cbrt", "abs", "round", "floor", "ceil", "ln", "log", "exp", "sin", "cos", "tan", "asin", "acos", "atan", "pi", "e", "tau"];
        const words = e.toLowerCase().match(/[a-z]+/g) ?? [];
        if (!words.every(w => known.includes(w)))
            return false;
        return /[+\-*\/%^(×÷]/.test(e.replace(/^\s*[-+]/, ""));
    }

    // A small recursive-descent parser — never eval(). Returns a number or null.
    // + - * / ^ (or **), % as modulo between numbers and as percent at the end
    // ("15% * 80" = 12), parentheses, pi e tau, sqrt cbrt abs round floor ceil
    // ln log exp sin cos tan asin acos atan (radians).
    function calc(src) {
        const s = src.toLowerCase().replace(/×/g, "*").replace(/÷/g, "/").replace(/\*\*/g, "^");
        const toks = [];
        let i = 0;
        while (i < s.length) {
            const c = s[i];
            if (c === " " || c === "\t") {
                i++;
            } else if ((c >= "0" && c <= "9") || c === ".") {
                let j = i;
                while (j < s.length && ((s[j] >= "0" && s[j] <= "9") || s[j] === "."))
                    j++;
                // 2e3 / 1.5e-2 — but a lone "e" after a number stays Euler's number
                const sign = s[j + 1] === "+" || s[j + 1] === "-" ? 1 : 0;
                if (s[j] === "e" && s[j + 1 + sign] >= "0" && s[j + 1 + sign] <= "9") {
                    j += 1 + sign;
                    while (j < s.length && s[j] >= "0" && s[j] <= "9")
                        j++;
                }
                const v = Number(s.slice(i, j));
                if (!isFinite(v))
                    return null;
                toks.push({
                    t: "n",
                    v: v
                });
                i = j;
            } else if (c >= "a" && c <= "z") {
                let j = i;
                while (j < s.length && s[j] >= "a" && s[j] <= "z")
                    j++;
                toks.push({
                    t: "id",
                    v: s.slice(i, j)
                });
                i = j;
            } else if ("+-*/%^()".includes(c)) {
                toks.push({
                    t: c
                });
                i++;
            } else {
                return null;
            }
        }

        const fns = {
            sqrt: Math.sqrt,
            cbrt: Math.cbrt,
            abs: Math.abs,
            round: Math.round,
            floor: Math.floor,
            ceil: Math.ceil,
            ln: Math.log,
            log: Math.log10,
            exp: Math.exp,
            sin: Math.sin,
            cos: Math.cos,
            tan: Math.tan,
            asin: Math.asin,
            acos: Math.acos,
            atan: Math.atan
        };
        const consts = {
            pi: Math.PI,
            e: Math.E,
            tau: 2 * Math.PI
        };
        let p = 0;
        const peek = () => toks[p]?.t;
        const operand = k => !!k && (k.t === "n" || k.t === "id" || k.t === "(");
        const expect = t => {
            if (peek() !== t)
                throw new Error("expected " + t);
            p++;
        };

        function atom() {
            const k = toks[p++];
            if (!k)
                throw new Error("unexpected end");
            if (k.t === "n")
                return k.v;
            if (k.t === "(") {
                const v = expr();
                expect(")");
                return v;
            }
            if (k.t === "id") {
                if (k.v in consts)
                    return consts[k.v];
                const f = fns[k.v];
                if (!f)
                    throw new Error("unknown " + k.v);
                expect("(");
                const v = expr();
                expect(")");
                return f(v);
            }
            throw new Error("unexpected " + k.t);
        }
        function power() {
            let v = atom();
            while (peek() === "%" && !operand(toks[p + 1])) {
                p++;
                v /= 100;
            }
            if (peek() === "^") {
                p++;
                v = Math.pow(v, unary());
            }
            return v;
        }
        function unary() {
            if (peek() === "-") {
                p++;
                return -unary();
            }
            if (peek() === "+") {
                p++;
                return unary();
            }
            return power();
        }
        function term() {
            let v = unary();
            for (;;) {
                const k = peek();
                if (k === "*") {
                    p++;
                    v *= unary();
                } else if (k === "/") {
                    p++;
                    v /= unary();
                } else if (k === "%") {
                    p++;
                    v %= unary();
                } else {
                    return v;
                }
            }
        }
        function expr() {
            let v = term();
            for (;;) {
                const k = peek();
                if (k === "+") {
                    p++;
                    v += term();
                } else if (k === "-") {
                    p++;
                    v -= term();
                } else {
                    return v;
                }
            }
        }

        try {
            const v = expr();
            return p === toks.length && isFinite(v) ? v : null;
        } catch (err) {
            return null;
        }
    }

    function formatNumber(v) {
        if (v === 0)
            return "0";
        if (Number.isInteger(v) && Math.abs(v) < 1e21)
            return String(v);
        return String(Number(v.toPrecision(12)));
    }

    // ── run a command ───────────────────────────────────────────────────────

    function runRows(cmd) {
        const out = [];
        const base = {
            kind: "run",
            icon: "",
            glyph: "",
            accent: Theme.colors.text,
            score: 0,
            ref: null
        };
        if (cmd)
            out.push(Object.assign({}, base, {
                title: cmd,
                sub: "Run   ·   Ctrl+Enter: in a terminal",
                cmd: cmd,
                pos: []
            }));
        const lc = cmd.toLowerCase();
        for (const h of root.runs) {
            if (h === cmd)
                continue;
            const at = lc ? h.toLowerCase().indexOf(lc) : 0;
            if (at < 0)
                continue;
            out.push(Object.assign({}, base, {
                title: h,
                sub: "From history   ·   Shift+Delete forgets it",
                cmd: h,
                pos: lc ? root.range(at, lc.length) : []
            }));
        }
        return out;
    }

    // ── the index ───────────────────────────────────────────────────────────

    function rebuild() {
        const hide = new Set(root.list(Config.launcher.hidden).map(h => String(h).toLowerCase().replace(/\.desktop$/, "")));
        const apps = [];
        const actions = [];
        const icons = new Set();
        for (const e of root.list(DesktopEntries.applications.values)) {
            const a = root.makeApp(e);
            if (hide.has(a.idL) || !a.cmd.length)
                continue;
            apps.push(a);
            if (a.icon)
                icons.add(a.icon);
            for (const act of root.list(e.actions)) {
                const x = root.makeAction(a, act);
                if (!x.name || !x.cmd.length)
                    continue;
                actions.push(x);
                if (x.icon)
                    icons.add(x.icon);
            }
        }
        root.apps = apps;
        root.actions = actions;
        root.icons = Array.from(icons);
        root.pool = apps.concat(actions);
        root.forget();
        if (root.active)
            root.compute();
    }

    function makeApp(e) {
        const id = String(e.id ?? "");
        const name = String(e.name || id);
        const generic = String(e.genericName ?? "");
        const comment = String(e.comment ?? "");
        const iconName = String(e.icon ?? "");
        const cmd = root.list(e.command).map(x => String(x));
        const nameL = name.toLowerCase();
        const idL = id.toLowerCase().replace(/\.desktop$/, "");
        const exec = cmd.filter(x => x && x[0] !== "-" && !x.includes("=")).map(x => x.split("/").pop()).join(" ").toLowerCase();
        return {
            kind: "app",
            key: id,
            name: name,
            nameL: nameL,
            nameB: root.bonuses(name),
            idL: idL,
            sub: generic && generic.toLowerCase() !== nameL ? generic : comment,
            icon: root.iconFor(iconName, idL),
            accent: AppColors.forApp(name, id, iconName),
            term: !!e.runInTerminal,
            cmd: cmd,
            cwd: String(e.workingDirectory ?? ""),
            needsName: false,
            fields: [
                {
                    s: idL,
                    w: 0.8
                },
                {
                    s: generic.toLowerCase(),
                    w: 0.9
                },
                {
                    s: root.list(e.keywords).join(" ").toLowerCase(),
                    w: 0.7
                },
                {
                    s: exec,
                    w: 0.7
                },
                {
                    s: comment.toLowerCase(),
                    w: 0.45,
                    wordOnly: true
                }
            ].filter(f => f.s)
        };
    }

    function makeAction(a, act) {
        const name = String(act.name ?? "");
        const key = a.key + "#" + String(act.id ?? name);
        return {
            kind: "action",
            key: key,
            name: name,
            nameL: name.toLowerCase(),
            nameB: root.bonuses(name),
            idL: key.toLowerCase(),
            sub: a.name,
            icon: root.iconFor(String(act.icon ?? ""), "") || a.icon,
            accent: a.accent,
            term: a.term,
            cmd: root.list(act.command).map(x => String(x)),
            cwd: a.cwd,
            needsName: true,
            fields: [
                {
                    s: a.nameL,
                    w: 0.9
                },
                {
                    s: a.idL,
                    w: 0.7
                },
                {
                    s: a.fields.find(f => f.w === 0.9)?.s ?? "",
                    w: 0.6
                }
            ].filter(f => f.s)
        };
    }

    function iconFor(icon, fallback) {
        if (icon.startsWith("/"))
            return "file://" + icon;
        if (icon) {
            const p = Quickshell.iconPath(icon, true);
            if (p)
                return p;
        }
        if (fallback && fallback !== icon) {
            const p = Quickshell.iconPath(fallback, true);
            if (p)
                return p;
        }
        return "";
    }

    function list(x) {
        const out = [];
        if (!x)
            return out;
        for (let i = 0; i < x.length; i++)
            out.push(x[i]);
        return out;
    }

    // ── helpers for the window ──────────────────────────────────────────────

    // title with the matched letters in your accent — StyledText, escaped
    function markup(s, pos) {
        if (!s)
            return "";
        const hit = new Set(pos ?? []);
        let o = "";
        let lit = false;
        for (let i = 0; i < s.length; i++) {
            const h = hit.has(i);
            if (h && !lit)
                o += `<font color="${root.hlColor}"><b>`;
            else if (!h && lit)
                o += "</b></font>";
            lit = h;
            const c = s[i];
            o += c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c;
        }
        if (lit)
            o += "</b></font>";
        return o;
    }

    // fuzzel's default keys → action names (the window carries them out)
    function keyAction(key, mods) {
        const C = Qt.ControlModifier;
        const S = Qt.ShiftModifier;
        const A = Qt.AltModifier;
        const m = mods & (C | S | A);
        if (key === Qt.Key_Escape || (m === C && (key === Qt.Key_G || key === Qt.Key_C || key === Qt.Key_BracketLeft)))
            return "cancel";
        if (key === Qt.Key_Return || key === Qt.Key_Enter)
            return m === S ? "execute-input" : m === C ? "execute-terminal" : "execute";
        if (m === C && key === Qt.Key_Y)
            return "execute";
        if (key === Qt.Key_Backtab)
            return "prev-wrap";
        if (key === Qt.Key_Tab)
            return m === C ? "insert-selected" : m === S ? "prev-wrap" : "execute-or-next";
        if (key === Qt.Key_Up || (m === C && key === Qt.Key_P))
            return "prev";
        if (key === Qt.Key_Down || (m === C && key === Qt.Key_N))
            return "next";
        if (key === Qt.Key_PageUp)
            return "prev-page";
        if (key === Qt.Key_PageDown)
            return "next-page";
        if (m === C && key === Qt.Key_Home)
            return "first";
        if (m === C && key === Qt.Key_End)
            return "last";
        if (m === S && key === Qt.Key_Delete)
            return "expunge";
        if (m === (C | S) && key === Qt.Key_Backspace)
            return "delete-line";
        if (m === C) {
            switch (key) {
            case Qt.Key_U:
                return "delete-line-backward";
            case Qt.Key_K:
                return "delete-line-forward";
            case Qt.Key_W:
                return "delete-prev-word";
            case Qt.Key_A:
                return "home";
            case Qt.Key_E:
                return "end";
            case Qt.Key_B:
                return "left";
            case Qt.Key_F:
                return "right";
            case Qt.Key_H:
                return "backspace";
            }
        }
        if (m === A) {
            switch (key) {
            case Qt.Key_Backspace:
                return "delete-prev-word";
            case Qt.Key_D:
                return "delete-next-word";
            case Qt.Key_B:
                return "word-left";
            case Qt.Key_F:
                return "word-right";
            }
        }
        return "";
    }

    function wordLeft(s, p) {
        let i = p;
        while (i > 0 && /\s/.test(s[i - 1]))
            i--;
        while (i > 0 && !/\s/.test(s[i - 1]))
            i--;
        return i;
    }

    function wordRight(s, p) {
        let i = p;
        while (i < s.length && /\s/.test(s[i]))
            i++;
        while (i < s.length && !/\s/.test(s[i]))
            i++;
        return i;
    }

    // ── plumbing ────────────────────────────────────────────────────────────

    // Indexing every app takes a moment, so it waits until the bar is on screen
    // (opening the launcher before then indexes right away).
    Timer {
        running: true
        interval: 400
        onTriggered: {
            if (!root.apps.length)
                root.rebuild();
        }
    }

    // While closed, work out "" and every single letter, so opening and the first
    // keystroke are lookups. One query per tick; stops the moment the launcher opens.
    Timer {
        interval: 30
        repeat: true
        running: !root.active && root.warmIndex < 26 && root.apps.length > 0
        onTriggered: {
            if (root.warmIndex === 0)
                root.search("");
            root.search(String.fromCharCode(97 + root.warmIndex));
            root.warmIndex++;
        }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.rebuild();
        }
    }

    FileView {
        id: store
        path: Quickshell.statePath("launcher.json")
        printErrors: false
        onLoaded: root.loadState(store.text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound && Config.launcher.importFuzzelHistory)
                root.importFuzzel = true;
        }
    }

    FileView {
        id: fuzzelFile
        path: root.importFuzzel ? root.fuzzelCache : ""
        printErrors: false
        onLoaded: {
            if (root.mergeFuzzel(fuzzelFile.text()))
                root.save();
            root.importFuzzel = false;
        }
        onLoadFailed: root.importFuzzel = false
    }

    // find a terminal once, at startup — not when you launch something
    Process {
        running: true
        command: ["sh", "-c", "for t in xdg-terminal-exec kitty foot ghostty alacritty wezterm konsole gnome-terminal xterm; do command -v \"$t\" >/dev/null 2>&1 && { printf %s \"$t\"; exit 0; }; done"]
        stdout: StdioCollector {
            id: termOut
            onStreamFinished: root.detectedTerminal = termOut.text.trim()
        }
    }

    GlobalShortcut {
        name: "launcher"
        description: "Open or close the app launcher"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open("");
        }
        function close(): void {
            root.close();
        }
        function search(text: string): void {
            root.open(text);
        }
    }
}
