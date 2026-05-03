const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;

const authMiddleware = (req, res, next) => {
  if (!JWT_SECRET) {
    console.error('FATAL: JWT_SECRET environment variable is not set.');
    return res.status(500).json({
      error: 'Configuration Error',
      message: 'Server is missing critical security configuration.',
    });
  }

  try {
    const authHeader = req.headers.authorization;
    let token = '';

    if (authHeader && authHeader.startsWith('Bearer ')) {
      token = authHeader.slice(7);
    }

    if (!token) {
      return res.status(401).json({
        error: 'Missing or invalid authentication',
        message: 'Provide token via Authorization: Bearer <token> header',
      });
    }

    const decoded = jwt.verify(token, JWT_SECRET);

    req.user = {
      userId: decoded.userId,
      username: decoded.username,
      role: decoded.role,
    };

    next();
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({
        error: 'Invalid token',
        message: 'JWT verification failed',
      });
    }

    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({
        error: 'Token expired',
        message: 'Please login again',
      });
    }

    res.status(401).json({
      error: 'Authentication failed',
      message: error.message,
    });
  }
};

const allowRole = (...allowedRoles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        error: 'Not authenticated',
        message: 'Please login first',
      });
    }

    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({
        error: 'Forbidden',
        message: `This action requires one of these roles: ${allowedRoles.join(', ')}`,
        yourRole: req.user.role,
      });
    }

    next();
  };
};

module.exports = { authMiddleware, allowRole };
