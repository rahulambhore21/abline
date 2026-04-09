# 🚀 Quick Setup Guide - Frontend Authentication

## 5-Minute Setup

### Step 1: Install Flutter Dependencies (2 min)

```bash
cd app
flutter pub get
```

This installs `shared_preferences` for token storage.

### Step 2: Start Backend (1 min)

```bash
cd backend
npm install  # If not already done
npm start
```

Expected output:
```
🚀 Server running on port 5000
Auth system initialized
```

### Step 3: Run Flutter App (1 min)

```bash
cd app
flutter run
```

App starts with **LoginScreen** ✓

### Step 4: Register & Login (1 min)

**First Time - Register Host:**
1. Toggle to "First time? Register as Host"
2. Enter: username = `admin`, password = `admin123`
3. Click "Register Host"
4. See success message

**Then - Login:**
1. Username = `admin`, password = `admin123`
2. Click "Login"
3. **HomeScreen appears** ✓

## What You'll See

### LoginScreen
```
┌─────────────────────────────┐
│    Login or Register         │
├─────────────────────────────┤
│ Username: [_____________]  │
│ Password: [_____________]  │
│                              │
│ [Login Button]              │
│                              │
│ "First time? Register..."   │
└─────────────────────────────┘
```

### HomeScreen (After Login)
```
┌──────────────────────────────────┐
│ Agora Voice System    admin  [🚪] │
├──────────────────────────────────┤
│                                   │
│ Welcome, admin!                  │
│ You are logged in as: HOST       │
│ ✓ You have host privileges       │
│                                   │
│ Navigation                        │
│ ┌──────────────────────────────┐ │
│ │ 📞 Voice Call                │ │
│ │ Join or start a voice call   │ │
│ │                            → │ │
│ └──────────────────────────────┘ │
│                                   │
│ ┌──────────────────────────────┐ │
│ │ 📊 Dashboard                 │ │
│ │ Manage sessions & recordings │ │
│ │                            → │ │
│ └──────────────────────────────┘ │
│                                   │
│ Available Features               │
│ 📹 Recording Control ... ✓        │
│ 👥 User Management ...  ✓        │
│ ℹ️ Dashboard ...        ✓        │
│                                   │
│ 🔒 Your session is protected    │
│ Token expires in 24 hours       │
└──────────────────────────────────┘
```

### Dashboard (After Clicking)
```
┌─────────────────────────────┐
│ Host Dashboard         [←]  │
├─────────────────────────────┤
│                              │
│ Session: test_room          │
│ [Start Recording] [Stop]     │  ← Now with JWT! ✓
│                              │
│ Users (connected)           │
│ ├─ admin (🟢 speaking)      │
│ ├─ user1 (⚫ silent)        │
│                              │
│ Timeline                    │
│ admin  ────█████──── │      │
│ user1  ──────███─────│      │
│                              │
│ Recordings                  │
│ [Play] admin_rec1.mp3      │
│ [Play] user1_rec1.mp3      │
└─────────────────────────────┘
```

## Verify It's Working

### Check 1: Token Storage
```bash
# Token is stored locally (you can't see it in code)
# But you can verify by:
# 1. Login
# 2. Stop app
# 3. Reopen app
# → Should still be logged in (no LoginScreen)
```

### Check 2: JWT in Requests
```bash
# Open app developer console or use API tools
# You should see request headers:
# Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Check 3: Role-Based UI
**Login as host:**
- Recording Control card: ✓ (checkmark, enabled)

**Create user and login as user:**
```bash
# Backend: Create user
curl -X POST http://localhost:5000/auth/create-user \
  -H "Authorization: Bearer <host_token>" \
  -H "Content-Type: application/json" \
  -d '{"username":"user1","password":"user123"}'
