/*
    kindle-tools server — 越狱入口 + 组件分发 (通用版, 无硬编码 IP)
    基于 WinterBreak2 (Scam.Net / Penguins184, ISC) 本地化改造。
    实例文件(local/)由启动脚本自动生成, 仓库不含任何机器信息。
*/
import express from "express";
import path from "path";
import fs from "fs";
import { execFile } from "child_process";

const ROOT = path.join(process.cwd(), "..");        // 仓库根
const LOCAL = path.join(ROOT, "local");             // 运行时实例
const T = (f) => path.join(LOCAL, f);

const app = express();
const MODE_FILE = T("mode.txt");
const readMode = () => { try { return fs.readFileSync(MODE_FILE, "utf8").trim() || "jb"; } catch { return "jb"; } };
const MODE_INFO = {
    jb:      { label: "越狱 (jb.sh 官方脚本)", file: path.join(ROOT, "jailbreak", "jb.sh") },
    install: { label: "安装/修复 SSH (kindle-tools)", file: T("jb.sh.install") },
};

/* ---------- 落地页 ---------- */
app.get("/", (req, res) => {
    const info = MODE_INFO[readMode()] || MODE_INFO.jb;
    res.send(`<!DOCTYPE html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Kindle 本地服务站</title>
<style>html,body{margin:0;background:#fff;color:#111;font-family:serif}
.wrap{max-width:480px;margin:0 auto;padding:24px 16px}
h1{font-size:1.4em;border-bottom:2px solid #111;padding-bottom:8px}
.card{border:2px solid #111;border-radius:8px;padding:14px;margin:14px 0}
.card h2{margin:0 0 6px;font-size:1.05em}.card p{margin:0 0 12px;font-size:.88em;color:#333}
a.btn{display:block;text-align:center;padding:12px;font-size:1em;border:2px solid #111;border-radius:6px;background:#fff;color:#111;text-decoration:none}
a.btn.dark{background:#111;color:#fff}
.mode{font-size:.85em;padding:8px 10px;border:1px dashed #666;border-radius:6px;margin:12px 0}
.foot{font-size:.78em;color:#666;margin-top:20px;line-height:1.5}</style></head><body><div class="wrap">
<h1>Kindle 本地服务站</h1>
<div class="mode">当前模式：<b>${info.label}</b><br>点按任一按钮切换模式并触发浏览器漏洞，设备将执行该模式脚本。</div>
<div class="card"><h2>1 · 越狱 Jailbreak</h2><p>未越狱的设备用。执行官方 jb.sh v1.3.7（本机拉取，全程不走外网）。</p>
<a class="btn dark" href="/mode/jb">Jailbreak 越狱</a></div>
<div class="card"><h2>2 · 安装 / 修复 SSH</h2><p>已越狱的设备用。安装 kindle-tools（ssh + telnet + 面板 + 开机自启）；可重复执行，幂等修复。</p>
<a class="btn" href="/mode/install">安装 / 修复 SSH</a></div>
<div class="foot">kindle-tools · Winterbreak2 by Scam.Net, Penguins184</div></div></body></html>`);
});

app.get("/mode/:which", (req, res) => {
    if (!MODE_INFO[req.params.which]) { res.status(404).send("unknown mode"); return; }
    fs.mkdirSync(LOCAL, { recursive: true });
    fs.writeFileSync(MODE_FILE, req.params.which);
    console.log(`[MODE] ${req.ip} -> ${req.params.which}`);
    res.redirect("/download");
});

/* ---------- WB2 浏览器漏洞 (Content-Disposition 文件名 XSS → customDialog 路径穿越) ---------- */
const MOBI = path.join(LOCAL, "placeholder.mobi");
app.get("/download", (req, res) => {
    console.log(`[HIT] /download (exploit) <- ${req.ip}`);
    if (!fs.existsSync(MOBI)) { fs.mkdirSync(LOCAL, { recursive: true }); fs.writeFileSync(MOBI, ""); }
    const fName = `<script>(window.kindle||top.kindle).messaging.sendMessage("com.lab126.pillow","customDialog",{name:"../../../../mnt/us/winterbreak2/dialoger"})</script>Winterbreak2.mobi`;
    res.set({ "Content-Type": "application/x-mobipocket-ebook", "Content-Disposition": `attachment; filename=${fName}` });
    res.sendFile(MOBI, (err) => { if (err) res.status(500).send("fail"); });
});

/* ---------- 通用文件分发 ---------- */
const serve = (route, file, type) => app.get(route, (req, res) => {
    console.log(`[HIT] ${route} <- ${req.ip}`);
    res.set("Content-Type", type);
    res.sendFile(file, (err) => { if (err && !res.headersSent) res.status(500).send(`${path.basename(file)} not found`); });
});

app.get("/jb.sh", (req, res) => {          // (覆盖上面的占位注册)
    const mode = readMode();
    const file = path.resolve(MODE_INFO[mode] ? MODE_INFO[mode].file : MODE_INFO.jb.file);
    console.log(`[HIT] /jb.sh (mode=${mode}) <- ${req.ip}`);
    res.set("Content-Type", "application/x-sh");
    res.sendFile(file, (err) => { if (err && !res.headersSent) res.status(500).send("script not found"); });
});

serve("/t", T("recovery.sh"), "text/x-shellscript");
serve("/boot", path.join(ROOT, "device", "boot.sh"), "text/x-shellscript");
serve("/config", T("config.sh"), "text/x-shellscript");
serve("/pubkey", T("pubkey.pub"), "text/plain");
serve("/dropbear", path.join(ROOT, "bin", "dropbear"), "application/octet-stream");
serve("/dropbearkey", path.join(ROOT, "bin", "dropbearkey"), "application/octet-stream");
serve("/shd", path.join(ROOT, "bin", "minishelld"), "application/octet-stream");
serve("/rmsh", path.join(ROOT, "bin", "rmsh"), "application/octet-stream");
serve("/sshentry", path.join(ROOT, "Remote Shell.sh"), "text/x-shellscript");
app.use("/ui", express.static(path.join(ROOT, "ui")));

/* ---------- 整面板按需渲染 ---------- */
app.get("/panel.png", (req, res) => {
    console.log(`[HIT] /panel.png w=${req.query.w} state=${req.query.state} <- ${req.ip}`);
    const w = Math.min(Math.max(parseInt(req.query.w, 10) || 758, 300), 2200);
    const h = Math.round(w * 1024 / 758);
    const ip = /^[0-9.]{1,15}$/.test(String(req.query.ip || "")) ? String(req.query.ip) : "";
    const st = String(req.query.state || "off,off").split(",");
    const ss = st[0] === "on" ? "ON" : "OFF", ts = st[1] === "on" ? "ON" : "OFF";
    const cache = path.join(ROOT, "ui-cache");
    fs.mkdirSync(cache, { recursive: true });
    const out = path.join(cache, `panel_${w}_${ip.replace(/\./g, "_")}_${ss}_${ts}.png`);
    if (fs.existsSync(out)) { res.set("Content-Type", "image/png"); res.sendFile(out); return; }
    execFile("bash", [path.join(ROOT, "ui", "make-ui.sh"), "single", String(w), String(h), ss, ts, out, ip],
        { timeout: 30000 }, (err) => {
        if (err || !fs.existsSync(out)) { res.status(500).send("render fail"); return; }
        res.set("Content-Type", "image/png");
        res.sendFile(out);
    });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`kindle-tools server: http://0.0.0.0:${PORT}  (repo=${ROOT})`));
