const { generateRtcToken } = require('../config/agora');

exports.getToken = (req, res) => {
  const { channelName, uid } = req.query;

  if (!channelName || !uid) {
    return res.status(400).json({ error: 'Missing required query parameters: channelName, uid' });
  }

  try {
    const token = generateRtcToken(channelName, uid);
    res.json({ token });
  } catch (error) {
    res.status(500).json({ error: 'Failed to generate token', message: error.message });
  }
};
