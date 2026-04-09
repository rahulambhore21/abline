# JWT Authentication & Role-Based Access Control

## Overview

This backend now implements **JWT-based authentication** with **role-based access control (RBAC)**. The system supports two roles:
- **Host**: Can start/stop recordings, create users, view dashboards
- **User**: Normal participants in voice calls

## Architecture

### Authentication Flow

```
1. User Registration (Host)
   POST /auth/register-host
   { username, password }
   ↓
   Backend creates first host user (password hashed with bcryptjs)

2. User Creation (Host)
   POST /auth/create-user
   { username, password }
   ↓
   Backend creates normal user (role: "user")

3. Login
   POST /auth/login
   { username, password }
   ↓
   Backend verifies credentials → generates JWT token
   Returns: { token, role, userId, expiresIn }

4. Protected Routes
   Client sends: Authorization: Bearer <token>
   ↓
   authMiddleware extracts & verifies JWT
   ↓
   If valid → continue; if invalid → 401 Unauthorized

5. Role Checks
   allowRole('host') middleware checks user.role
   ↓
   If authorized → continue; if not → 403 Forbidden
```

### Password Security (bcryptjs)

```
Registration/Creation:
  plainPassword → bcrypt.hash() → salted hash
  ↓
  Stored in MongoDB (never plain password!)

Login:
  plainPassword + storedHash → bcrypt.compare()
  ↓
  Returns true/false
```

### JWT Token Structure

```
Header:
{
  "alg": "HS256",
  "typ": "JWT"
}

Payload (signed & secret):
{
  "userId": "507f1f77bcf86cd799439011",
  "username": "host_user",
  "role": "host",
  "exp": 1234567890,      // Expiration time
  "iat": 1234567890       // Issued at
}

Signature:
HMACSHA256(base64(header) + "." + base64(payload), JWT_SECRET)
```

## API Endpoints

### Authentication

#### POST /auth/register-host
Create the first host user (only one host can exist).

**Request:**
```json
{
  "username": "admin",
  "password": "securePassword123"
}
```

**Response (201):**
```json
{
  "success": true,
  "userId": "507f1f77bcf86cd799439011",
  "message": "Host 'admin' created successfully"
}
```

**Error (400):**
```json
{
  "error": "Host user already exists",
  "message": "A host user has already been registered"
}
```

#### POST /auth/create-user
Create a normal user (host-only).

**Headers:**
```
Authorization: Bearer <host_jwt_token>
```

**Request:**
```json
{
  "username": "user1",
  "password": "password123"
}
```

**Response (201):**
```json
{
  "success": true,
  "userId": "507f1f77bcf86cd799439012",
  "message": "User 'user1' created successfully"
}
```

**Error (403):**
```json
{
  "error": "Forbidden",
  "message": "This action requires one of these roles: host",
  "yourRole": "user"
}
```

#### POST /auth/login
Authenticate and get JWT token.

**Request:**
```json
{
  "username": "admin",
  "password": "securePassword123"
}
```

**Response (200):**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "role": "host",
  "userId": "507f1f77bcf86cd799439011",
  "username": "admin",
  "expiresIn": "1d",
  "message": "Login successful"
}
```

**Error (401):**
```json
{
  "error": "Invalid credentials",
  "message": "Username not found"
}
```

### Protected Endpoints

#### POST /recording/start (Host-Only)
Start recording (now requires JWT + host role).

**Headers:**
```
Authorization: Bearer <host_jwt_token>
```

**Request:**
```json
{
  "channelName": "test_room",
  "uid": 1
}
```

**Response (201):**
```json
{
  "resourceId": "TOsCYpxkvDStVUIBRC0OsZCs...",
  "sid": "1234567890",
  "message": "Recording started successfully"
}
```

**Error (401):**
```json
{
  "error": "Missing or invalid Authorization header",
  "message": "Expected format: Authorization: Bearer <token>"
}
```

**Error (403):**
```json
{
  "error": "Forbidden",
  "message": "This action requires one of these roles: host",
  "yourRole": "user"
}
```

#### POST /recording/stop (Host-Only)
Stop recording (now requires JWT + host role).

**Headers:**
```
Authorization: Bearer <host_jwt_token>
```

**Request:**
```json
{
  "channelName": "test_room"
}
```

**Response (200):**
```json
{
  "success": true,
  "message": "Recording stopped successfully"
}
```

## Middleware

### authMiddleware

Verifies JWT token and attaches user info to request.

```javascript
// Extracts token from Authorization header
// Verifies signature with JWT_SECRET
// If valid: req.user = { userId, username, role }
// If invalid: returns 401
```

**Usage:**
```javascript
app.post('/protected', authMiddleware, (req, res) => {
  console.log(req.user.username); // User info available
});
```

### allowRole(...roles)

Checks if user has one of the specified roles.

```javascript
// Higher-order middleware: returns middleware
// Checks req.user.role against allowed roles
// If authorized: proceeds to handler
// If not: returns 403
```

**Usage:**
```javascript
app.post('/admin', authMiddleware, allowRole('host'), (req, res) => {
  // Only host can access
});

