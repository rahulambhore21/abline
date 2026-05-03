/**
 * Seed script to initialize admin user credentials
 * Run with: node backend/seed.js
 */

require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const MONGODB_URI =
  'mongodb+srv://Vercel-Admin-abline:mH0AtaeqnjGVIg7c@abline.rzfhc4g.mongodb.net/?retryWrites=true&w=majority';

// Define User Schema
const UserSchema = new mongoose.Schema(
  {
    username: {
      type: String,
      required: [true, 'Username is required'],
      unique: true,
      trim: true,
      minlength: [3, 'Username must be at least 3 characters'],
    },
    password: {
      type: String,
      required: [true, 'Password is required'],
      minlength: [6, 'Password must be at least 6 characters'],
      select: false,
    },
    role: {
      type: String,
      enum: ['host', 'user'],
      default: 'user',
      required: true,
    },
  },
  { timestamps: true }
);

// Hash password before saving
UserSchema.pre('save', async function (next) {
  if (!this.isModified('password')) {
    return next();
  }
  try {
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    next();
  } catch (error) {
    next(error);
  }
});

const UserModel = mongoose.model('User', UserSchema);

async function seedAdmin() {
  try {
    if (!MONGODB_URI) {
      console.error('❌ MONGODB_URI not configured in .env');
      process.exit(1);
    }

    console.log('📚 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI, {
      serverSelectionTimeoutMS: 5000,
    });

    console.log('✅ Connected to MongoDB');

    // Delete existing host user
    const existingHost = await UserModel.findOne({ role: 'host' });
    if (existingHost) {
      await UserModel.deleteOne({ role: 'host' });
      console.log(`🗑️  Removed existing host user: ${existingHost.username}`);
    }

    // Create new admin user
    const adminUser = new UserModel({
      username: 'admin',
      password: 'admin123',
      role: 'host',
    });

    await adminUser.save();

    console.log('✅ Admin user created successfully!');
    console.log('\n📋 Admin Credentials:');
    console.log('   Username: admin');
    console.log('   Password: admin123');
    console.log('   Role: host\n');

    process.exit(0);
  } catch (error) {
    console.error('❌ Error seeding admin:', error.message);
    process.exit(1);
  }
}

seedAdmin();
