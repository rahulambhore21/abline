# Developer Quick Reference

## JWT Authentication System

### Quick Access

| Document | Purpose |
|----------|---------|
| **AUTH_QUICKSTART.md** | Start here - setup & examples |
| **AUTHENTICATION_GUIDE.md** | Deep dive - architecture & security |
| **AUTH_CHECKLIST.md** | Verification - all requirements |
| **This file** | Quick reference - copy-paste patterns |

---

## Copy-Paste Code Patterns

### 1. Backend: Protect an Endpoint

```javascript
// Add middleware chain to any route
app.post('/api/some-protected-route', authMiddleware, allowRole('host'), async (req, res) => {
  // req.user is now available with userId, username, role
  console.log(`Action by ${req.user.username} (${req.user.role})`);
  
  try {
    // Your route logic here
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
```

### 2. Backend: Allow Multiple Roles

```javascript
// Allow both host and admin roles
app.post('/api/admin-area', authMiddleware, allowRole('host', 'admin'), (req, res) => {
  // Only host or admin can access
  res.json({ message: 'Admin area accessed' });
});
```

### 3. Backend: Get User Info in Handler

```javascript
app.post('/api/action', authMiddleware, (req, res) => {
  const userId = req.user.userId;
  const username = req.user.username;
  const role = req.user.role;
  
  // Use these values as needed
  res.json({ userId, username, role });
});
```

### 4. Flutter: Store JWT After Login

```dart
Future<void> login(String username, String password) async {
  try {
    final response = await http.post(
      Uri.parse('http://localhost:5000/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String token = data['token'];
      String role = data['role'];
      
      // Store token (use secure_storage in production)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      await prefs.setString('user_role', role);
      
      // Navigate to dashboard
      Navigator.of(context).pushReplacementNamed('/dashboard');
    }
  } catch (e) {
    print('Login error: $e');
  }
}
```

### 5. Flutter: Use JWT in API Calls

```dart
Future<List<Recording>> fetchRecordings(String sessionId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    
    final response = await http.get(
      Uri.parse('http://localhost:5000/recordings?sessionId=$sessionId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',  // Important!
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.map((r) => Recording.fromJson(r)).toList();
    } else if (response.statusCode == 401) {
      // Token expired, redirect to login
      Navigator.of(context).pushReplacementNamed('/login');
    }
    return [];
  } catch (e) {
    print('Error: $e');
    return [];
  }
}
```

### 6. Flutter: Start Recording (Protected Route)

```dart
Future<void> startRecording() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    final response = await http.post(
      Uri.parse('http://localhost:5000/recording/start'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'channelName': widget.channelName,
        'uid': widget.uid,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording started')),
      );
    } else if (response.statusCode == 403) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Host privileges required')),
      );
    } else {
      final error = jsonDecode(response.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${error['message']}')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}
```

### 7. Flutter: Logout & Clear Token

```dart
Future<void> logout() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('auth_token');
  await prefs.remove('user_role');
  
  if (mounted) {
    Navigator.of(context).pushReplacementNamed('/login');
  }
}
```

---

## API Quick Reference

### Register Host (First Time Only)

```bash
curl -X POST http://localhost:5000/auth/register-host \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "securePassword123"
  }'
```

**Success Response (201):**
```json
{
  "success": true,
  "userId": "507f1f77bcf86cd799439011",
  "message": "Host 'admin' created successfully"
}
```

**Error Response (400):**
```json
{
  "error": "Bad Request",
  "message": "Host user already exists"
}
```

### Login

```bash
curl -X POST http://localhost:5000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "securePassword123"
  }'
```

**Success Response (200):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "role": "host",
  "userId": "507f1f77bcf86cd799439011",
  "expiresIn": "1d",
  "message": "Login successful"
}
```

**Error Response (401):**
```json
{
  "error": "Unauthorized",
  "message": "Invalid credentials"
}
```

### Create User (Host-Only)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:5000/auth/create-user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "username": "john",
    "password": "userPassword123"
  }'
```

**Success Response (201):**
```json
{
  "success": true,
  "userId": "507f1f77bcf86cd799439012",
  "message": "User 'john' created successfully"
}
```

**Error Response (403):**
```json
{
  "error": "Forbidden",
  "message": "This action requires one of these roles: host"
}
```

