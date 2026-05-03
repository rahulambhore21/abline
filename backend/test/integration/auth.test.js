const request = require('supertest');
const app = require('../../app');
const User = require('../../src/models/User');
const mongoose = require('mongoose');

jest.mock('../../src/models/User');

describe('Auth Integration Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Default mock behavior for mongoose connection
    Object.defineProperty(mongoose.connection, 'readyState', { value: 1, writable: true });
    process.env.MONGODB_URI = 'mongodb://localhost:27017/test';
  });

  describe('GET /auth/host', () => {
    it('should return host username if host exists', async () => {
      User.findOne.mockReturnValue({
        select: jest.fn().mockReturnThis(),
        lean: jest.fn().mockResolvedValue({ username: 'prakash_kaka' }),
      });

      const res = await request(app).get('/auth/host');

      expect(res.statusCode).toEqual(200);
      expect(res.body).toHaveProperty('username', 'prakash_kaka');
    });

    it('should return null if no host exists', async () => {
      User.findOne.mockReturnValue({
        select: jest.fn().mockReturnThis(),
        lean: jest.fn().mockResolvedValue(null),
      });

      const res = await request(app).get('/auth/host');

      expect(res.statusCode).toEqual(200);
      expect(res.body).toHaveProperty('username', null);
    });
  });

  describe('POST /auth/login', () => {
    it('should return 400 if missing fields', async () => {
      const res = await request(app).post('/auth/login').send({ username: 'test' });

      expect(res.statusCode).toEqual(400);
      expect(res.body).toHaveProperty('error', 'Validation Error');
      expect(res.body.details[0]).toHaveProperty('field', 'password');
    });
  });

});
