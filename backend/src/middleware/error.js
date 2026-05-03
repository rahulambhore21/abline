const logger = require('../utils/logger');

const errorHandler = (err, req, res, _next) => {
  const status = err.status || 500;
  const message = err.message || 'Internal Server Error';

  // Log structured error
  logger.error(message, {
    status,
    path: req.path,
    method: req.method,
    ip: req.ip,
    userId: req.user?.userId,
    username: req.user?.username,
    stack: err.stack,
    // Sensitive fields like password or PIN should already be redacted or not present in req.body at this point,
    // but we can be explicit if needed.
  });

  res.status(status).json({
    error: err.name || 'Error',
    message: message,
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
  });
};

module.exports = errorHandler;

