const { ensureMongoForAuth } = require('../src/utils/dbHelpers');
const mongoose = require('mongoose');

jest.mock('mongoose', () => ({
  connection: {
    readyState: 0,
  },
}));

describe('dbHelpers.ensureMongoForAuth', () => {
  let mockRes;
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv };
    mockRes = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn().mockReturnThis(),
    };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('should return 503 if MONGODB_URI is not set', () => {
    delete process.env.MONGODB_URI;
    const result = ensureMongoForAuth(mockRes);
    
    expect(result).toBe(false);
    expect(mockRes.status).toHaveBeenCalledWith(503);
    expect(mockRes.json).toHaveBeenCalledWith(expect.objectContaining({
      error: 'MongoDB not configured'
    }));
  });

  it('should return 503 if MongoDB is not connected', () => {
    process.env.MONGODB_URI = 'mongodb://localhost:27017/test';
    mongoose.connection.readyState = 0; // Disconnected
    
    const result = ensureMongoForAuth(mockRes);
    
    expect(result).toBe(false);
    expect(mockRes.status).toHaveBeenCalledWith(503);
    expect(mockRes.json).toHaveBeenCalledWith(expect.objectContaining({
      error: 'MongoDB not connected'
    }));
  });

  it('should return true if MongoDB is configured and connected', () => {
    process.env.MONGODB_URI = 'mongodb://localhost:27017/test';
    mongoose.connection.readyState = 1; // Connected
    
    const result = ensureMongoForAuth(mockRes);
    
    expect(result).toBe(true);
    expect(mockRes.status).not.toHaveBeenCalled();
  });
});
