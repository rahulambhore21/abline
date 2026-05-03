const errorHandler = (err, req, res, _next) => {
  console.error('❌ Error:', err.stack);

  const status = err.status || 500;
  const message = err.message || 'Internal Server Error';

  res.status(status).json({
    error: err.name || 'Error',
    message: message,
  });
};

module.exports = errorHandler;