app.post('/any', authMiddleware, allowRole('host', 'user'), (req, res) => {
  // Both host and user can access
});
```

## Setup & Configuration

### 1. Install Dependencies
```bash
npm install bcryptjs jsonwebtoken
```

### 2. Configure Environment Variables
Edit `backend/.env`:

```env
# JWT Configuration
JWT_SECRET=your-super-secret-key-change-in-production
JWT_EXPIRY=1d

# MongoDB
MONGODB_URI=mongodb://localhost:27017/agora

# Agora
AGORA_APP_ID=...
AGORA_APP_CERTIFICATE=...
```

**Important:** Change `JWT_SECRET` to a strong random string in production:
```bash
# Generate a strong secret (Linux/Mac)
openssl rand -base64 32
```

### 3. Start Backend
```bash
npm start
# or
npm run dev  # watch mode
```

## Usage Examples

### Example 1: Register Host & Create User

```bash
# 1. Register host
curl -X POST http://localhost:5000/auth/register-host \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# Response:
# {
#   "success": true,
#   "userId": "507f1f77bcf86cd799439011",
#   "message": "Host 'admin' created successfully"
# }

# 2. Login as host
curl -X POST http://localhost:5000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'

# Response:
# {
#   "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
#   "role": "host",
#   "userId": "507f1f77bcf86cd799439011",
#   ...
# }

# 3. Create user (as host)
curl -X POST http://localhost:5000/auth/create-user \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -d '{"username":"user1","password":"user123"}'

# Response:
# {
#   "success": true,
#   "userId": "507f1f77bcf86cd799439012",
#   "message": "User 'user1' created successfully"
# }
```

### Example 2: Start Recording (Host-Only)

```bash
# 1. Login
TOKEN=$(curl -s -X POST http://localhost:5000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}' | jq -r '.token')

# 2. Start recording (with JWT)
curl -X POST http://localhost:5000/recording/start \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"channelName":"test_room","uid":1}'

# If user tries to start recording:
# Response: 403 Forbidden
# {
#   "error": "Forbidden",
#   "message": "This action requires one of these roles: host"
# }
```

### Example 3: Using JWT with Flutter Dashboard

In `dashboard_screen.dart`, add JWT to requests:

```dart
// 1. Store token after login (from auth server)
String token = loginResponse['token'];

// 2. Use token in dashboard API calls
final response = await http.post(
  url,
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',  // Add this
  },
  body: jsonEncode(body),
);
```

## Security Best Practices

1. **JWT Secret**
   - Use strong, random secret (32+ characters)
   - Store in environment variables (never in code)
   - Rotate periodically in production

2. **Token Expiry**
   - Default: 1 day
   - Shorter expiry = more frequent re-login (more secure)
   - Implement refresh tokens for longer sessions

3. **HTTPS**
   - Always use HTTPS in production (never HTTP)
   - Tokens are base64-encoded but not encrypted
   - HTTPS provides transport security

4. **Password Storage**
   - Always hash passwords (bcryptjs does this)
   - Never log or return plain passwords
   - Enforce minimum password length (6+ characters)

5. **CORS**
   - Backend already has CORS enabled
   - Restrict to specific origins in production

## Token Lifecycle

```
1. User logs in → JWT generated with exp (1 day from now)
2. Token returned to client
3. Client stores token (localStorage, session storage, etc.)
4. Client includes token in Authorization header
5. Server verifies token on each protected request
6. If token expired → 401, client should re-login
7. If token valid → request proceeds with req.user available
```

## Troubleshooting

### "Missing or invalid Authorization header"
- Ensure token is in header: `Authorization: Bearer <token>`
- Check for typos or missing "Bearer " prefix

### "Invalid token" / "JWT verification failed"
- Token may be corrupted
- Try logging in again to get a fresh token
- Check JWT_SECRET matches between server restart

### "Token expired"
- Token's 1-day expiration has passed
- User must log in again
- Consider implementing refresh tokens for UX

### "Forbidden" / "role mismatch"
- User doesn't have required role
- Only hosts can start/stop recordings
- Only hosts can create users

## Code Comments Reference

The implementation includes detailed comments explaining:
- **JWT flow**: Token generation, verification, expiration
- **Password hashing**: bcryptjs pre-save middleware
- **Role-based access**: Middleware chain for RBAC
- **Error handling**: Specific error messages for debugging
- **Payload structure**: What information is in the JWT

Search the code for comments starting with "JWT", "Password", "Role", etc.

## Files Modified

- `backend/app.js`: Added User model, auth middleware, auth endpoints, protected routes
- `backend/package.json`: Added bcryptjs, jsonwebtoken dependencies
- `backend/.env`: Added JWT_SECRET, JWT_EXPIRY configuration

## Next Steps (Optional Enhancements)

1. **Refresh Tokens**: Implement token refresh endpoint for longer sessions
2. **Rate Limiting**: Add rate limiting to auth endpoints (prevent brute force)
3. **Email Verification**: Require email for user registration
4. **Two-Factor Authentication**: Add 2FA for extra security
5. **Audit Logging**: Log all authentication events for security
6. **Password Reset**: Implement forgot password flow
