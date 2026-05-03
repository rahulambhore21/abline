const logger = require('../utils/logger');

/**
 * Middleware to validate request data against a Joi schema.
 * @param {Object} schema - Joi schema object
 * @param {String} property - Request property to validate (body, query, params)
 */
const validate = (schema, property = 'body') => {
  return (req, res, next) => {
    const { error } = schema.validate(req[property], { 
      abortEarly: false,
      stripUnknown: true, // Remove fields not defined in schema
    });

    if (error) {
      const errors = error.details.map((detail) => ({
        field: detail.path.join('.'),
        message: detail.message.replace(/['"]/g, ''),
      }));
      
      logger.warn('Validation Failure', { 
        path: req.path, 
        method: req.method,
        errors, 
        userId: req.user?.userId 
      });

      return res.status(400).json({
        error: 'Validation Error',
        message: 'The request payload is invalid.',
        details: errors,
      });
    }
    next();
  };
};

module.exports = validate;