```

Then login as user1:
- Recording Control card: 🔒 (lock, disabled)

## Common Issues & Fixes

### Issue: "Failed to connect to backend"
**Fix:** Verify backend is running
```bash
# Check backend logs
cd backend
npm start
# Should show: 🚀 Server running on port 5000
```

### Issue: "Username already exists"
**Fix:** Use different username for each test
```bash
# Use: admin, testuser, john, etc.
# Not: admin (if already registered)
```

### Issue: "Host user already exists"
**Fix:** Only one host allowed
```bash
# Clear MongoDB or use different username
# Or just use "admin" for all tests
```

### Issue: "Missing authorization header" when recording
**Fix:** Verify you're logged in
```dart
// In dashboard_screen.dart, jwtToken should not be null
print('JWT Token: ${widget.jwtToken}');
```

### Issue: "Host privileges required" for host user
**Fix:** Verify user is host
```bash
# Check login response has role: "host"
# Verify token includes role field
```

### Issue: "Token expired" after 24 hours
**Fix:** Re-login
```bash
# App redirects to LoginScreen automatically
# Or reduce JWT_EXPIRY in .env for testing:
JWT_EXPIRY=1h  # 1 hour instead of 1 day
```

## Testing Scenarios

### Scenario 1: Register & Login (5 min)
```
1. Open app → LoginScreen
2. Register host (admin/admin123)
3. See success message
4. Login (admin/admin123)
5. See HomeScreen ✓
```

### Scenario 2: View Dashboard (3 min)
```
1. From HomeScreen
2. Click "View Dashboard"
3. See real-time data ✓
4. JWT being sent behind scenes ✓
```

### Scenario 3: Start Recording (5 min)
```
1. In Dashboard
2. Click "Start Recording"
3. See "Recording started" ✓
4. JWT required for this! ✓
```

### Scenario 4: Role-Based UI (10 min)
```
1. Login as host
   - See Recording Control enabled ✓
2. Logout
3. Create user (see "Common Issues")
4. Login as user
   - See Recording Control disabled 🔒
5. Try to click it
   - See "Host privileges required" ✗
```

### Scenario 5: Token Expiry (testing)
```
1. Set JWT_EXPIRY=5s (5 seconds) in .env
2. Restart backend
3. Login
4. Wait 6 seconds
5. Click any API button
6. See "Session expired, please login"
7. Redirect to LoginScreen ✓
```

## Files to Know

```
app/lib/
├── main.dart                    ← Auth routing starts here
├── auth_service.dart            ← Token management
├── login_screen.dart            ← Login/register UI
├── home_screen.dart             ← Authenticated home
├── dashboard_screen.dart        ← Uses JWT in requests
└── other files (unchanged)

backend/
├── app.js                       ← Auth endpoints + middleware
├── package.json                 ← bcryptjs, jsonwebtoken
└── .env                         ← JWT_SECRET, JWT_EXPIRY
```

## Configuration

### Change Backend URL (For Production)

**main.dart:**
```dart
class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: 'https://your-domain.com');
    // Change localhost to production URL
  }
}
```

**login_screen.dart:**
```dart
const LoginScreen({super.key, required this.backendUrl});
// Update when calling: LoginScreen(backendUrl: 'https://...')
```

**home_screen.dart:**
```dart
_authService = AuthService(backendUrl: 'https://your-domain.com');
```

## Production Checklist

- [ ] Backend JWT_SECRET changed from default
- [ ] Frontend backendUrl uses HTTPS
- [ ] MongoDB connection verified
- [ ] Agora credentials in .env
- [ ] CORS configured for your domain
- [ ] Flutter app built as release
- [ ] Tested on actual device
- [ ] Rate limiting added to login endpoint

## What's Different Now

### Before
```
LoginScreen → Dashboard (no auth)
All API calls open (no JWT)
Anyone could access anything
```

### After
```
AuthWrapper → Check token → LoginScreen or HomeScreen
Dashboard sends JWT in every request
Backend validates token + role
Only authorized users can access protected features
```

## Support

See full documentation:
- **END_TO_END_AUTH_COMPLETE.md** - Complete architecture
- **FRONTEND_AUTH_IMPLEMENTATION.md** - Frontend details
- **AUTHENTICATION_GUIDE.md** - Backend details
- **DEVELOPER_QUICK_REFERENCE.md** - Copy-paste code

---

## TL;DR - Just Run These Commands

```bash
# Terminal 1: Backend
cd backend
npm install
npm start

# Terminal 2: Flutter (after backend is running)
cd app
flutter pub get
flutter run

# In app:
# 1. Register host (admin/admin123)
# 2. Login
# 3. View Dashboard
# 4. Start recording
# Done! ✓
```

**That's it! Full authentication working end-to-end.** 🎉
