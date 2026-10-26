#!/usr/bin/env node
// Audit gate: fails on any HIGH/CRITICAL lockfile advisory except a documented,
// explicitly allowlisted set of no-fix-available advisories.
// AUDIT_GATE_STRICT=1 disables the allowlist (re-audit accepted risk at any time).
const { spawnSync } = require("child_process");
const ALLOWLIST = {
  "GHSA-86w9-cpqp-85rv": {
    package: "node-forge",
    reason:
      "No fixed release exists (advisory covers every version). Carried by @parse/node-apn; " +
      "AlarmServer uses forge only to parse its own APNs credentials, never to verify " +
      "attacker-controlled signatures.",
  },
};
const argv = process.argv.slice(2);
const installed = argv.includes("--installed");
const dirs = argv.filter((a) => a !== "--installed");
dirs.length || dirs.push(".");
const strict = process.env.AUDIT_GATE_STRICT === "1";
let failed = 0;
for (const dir of dirs) {
  const r = spawnSync("npm", ["--prefix", dir, "audit"].concat(installed ? [] : ["--package-lock-only"]).concat(["--json"]), {
    encoding: "utf8", maxBuffer: 64 * 1024 * 1024,
  });
  let report;
  try { report = JSON.parse(r.stdout); } catch (e) {
    console.error("[audit-gate] " + dir + ": could not parse npm audit output");
    failed = 1; continue;
  }
  const vulns = report.vulnerabilities || {};
  const acceptedPkgs = new Set();
  for (const [name, v] of Object.entries(vulns)) {
    if (!["high", "critical"].includes(v.severity)) continue;
    const advisories = (v.via || []).filter((x) => typeof x === "object" && x.url);
    const ok = !strict && advisories.length > 0 &&
      advisories.every((a) => ALLOWLIST[a.url.split("/").pop()]);
    if (ok) { acceptedPkgs.add(name); }
  }
  for (const [name, v] of Object.entries(vulns)) {
    if (!["high", "critical"].includes(v.severity)) continue;
    const advisories = (v.via || []).filter((x) => typeof x === "object" && x.url);
    if (advisories.length > 0) {
      const ok = acceptedPkgs.has(name);
      for (const a of advisories) {
        const id = a.url.split("/").pop();
        if (ok) console.log("[audit-gate] ACCEPTED " + name + " " + id + ": " + ALLOWLIST[id].reason);
        else { console.error("[audit-gate] FAIL " + name + " " + a.url + " - " + a.title); failed = 1; }
      }
    } else {
      const chainVia = (v.via || []).filter((x) => typeof x === "string");
      if (!chainVia.every((p) => acceptedPkgs.has(p))) {
        console.error("[audit-gate] FAIL " + name + " (" + v.severity + ") via " + JSON.stringify(chainVia));
        failed = 1;
      }
    }
  }
}
process.exit(failed);
