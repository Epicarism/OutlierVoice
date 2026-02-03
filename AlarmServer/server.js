const express = require('express');
const schedule = require('node-schedule');
const apn = require('@parse/node-apn');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json());

// ============================================
// CONFIGURATION - UPDATE THESE!
// ============================================
const CONFIG = {
    port: 3000,
    
    // APNs Configuration (get from Apple Developer Portal)
    apns: {
        // Option 1: Use .p8 key file (recommended)
        keyPath: './AuthKey.p8',      // Download from Apple Developer Portal
        keyId: 'YOUR_KEY_ID',          // 10-char key ID from Apple
        teamId: 'YOUR_TEAM_ID',        // Your Apple Developer Team ID
        
        // Your app's bundle ID
        bundleId: 'com.outliervoice.app',
        
        // Use production for TestFlight/App Store, development for Xcode builds
        production: false
    }
};

// ============================================
// STORAGE
// ============================================
const ALARMS_FILE = path.join(__dirname, 'alarms.json');
const DEVICES_FILE = path.join(__dirname, 'devices.json');

let alarms = {};      // { alarmId: { deviceToken, title, message, time, repeatDays, jobId } }
let devices = {};     // { deviceId: deviceToken }
let scheduledJobs = {}; // { alarmId: Job }

// Load saved data
function loadData() {
    try {
        if (fs.existsSync(ALARMS_FILE)) {
            alarms = JSON.parse(fs.readFileSync(ALARMS_FILE, 'utf8'));
            console.log(`📂 Loaded ${Object.keys(alarms).length} alarms`);
        }
        if (fs.existsSync(DEVICES_FILE)) {
            devices = JSON.parse(fs.readFileSync(DEVICES_FILE, 'utf8'));
            console.log(`📱 Loaded ${Object.keys(devices).length} devices`);
        }
    } catch (e) {
        console.error('Error loading data:', e);
    }
}

function saveData() {
    fs.writeFileSync(ALARMS_FILE, JSON.stringify(alarms, null, 2));
    fs.writeFileSync(DEVICES_FILE, JSON.stringify(devices, null, 2));
}

// ============================================
// APNs SETUP
// ============================================
let apnProvider = null;

function initAPNs() {
    // Check if key file exists
    if (!fs.existsSync(CONFIG.apns.keyPath)) {
        console.log('\n⚠️  APNs key file not found!');
        console.log('📋 To enable VoIP push notifications:');
        console.log('   1. Go to https://developer.apple.com/account/resources/authkeys/list');
        console.log('   2. Create a new key with "Apple Push Notifications service (APNs)"');
        console.log('   3. Download the .p8 file and save as "AuthKey.p8" in this folder');
        console.log('   4. Update CONFIG.apns.keyId and CONFIG.apns.teamId in server.js');
        console.log('\n🔄 Server running in TEST MODE (no pushes will be sent)\n');
        return;
    }
    
    try {
        apnProvider = new apn.Provider({
            token: {
                key: CONFIG.apns.keyPath,
                keyId: CONFIG.apns.keyId,
                teamId: CONFIG.apns.teamId
            },
            production: CONFIG.apns.production
        });
        console.log('✅ APNs provider initialized');
    } catch (e) {
        console.error('❌ APNs init failed:', e.message);
    }
}

// ============================================
// SEND VOIP PUSH
// ============================================
async function sendVoIPPush(deviceToken, alarmId, title, message) {
    console.log(`\n📞 Sending VoIP push for alarm: ${title}`);
    console.log(`   Device: ${deviceToken.substring(0, 20)}...`);
    
    if (!apnProvider) {
        console.log('   ⚠️  APNs not configured - skipping push');
        console.log('   📱 In test mode, trigger alarm manually in the app');
        return { sent: false, reason: 'APNs not configured' };
    }
    
    // Create VoIP notification
    const notification = new apn.Notification();
    
    // VoIP pushes use a different topic
    notification.topic = CONFIG.apns.bundleId + '.voip';
    notification.pushType = 'voip';
    notification.priority = 10;  // Send immediately
    notification.expiry = Math.floor(Date.now() / 1000) + 60; // Expire in 60 seconds
    
    notification.payload = {
        alarmId: alarmId,
        title: title,
        message: message,
        timestamp: Date.now()
    };
    
    try {
        const result = await apnProvider.send(notification, deviceToken);
        
        if (result.failed.length > 0) {
            console.log('   ❌ Push failed:', result.failed[0].response);
            return { sent: false, reason: result.failed[0].response };
        }
        
        console.log('   ✅ VoIP push sent successfully!');
        return { sent: true };
    } catch (e) {
        console.error('   ❌ Push error:', e.message);
        return { sent: false, reason: e.message };
    }
}

