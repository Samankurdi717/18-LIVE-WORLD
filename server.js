const express = require("express");
const cors = require("cors");
const { RtcTokenBuilder, RtcRole } = require("agora-token");

const app = express();

app.use(cors({
  origin: "https://samankurdi717.github.io"
}));

app.get("/", (req, res) => {
  res.send("18 LIVE WORLD Server is running");
});

app.get("/token", (req, res) => {
  const appId = process.env.AGORA_APP_ID;
  const certificate = process.env.AGORA_APP_CERTIFICATE;

  const channel = String(req.query.channel || "").trim();
  const uid = Number(req.query.uid);

  if (!appId || !certificate) {
    return res.status(500).json({ error: "Server settings missing" });
  }

  if (!channel || channel.length > 64 ||
      !Number.isInteger(uid) || uid < 1) {
    return res.status(400).json({ error: "Invalid channel or uid" });
  }

  try {
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId,
      certificate,
      channel,
      uid,
      RtcRole.PUBLISHER,
      3600,
      3600
    );

    res.json({ token, appId });
  } catch (error) {
    res.status(500).json({ error: "Token generation failed" });
  }
});

const PORT = process.env.PORT || 10000;
app.listen(PORT, () => {
  console.log("Server started");
});
