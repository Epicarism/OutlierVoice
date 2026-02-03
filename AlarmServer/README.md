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
