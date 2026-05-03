const Joi = require('joi');

const schemas = {
  // Auth Schemas
  auth: {
    login: Joi.object({
      username: Joi.string().required().trim().min(3).max(30),
      password: Joi.string().required(),
    }),
    register: Joi.object({
      username: Joi.string().required().trim().min(3).max(30),
      password: Joi.string().required().min(6),
      role: Joi.string().valid('user', 'host').default('user'),
    }),
    updateUser: Joi.object({
      username: Joi.string().trim().min(3).max(30),
      password: Joi.string().min(6),
      role: Joi.string().valid('user', 'host'),
      isActive: Joi.boolean(),
    }),
    deleteUser: Joi.object({
      pin: Joi.string().required(),
    }),
  },

  // Recording Schemas
  recording: {
    start: Joi.object({
      channelName: Joi.string().required().trim(),
      uid: Joi.number().required(),
    }),
    stop: Joi.object({
      channelName: Joi.string().required().trim(),
      resourceId: Joi.string(),
      sid: Joi.string(),
    }),
    save: Joi.object({
      userId: Joi.number().required(),
      username: Joi.string().required().trim(),
      sessionId: Joi.string().required().trim(),
      durationMs: Joi.number().min(0).required(),
      url: Joi.string().uri().required(),
      filename: Joi.string().required().trim(),
    }),
    requestUrl: Joi.object({
      filename: Joi.string().required().trim(),
      contentType: Joi.string().required().trim(),
    }),
    list: Joi.object({
      userId: Joi.string(),
      sessionId: Joi.string(),
      page: Joi.number().integer().min(1).default(1),
      limit: Joi.number().integer().min(1).max(100).default(50),
      verify: Joi.boolean().default(true),
    }),
  },

  // Session Schemas
  session: {
    start: Joi.object({
      channelName: Joi.string().required().trim(),
    }),
    addUser: Joi.object({
      userId: Joi.number().required(),
      username: Joi.string().required().trim(),
      role: Joi.string().valid('user', 'host').required(),
    }),
    speakingEvent: Joi.object({
      sessionId: Joi.string().required(),
      userId: Joi.number().required(),
      username: Joi.string().required(),
      type: Joi.string().valid('start', 'stop').required(),
      timestamp: Joi.date().iso().required(),
    }),
  }
};


module.exports = schemas;
