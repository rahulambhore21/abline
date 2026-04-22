# 🎙️ Hold-to-Speak Recording - Fix & Test

## What I Fixed:

1. ✅ **Installed missing `express-fileupload`** - This was preventing file uploads
2. ✅ **Added detailed error logging** - Now you'll see exactly what's failing
3. ✅ **Improved Flutter error handling** - Shows actual error messages to user
4. ✅ **Extended timeout to 60 seconds** - Handles slow network uploads

---

## Step-by-Step Test (Do This Now):

### Step 1: Restart Backend
```bash
cd backend
npm run start
```

Wait for: `✅ Agora RTC Token Server running on http://localhost:5000`

### Step 2: Rebuild Flutter App
```bash
cd app
flutter clean
flutter pub get
flutter run
```

### Step 3: Test Recording

**On Phone/Emulator:**
1. Login as a user
2. Join Room
3. Wait 2-3 seconds for microphone to be ready
4. **HOLD the microphone button** (don't tap - HOLD it)
5. You should hear yourself speaking (audio passthrough)
6. Release the button after 2-3 seconds
7. Watch for: ✅ **"Recording saved! 🎙️"** notification

**Check Backend Logs:**
Look for lines like:
```
📥 Recording upload request received
📤 Sending request...
✅ File saved successfully
✅ Recording metadata stored
```

---

## If Still Not Working:

### Common Issues:

**1. ❌ "Upload failed (400)" error**
- Check backend logs for: `❌ Missing: audioFile`
- **Solution:** Make sure you're HOLDING the button (not tapping), hold for at least 1 second

**2. ❌ "Upload error: Connection timeout"**
- Network too slow for deployed URL
- **Solution:** Try on local WiFi, or test locally with `localhost`

**3. ❌ "Upload failed (405)" or "Not Found"**
- Backend endpoint not found or not restarted
- **Solution:** 
  - Stop backend (Ctrl+C)
  - Run: `npm install` (to ensure express-fileupload installed)
  - Run: `npm run start`

**4. ❌ No "Recording saved" notification at all**
- Request not reaching server
- **Solution:** Check backend logs - should show `📥 Recording upload request received`

**5. ✅ Recording uploads but doesn't appear in list**
- Upload succeeded but retrieval failed
- **Solution:** Refresh the recordings screen

---

## Debug Steps:

### Check Backend is Ready:
```bash
curl http://localhost:5000/health
```
Should return: `{"status":"ok",...}`

### Check File Upload Endpoint:
```bash
# Create a test audio file (or use any m4a file)
curl -X POST http://localhost:5000/recordings/save \
  -F "audioFile=@test.m4a" \
  -F "userId=123" \
  -F "sessionId=test_room" \
  -F "durationMs=3000"
```

### Watch Backend Logs Live:
```bash
npm run start
# Keep this window open and watch for upload messages
```

---

## Expected Workflow:

```
[User HOLDS microphone button]
  ↓
[Flutter records audio to local file]
  ↓
[User releases button]
  ↓
Flutter: 📤 Uploading to backend...
Backend: 📥 Recording upload request received
Backend: 💾 Saving file to: .../recordings/rec_xxx.m4a
Backend: ✅ File saved successfully
Flutter: ✅ "Recording saved! 🎙️"
User: Can now view in "Your Recordings"
```

---

## Share This If Still Failing:

1. **Full backend log output** when you upload
2. **Error message** shown in Flutter app
3. **Your backend URL** from app_config.dart

Then I can pinpoint the exact issue!
