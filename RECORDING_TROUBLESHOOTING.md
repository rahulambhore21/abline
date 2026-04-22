# 🎙️ Recording Not Working - Troubleshooting Guide

## Issue: Nothing gets recorded

This guide will help you diagnose and fix the recording problem.

---

## Step 1: Verify Agora Cloud Recording is ENABLED ⚠️ **CRITICAL**

The #1 reason recordings don't work is **Cloud Recording not enabled on your Agora account**.

### How to check:
1. Go to https://console.agora.io
2. Login with your account
3. Click on your Project
4. Go to **Features** or **Manage Project**
5. Look for **"Cloud Recording"** - it should show as **ENABLED**

### If it's NOT enabled:
1. Click **Enable** next to Cloud Recording
2. Wait 2-3 minutes for it to activate
3. Then test recording again

❌ **Without this, recordings WILL NOT WORK** ❌

---

## Step 2: Verify AWS S3 Setup

### A. Check if bucket exists and is accessible

1. Go to https://console.aws.amazon.com/s3/
2. Look for bucket: `agora-recordings-rahul`
3. If it doesn't exist, create it:
   - Click "Create Bucket"
   - Name: `agora-recordings-rahul`
   - Region: `us-east-1` (or your preferred region)
   - Click "Create"

### B. Verify IAM credentials have S3 access

Your AWS Access Key: `AKIA6JTG4ZK2P53PXJ45`

1. Go to https://console.aws.amazon.com/iam/
2. Click on **Users**
3. Find the user associated with that Access Key
4. Go to **Permissions**
5. Make sure they have **AmazonS3FullAccess** or similar policy

If missing:
1. Click "Add permissions" → "Attach policies directly"
2. Search for "S3"
3. Select "AmazonS3FullAccess"
4. Click "Add permissions"

---

## Step 3: Test the Backend Recording API

### Run the diagnostic test (already done ✅)

```bash
cd backend
node test-recording-setup.js
```

### Test the recording endpoint

1. **Start the backend server:**
   ```bash
   npm run start
   ```
   You should see: `✅ Agora RTC Token Server running on http://localhost:5000`

2. **Get a host JWT token** (in another terminal):
   ```bash
   curl -X POST http://localhost:5000/auth/login \
     -H "Content-Type: application/json" \
     -d '{"username":"host_user","password":"password123"}'
   ```
   Save the `token` from the response

3. **Test recording** with the token:
   ```bash
   curl -X POST http://localhost:5000/test/recording \
     -H "Authorization: Bearer YOUR_TOKEN_HERE" \
     -H "Content-Type: application/json" \
     -d '{"channelName":"test_room"}'
   ```

### What to look for:

✅ **SUCCESS** - You should see:
```json
{
  "success": true,
  "resourceId": "...",
  "sid": "...",
  "message": "Recording test successful!"
}
```

❌ **FAILURE** - Common errors:

| Error | Cause | Fix |
|-------|-------|-----|
| `401 Unauthorized` | Cloud Recording not enabled on Agora | Enable in Agora Console |
| `Invalid credentials` | Agora customer ID/secret wrong | Check `.env` AGORA_CUSTOMER_* |
| `Cloud Recording storage is not configured` | S3 credentials wrong | Check `.env` RECORDING_* |
| `Access Denied` to S3 | AWS IAM permissions missing | Add S3 policy to IAM user |
| `NoSuchBucket` | S3 bucket doesn't exist | Create bucket: `agora-recordings-rahul` |

---

## Step 4: Check Backend Logs

When you test, watch the backend terminal for detailed error messages.

Key lines to look for:
- `❌ Acquire recording failed:` - Agora Cloud Recording issue
- `❌ Start recording failed:` - S3 or configuration issue  
- `✅ Recording acquired` / `✅ Recording started` - Success!

---

## Step 5: Test End-to-End in the App

1. Start backend: `npm run start`
2. Login to Flutter app
3. Host user: Join room
4. Non-host user: Join room
5. Recording should start automatically
6. You should see "🔴 RECORDING ACTIVE" indicator

If nothing appears:
- Check backend logs for errors
- Make sure you're logged in as HOST (recording starts on host session start)
- Check that both users are actually connected

---

## Common Causes & Fixes

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| No "RECORDING ACTIVE" indicator | Recording failed silently | Check Agora Cloud Recording is ENABLED |
| "Waiting for Host" message | Session not started | Host must tap "Join Room" first |
| Recordings not uploaded after recording | File upload endpoint not working | Check `express-fileupload` installed (just did ✅) |
| Recordings visible in admin but no files | S3 bucket not accessible | Verify AWS credentials and bucket |
| Token errors | JWT expired or invalid | Login again to get fresh token |

---

## Quick Checklist

- [ ] ✅ Configuration test passed (`npm run test-recording-setup.js`)
- [ ] ☐ Agora Cloud Recording is ENABLED on console.agora.io
- [ ] ☐ AWS S3 bucket `agora-recordings-rahul` exists
- [ ] ☐ AWS IAM user has S3 full access
- [ ] ☐ Backend starts without errors (`npm run start`)
- [ ] ☐ Recording test endpoint works (`POST /test/recording`)
- [ ] ☐ Host and user both connected in app
- [ ] ☐ "RECORDING ACTIVE" indicator shows

---

## If Still Not Working

Please provide:
1. Backend server startup output
2. Backend logs when recording fails
3. Error from `POST /test/recording` endpoint
4. Screenshot of Agora Console showing Cloud Recording status
5. Screenshot of AWS S3 console showing the bucket

Then we can diagnose the exact issue.