// ============================================
// SCHEDULE ALARM
// ============================================
function scheduleAlarm(alarmId, alarm) {
    // Cancel existing job if any
    if (scheduledJobs[alarmId]) {
        scheduledJobs[alarmId].cancel();
    }
    
    const { deviceToken, title, message, time, repeatDays } = alarm;
    const alarmTime = new Date(time);
    
    if (repeatDays && repeatDays.length > 0) {
        // Repeating alarm - schedule for each day
        // repeatDays: 1=Sunday, 2=Monday, ..., 7=Saturday (iOS format)
        // node-schedule: 0=Sunday, 1=Monday, ..., 6=Saturday
        const rule = new schedule.RecurrenceRule();
        rule.dayOfWeek = repeatDays.map(d => d - 1); // Convert iOS to node-schedule format
        rule.hour = alarmTime.getHours();
        rule.minute = alarmTime.getMinutes();
        rule.second = 0;
        
        scheduledJobs[alarmId] = schedule.scheduleJob(rule, () => {
            console.log(`\n⏰ REPEATING ALARM TRIGGERED: ${title}`);
            sendVoIPPush(deviceToken, alarmId, title, message);
        });
        
        console.log(`📅 Scheduled repeating alarm "${title}" for days [${repeatDays}] at ${alarmTime.getHours()}:${String(alarmTime.getMinutes()).padStart(2, '0')}`);
    } else {
        // One-time alarm
        if (alarmTime <= new Date()) {
            console.log(`⚠️  Alarm "${title}" is in the past, skipping`);
            return;
        }
        
        scheduledJobs[alarmId] = schedule.scheduleJob(alarmTime, () => {
            console.log(`\n⏰ ONE-TIME ALARM TRIGGERED: ${title}`);
            sendVoIPPush(deviceToken, alarmId, title, message);
            
            // Remove one-time alarm after triggering
            delete alarms[alarmId];
            delete scheduledJobs[alarmId];
            saveData();
        });
        
        console.log(`📅 Scheduled one-time alarm "${title}" for ${alarmTime.toLocaleString()}`);
    }
}

// Reschedule all alarms on startup
function rescheduleAllAlarms() {
    console.log('\n🔄 Rescheduling all alarms...');
    for (const [alarmId, alarm] of Object.entries(alarms)) {
        if (alarm.isEnabled !== false) {
            scheduleAlarm(alarmId, alarm);
        }
    }
}

// ============================================
// API ENDPOINTS
// ============================================

// Health check
app.get('/', (req, res) => {
    res.json({ 
        status: 'running',
        alarms: Object.keys(alarms).length,
        devices: Object.keys(devices).length,
        apnsConfigured: !!apnProvider
    });
});

// Register device token
app.post('/register', (req, res) => {
    const { deviceId, deviceToken } = req.body;
    
    if (!deviceId || !deviceToken) {
        return res.status(400).json({ error: 'deviceId and deviceToken required' });
    }
    
    devices[deviceId] = deviceToken;
    saveData();
    
    console.log(`📱 Registered device: ${deviceId.substring(0, 8)}... → ${deviceToken.substring(0, 20)}...`);
    res.json({ success: true });
});

// Create/update alarm
app.post('/alarm', (req, res) => {
    const { alarmId, deviceId, title, message, time, repeatDays, isEnabled } = req.body;
    
    if (!alarmId || !deviceId || !title || !time) {
        return res.status(400).json({ error: 'alarmId, deviceId, title, and time required' });
    }
    
    const deviceToken = devices[deviceId];
    if (!deviceToken) {
        return res.status(400).json({ error: 'Device not registered. Call /register first.' });
    }
    
    const alarm = {
        deviceToken,
        title,
        message: message || '',
        time,
        repeatDays: repeatDays || [],
        isEnabled: isEnabled !== false
    };
    
    alarms[alarmId] = alarm;
    saveData();
    
    if (alarm.isEnabled) {
        scheduleAlarm(alarmId, alarm);
    } else if (scheduledJobs[alarmId]) {
        scheduledJobs[alarmId].cancel();
        delete scheduledJobs[alarmId];
    }
    
    console.log(`⏰ Alarm saved: ${title} (${isEnabled !== false ? 'enabled' : 'disabled'})`);
    res.json({ success: true, alarmId });
});

// Delete alarm
app.delete('/alarm/:alarmId', (req, res) => {
    const { alarmId } = req.params;
    
    if (scheduledJobs[alarmId]) {
        scheduledJobs[alarmId].cancel();
        delete scheduledJobs[alarmId];
    }
    
    delete alarms[alarmId];
    saveData();
    
    console.log(`🗑️  Alarm deleted: ${alarmId}`);
    res.json({ success: true });
});

// List all alarms
app.get('/alarms', (req, res) => {
    res.json(alarms);
});

// Test push (for debugging)
app.post('/test-push', async (req, res) => {
    const { deviceId } = req.body;
    
    const deviceToken = devices[deviceId];
    if (!deviceToken) {
        return res.status(400).json({ error: 'Device not registered' });
    }
    
    const result = await sendVoIPPush(
        deviceToken, 
        'test-' + Date.now(), 
        'Test Alarm', 
        'This is a test VoIP push!'
    );
    
    res.json(result);
});

// ============================================
// START SERVER
// ============================================
loadData();
initAPNs();
rescheduleAllAlarms();

app.listen(CONFIG.port, () => {
    console.log('\n🚀 =======================================');
    console.log(`   Claude Alarm Server running on port ${CONFIG.port}`);
    console.log('   =======================================');
    console.log(`\n📡 Local URL: http://localhost:${CONFIG.port}`);
    console.log(`📡 Network URL: http://${getLocalIP()}:${CONFIG.port}`);
    console.log('\n📋 Endpoints:');
    console.log('   POST /register     - Register device token');
    console.log('   POST /alarm        - Create/update alarm');
    console.log('   DELETE /alarm/:id  - Delete alarm');
    console.log('   GET /alarms        - List all alarms');
    console.log('   POST /test-push    - Send test push');
    console.log('');
});

// Get local IP for easy access from phone
function getLocalIP() {
    const { networkInterfaces } = require('os');
    const nets = networkInterfaces();
    
    for (const name of Object.keys(nets)) {
        for (const net of nets[name]) {
            if (net.family === 'IPv4' && !net.internal) {
                return net.address;
            }
        }
    }
    return 'localhost';
}