### Start Recording (Host-Only)

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:5000/recording/start \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "channelName": "test_room",
    "uid": 1
  }'
```

**Success Response (201):**
```json
{
  "success": true,
  "resourceId": "TOsCYpxkvDStVUIBRC0O...",
  "message": "Recording started"
}
```

**Error Response (403):**
```json
{
  "error": "Forbidden",
  "message": "This action requires one of these roles: host"
}
```

---

## Common Tasks

### Task 1: Add Authorization Header to Existing API

**Before:**
```dart
final response = await http.post(
  url,
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode(data),
);
```

**After:**
```dart
final prefs = await SharedPreferences.getInstance();
final token = prefs.getString('auth_token');

final response = await http.post(
  url,
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',  // Add this line
  },
  body: jsonEncode(data),
);
```

### Task 2: Protect a New Backend Endpoint

1. Add middleware chain to route:
```javascript
app.post('/api/new-endpoint', authMiddleware, allowRole('host'), async (req, res) => {
  // Your logic here
});
```

2. No other changes needed - authMiddleware handles JWT verification

### Task 3: Handle Token Expiry

```dart
if (response.statusCode == 401) {
  // Token expired or invalid
  // Clear stored token
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('auth_token');
  
  // Redirect to login
  Navigator.of(context).pushReplacementNamed('/login');
}
```

### Task 4: Check User Role

```dart
Future<bool> isUserHost() async {
  final prefs = await SharedPreferences.getInstance();
  String role = prefs.getString('user_role') ?? 'user';
  return role == 'host';
}

// Usage:
if (await isUserHost()) {
  // Show host-only features
} else {
  // Show limited features
}
```

### Task 5: Add Another Role

1. In User model, update role enum to include new role
2. Update middleware chain on protected routes
3. Example: `allowRole('host', 'moderator')`

---

## Debugging Tips

### "Missing Authorization header"
- Check header is spelled correctly
- Format must be: `Authorization: Bearer <token>`
- Token must be present in header, not in body

### "Invalid token"
- Token might be expired (check login response expiresIn)
- JWT_SECRET might be wrong (verify in .env)
- Token might be corrupted (copy-paste issue)

### "Forbidden - requires host role"
- Logged in user is not a host
- Check role returned from login
- Host can only be created via /auth/register-host

### "User already exists"
- Username must be unique
- Try login instead of register

### Test with curl first, then Flutter
1. Test auth endpoints with curl
2. Verify token works with curl
3. Then add to Flutter code
4. Easier to debug with curl

---

## Files to Know

| File | Purpose |
|------|---------|
| backend/app.js | Main auth logic (lines ~45-700) |
| backend/.env | Configuration (JWT_SECRET, etc.) |
| AUTHENTICATION_GUIDE.md | Complete reference |
| AUTH_QUICKSTART.md | Quick start |
| AUTH_CHECKLIST.md | Requirements verification |

---

## Environment Setup

```bash
# Linux/Mac - Generate strong secret
openssl rand -base64 32

# Windows PowerShell
[Convert]::ToBase64String((1..32 | ForEach-Object { [byte](Get-Random -Min 0 -Max 256) }))

# Put result in backend/.env
JWT_SECRET=<generated_string>
```

---

## Quick Test Suite

```bash
# 1. Register host
RESULT=$(curl -s -X POST http://localhost:5000/auth/register-host \
  -H "Content-Type: application/json" \
  -d '{"username":"testhost","password":"test123"}')
echo "Register: $RESULT"

# 2. Login
TOKEN=$(echo $RESULT | jq -r '.token' 2>/dev/null || echo "")
if [ -z "$TOKEN" ]; then
  TOKEN=$(curl -s -X POST http://localhost:5000/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"testhost","password":"test123"}' | jq -r '.token')
fi
echo "Token: $TOKEN"

# 3. Test protected route
curl -s -X POST http://localhost:5000/recording/start \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"channelName":"test","uid":1}' | jq .

# 4. Test without token (should fail)
curl -s -X POST http://localhost:5000/recording/start \
  -H "Content-Type: application/json" \
  -d '{"channelName":"test","uid":1}' | jq .
```

---

**Version**: 1.0
**Last Updated**: JWT Authentication Complete
**Status**: Production Ready ✅
