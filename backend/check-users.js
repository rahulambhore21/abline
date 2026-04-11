require('dotenv').config();
const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
  username: String,
  role: String,
  createdAt: Date,
}, { collection: 'users' });

const UserModel = mongoose.model('User', UserSchema);

async function checkUsers() {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
    const users = await UserModel.find().select('-password');
    console.log('Database users:');
    users.forEach(u => {
      console.log(`  - ${u.username} (${u.role})`);
    });
    process.exit(0);
  } catch (e) {
    console.error('Error:', e.message);
    process.exit(1);
  }
}

checkUsers();
