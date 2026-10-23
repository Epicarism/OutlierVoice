# 🔔 Claude Alarm Server

Local server that sends VoIP push notifications to make alarms ring like **real phone calls** even when your iPhone is locked!

## How It Works

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   iPhone    │ ───→ │  Mac Server │ ───→ │    APNs     │ ───→ │   iPhone    │
│ (set alarm) │      │  (this!)    │      │   (Apple)   │      │ (CallKit!)  │
└─────────────┘      └─────────────┘      └─────────────┘      └─────────────┘
```

1. **App creates alarm** → Syncs to this server
2. **Server schedules job** → Waits for alarm time
3. **Alarm time hits** → Server sends VoIP push via APNs
4. **iPhone receives push** → CallKit rings like a real call!

## Quick Start

### 1. Start the server
```bash
cd AlarmServer
npm ci --ignore-scripts
npm audit --audit-level=high
node ../.github/scripts/dependency-smoke.cjs
npm start
```

### 2. Configure APNs (required for real pushes)

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list)
2. Create a new **Key** with "Apple Push Notifications service (APNs)" enabled
3. Download the `.p8` file
4. Save it as `AuthKey.p8` in this folder
5. Edit `server.js` and update:
   ```js
   const CONFIG = {
       apns: {
           keyId: 'YOUR_KEY_ID',      // From the key you created
           teamId: 'YOUR_TEAM_ID',    // Your Apple Developer Team ID
       }
   };
   ```

### 3. Update the app's server URL

The app defaults to `http://192.168.1.100:3000`. Update it in:
- `VoIPPushManager.swift` → Change the default URL
- Or add a Settings screen to configure it

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Health check |
| `/register` | POST | Register device token |
| `/alarm` | POST | Create/update alarm |
| `/alarm/:id` | DELETE | Delete alarm |
| `/alarms` | GET | List all alarms |
| `/test-push` | POST | Send test push |

## Example Requests

### Register Device
```bash
curl -X POST http://localhost:3000/register \
  -H "Content-Type: application/json" \
  -d '{"deviceId": "abc123", "deviceToken": "your-voip-token"}'
```

### Create Alarm
```bash
curl -X POST http://localhost:3000/alarm \
  -H "Content-Type: application/json" \
  -d '{
    "alarmId": "alarm-1",
    "deviceId": "abc123",
    "title": "Wake Up!",
    "message": "Good morning sunshine!",
    "time": "2024-01-15T07:00:00Z",
    "repeatDays": [2,3,4,5,6],
    "isEnabled": true
  }'
```

### Test Push
```bash
curl -X POST http://localhost:3000/test-push \
  -H "Content-Type: application/json" \
  -d '{"deviceId": "abc123"}'
```

## Keep Mac Awake

For overnight alarms, prevent your Mac from sleeping:

```bash
# Run in terminal (keeps running)
caffeinate -d -i -s
```

Or: **System Settings → Energy → Prevent sleep when display is off**

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Push not received | Check APNs config, device token, network |
| Server won't start | Run `npm install` first |
| Connection refused | Check firewall, same WiFi network |
| Token invalid | Rebuild app to get new VoIP token |

## Files

- `server.js` - Main server code
- `AuthKey.p8` - Your APNs key (you create this)
- `alarms.json` - Persisted alarms (auto-created)
- `devices.json` - Registered devices (auto-created)

## Node security baseline (2026-10-23)

AlarmServer uses **24.22.1** from its `.node-version`. Supported alternatives are 22.23.4+
on 22.x, 24.22.1+ on 24.x, or 26.12.1+ on 26.x; other major lines are rejected. These are
the [October 21 security floors](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases)
for CVE-2026-111497. No Swift, notification, alarm or server protocol behavior is changed.

From the repository root, `node .github/scripts/node-security.cjs --self-test` passed on
Node 24.22.1 on 2026-10-23: supported-floor boundaries, stale deployment-selector rejection
and a normal Brotli roundtrip. This does not prove exploit resistance or vendor backport provenance.
CI also audits this lockfile without installing dependencies and fails closed on high/critical
advisories or audit errors. Compatible security fixes reduce **3 high / 1 critical** to
**2 high / 0 critical** (2026-10-23): proxy-addr 2.0.8, path-to-regexp 8.4.2,
qs 6.16.1, body-parser 2.4.0, and a same-major node-forge 1.4.0 override.
The remaining two high package entries share one unpatched vendor advisory,
[node-forge GHSA-86w9-cpqp-85rv](https://github.com/advisories/GHSA-86w9-cpqp-85rv).
Latest-published node-forge 1.4.0 is still affected; node-apn 8.1.0 also pins it, so a blind
APNs major upgrade would not repair this risk. CI keeps failing honestly, without suppression.
The obsolete committed `node_modules` tree is removed and ignored: install from the lockfile,
never from stale vendored files. CI tests normal payload serialization without any provider,
push, alarm or listener, and audits the actual freshly installed tree as well as the lockfile.
**Rollout hazard:** pulling this commit into a checkout removes its tracked `node_modules` files.
Do not pull it underneath a running AlarmServer. The service owner must explicitly decide the
remaining vendor risk, retain a rollback, coordinate an idle window, and run `npm ci --ignore-scripts`
before any restart. Repository approval is not approval to deploy with the failing forge audit.
Do not proceed to `npm start` when the audit fails; deployment needs the service owner's
explicit handling of the remaining vendor blocker.
Weekly Dependabot covers AlarmServer npm and GitHub Actions; the repository author reviews updates.
This patch does not start the server, send pushes, place calls, or deploy/restart any service.
