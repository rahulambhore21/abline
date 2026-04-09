# JWT Authentication Quick Setup

## What Was Implemented ✅

Complete JWT + Role-Based Access Control system for the Agora backend.

### Features
- ✅ User registration (host-only, first user)
- ✅ User creation (host-only, create normal users)
- ✅ JWT-based login
- ✅ Password hashing with bcryptjs
- ✅ Role-based middleware (host, user)
- ✅ Protected recording endpoints (host-only)
- ✅ Error handling with clear messages

### Architecture
```
User → /auth/login → JWT Token → Authorization: Bearer <token>
                          ↓
                    authMiddleware (verify JWT)
                          ↓
                    allowRole() (check role)
                          ↓
                    Route Handler (req.user available)
```

## Quick Start

### 1. Install Dependencies
```bash
cd backend
npm install
# bcryptjs and jsonwebtoken are now in package.json
```

### 2. Configure .env
Edit `backend/.env`:
```env
JWT_SECRET=your-strong-secret-key-here
JWT_EXPIRY=1d
MONGODB_URI=mongodb://localhost:27017/agora
```

### 3. Start Server
```bash
npm start
```

Server will log all available endpoints including auth routes.

## API Flow

### 1. Register Host (First Time)
```bash
curl -X POST http://localhost:5000/auth/register-host \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password123"}'
```

**Response:**
```json
{
  "success": true,
  "userId": "...",
  "message": "Host 'admin' created successfully"
}
```

### 2. Login to Get Token
```bash
curl -X POST http://localhost:5000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password123"}'
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "role": "host",
  "userId": "...",
  "expiresIn": "1d"
}
```

### 3. Use Token for Protected Routes
```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

curl -X POST http://localhost:5000/recording/start \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"channelName":"test_room","uid":1}'
```

### 4. Create Users (Host-Only)
```bash
curl -X POST http://localhost:5000/auth/create-user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"username":"user1","password":"password123"}'
```

## Role-Based Access

### Host Can:
- ✅ Start recordings (`POST /recording/start`)
- ✅ Stop recordings (`POST /recording/stop`)
- ✅ Create users (`POST /auth/create-user`)
- ✅ View dashboard

### User Can:
- ✅ Join calls
- ✅ Access non-protected endpoints
- ❌ Cannot start/stop recordings
- ❌ Cannot create users

## Code Structure

### Embedded in backend/app.js

**User Model** (lines ~45-95)
```javascript
const UserSchema = new mongoose.Schema({
  username: { type: String, unique: true, ... },
  password: { type: String, ... },
  role: { enum: ['host', 'user'], ... }
})
```

**Authentication Middleware** (lines ~96-160)
```javascript
const authMiddleware = (req, res, next) => { ... }
const allowRole = (...roles) => { ... }
```

**Auth Endpoints** (lines ~488-700)
- `POST /auth/register-host` - Create first host
- `POST /auth/login` - Get JWT token
- `POST /auth/create-user` - Create normal user

**Protected Routes** (lines ~808+)
- `POST /recording/start` - Now requires auth + host
- `POST /recording/stop` - Now requires auth + host

## Environment Variables

Add to `backend/.env`:

```env
# JWT Configuration
JWT_SECRET=generate-strong-random-string
JWT_EXPIRY=1d

# Example strong secret (use this format):
# JWT_SECRET=7k#mP9@xQ2$wL4&bN8*vC5(zH3)fG6!jR0+sT1-uY7^vW9.dE2~aF4!gH6#iJ8$kL0%mN2&oP4*qR6(sT8)uV0+
```

## Testing

### Test as Host
```bash
# 1. Register
curl -X POST http://localhost:5000/auth/register-host \
  -H "Content-Type: application/json" \
  -d '{"username":"testhost","password":"test123"}'

# 2. Login
TOKEN=$(curl -s -X POST http://localhost:5000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testhost","password":"test123"}' | jq -r '.token')

# 3. Start recording (should work)
curl -X POST http://localhost:5000/recording/start \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"channelName":"test","uid":1}'
```

### Test as User
```bash
# 1. Create user (as host with TOKEN from above)
curl -X POST http://localhost:5000/auth/create-user \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"test123"}'

# 2. Login as user
USER_TOKEN=$(curl -s -X POST http://localhost:5000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"test123"}' | jq -r '.token')

# 3. Try to start recording (should get 403 Forbidden)
curl -X POST http://localhost:5000/recording/start \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"channelName":"test","uid":1}'

# Response: 403 Forbidden
# {
#   "error": "Forbidden",
#   "message": "This action requires one of these roles: host"
# }
```

## Integration with Flutter

In `dashboard_screen.dart`, add JWT to API calls:

```dart
Future<void> _toggleRecording() async {
  try {
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.jwtToken}',  // Add this
      },
      body: jsonEncode({...}),
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      // Success
    } else if (response.statusCode == 403) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Host privileges required')),
      );
    }
  } catch (e) {
    print('Error: $e');
  }
}
```

## Error Reference

| Status | Error | Meaning |
|--------|-------|---------|
| 400 | Missing fields | username or password not provided |
| 400 | Username already taken | User already exists |
| 400 | Host user already exists | Trying to create second host |
| 401 | Invalid credentials | Wrong password or user not found |
| 401 | Invalid token | JWT verification failed |
| 401 | Token expired | JWT expired (re-login needed) |
| 403 | Forbidden | User role doesn't have permission |

## Security Notes

1. **JWT_SECRET** - Change from default in production!
   ```bash
   # Generate random secret:
   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```

2. **HTTPS Only** - Always use HTTPS in production (never HTTP)

3. **Token Storage** - Store token securely:
   - Flutter: Use secure_storage package (not just SharedPreferences)
   - Web: HttpOnly cookies (if using web backend)

4. **Password Requirements**
   - Minimum 6 characters
   - Hashed with bcryptjs (10 salt rounds)

5. **Expiry** - Default 1 day, adjust JWT_EXPIRY for your use case

## Documentation

Full details in `AUTHENTICATION_GUIDE.md`:
- Complete API reference
- Architecture deep dive
- Code examples
- Troubleshooting

## What's Protected Now

- ✅ `POST /recording/start` → host-only
- ✅ `POST /recording/stop` → host-only
- ✅ `POST /auth/create-user` → host-only

## What's Still Open

- `POST /agora/token` - Public (needed for joining calls)
- `GET /session/:id/users` - Public
- `POST /events/speaking` - Public
- `GET /events/speaking` - Public
- `GET /recordings` - Public

You can protect these further if needed.

## Next Steps

1. Test auth flow locally
2. Update Flutter dashboard to send JWT in headers
3. Set strong JWT_SECRET for production
4. Configure Cloud Recording storage in .env
5. Deploy to production with HTTPS
