const mongoose = require('mongoose');

// Fail fast on disconnected queries instead of buffering for 10 seconds
mongoose.set('bufferTimeoutMS', 2500);

const connectDB = async () => {
  const uri = process.env.MONGODB_URI;
  if (!uri) {
    console.warn('WARNING: MONGODB_URI environment variable is not set! Running server in stateless / in-memory mode.');
    return;
  }
  console.log('Attempting MongoDB connection...');
  try {
    const conn = await mongoose.connect(uri, {
      serverSelectionTimeoutMS: 5000,
    });
    console.log(`MongoDB Connected: ${conn.connection.host}`);
  } catch (error) {
    console.error(`MongoDB connection error: ${error.message}. Continuing without database.`);
  }
};

module.exports = connectDB;
