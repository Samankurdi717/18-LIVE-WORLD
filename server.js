
const express = require("express");
const cors = require("cors");
const { RtcTokenBuilder, RtcRole } = require("agora-token");
const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { randomUUID } = require("crypto");
const { pipeline } = require("stream/promises");
const { Readable } = require("stream");

const app = express();

app.use(cors({ origin: "*" }));
app.use(express.json({ limit: "1mb" }));

app.get("/", (req, res) => {
  res.send("KURD HALO Server is running");
});

// Agora token
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

// Only allow public files from our Supabase storage buckets
function validStorageUrl(value, bucket) {
  try {
    const url = new URL(value);

    return (
      url.protocol === "https:" &&
      url.hostname === "eofqtrncbswbujzgrvra.supabase.co" &&
      !url.username &&
      !url.password &&
      url.pathname.startsWith(
        `/storage/v1/object/public/${bucket}/`
      )
    );
  } catch {
    return false;
  }
}

async function downloadFile(url, destination, maxBytes) {
  const response = await fetch(url, {
    redirect: "error",
    signal: AbortSignal.timeout(120000)
  });

  if (!response.ok || !response.body) {
    throw new Error("Could not download source file");
  }

  const size = Number(response.headers.get("content-length") || 0);

  if (size > maxBytes) {
    throw new Error("File is too large");
  }

  let received = 0;

  const limiter = new (require("stream").Transform)({
    transform(chunk, encoding, callback) {
      received += chunk.length;

      if (received > maxBytes) {
        callback(new Error("File is too large"));
      } else {
        callback(null, chunk);
      }
    }
  });

  await pipeline(
    Readable.fromWeb(response.body),
    limiter,
    fs.createWriteStream(destination)
  );
}

function runCommand(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args);
    let errorText = "";

    child.stderr.on("data", data => {
      errorText += data.toString();
      if (errorText.length > 12000) {
        errorText = errorText.slice(-12000);
      }
    });

    child.on("error", reject);

    child.on("close", code => {
      if (code === 0) resolve();
      else reject(new Error(errorText || "Media processing failed"));
    });
  });
}

async function hasAudio(file) {
  const result = await new Promise((resolve, reject) => {
    const child = spawn("ffprobe", [
      "-v", "error",
      "-select_streams", "a",
      "-show_entries", "stream=codec_type",
      "-of", "json",
      file
    ]);

    let output = "";
    child.stdout.on("data", data => output += data);
    child.on("error", reject);
    child.on("close", code => {
      if (code !== 0) reject(new Error("Video inspection failed"));
      else resolve(output);
    });
  });

  const data = JSON.parse(result);
  return Array.isArray(data.streams) && data.streams.length > 0;
}

// Mix original video sound with selected library sound
app.post("/mix-audio", async (req, res) => {
  const { videoUrl, soundUrl } = req.body || {};

  if (
    !validStorageUrl(videoUrl, "videos") ||
    !validStorageUrl(soundUrl, "sounds")
  ) {
    return res.status(400).json({
      error: "Invalid video or sound URL"
    });
  }

  const folder = path.join(os.tmpdir(), "kurd-halo-" + randomUUID());

  const videoFile = path.join(folder, "video.bin");
  const soundFile = path.join(folder, "sound.bin");
  const outputFile = path.join(folder, "mixed.mp4");

  try {
    await fs.promises.mkdir(folder, { recursive: true });

    await Promise.all([
      downloadFile(videoUrl, videoFile, 50 * 1024 * 1024),
      downloadFile(soundUrl, soundFile, 20 * 1024 * 1024)
    ]);

    const originalHasAudio = await hasAudio(videoFile);

    let filter;

    if (originalHasAudio) {
      filter =
        "[0:a]volume=1.0[a0];" +
        "[1:a]volume=0.25[a1];" +
        "[a0][a1]amix=inputs=2:duration=longest:dropout_transition=2[a]";
    } else {
      filter = "[1:a]volume=0.25[a]";
    }

    const args = [
      "-y",
      "-i", videoFile,
      "-stream_loop", "-1",
      "-i", soundFile,
      "-filter_complex", filter,
      "-map", "0:v:0",
      "-map", "[a]",
      "-c:v", "copy",
      "-c:a", "aac",
      "-b:a", "192k",
      "-movflags", "+faststart",
      "-shortest",
      outputFile
    ];

    await runCommand("ffmpeg", args);

    res.setHeader("Content-Type", "video/mp4");
    res.setHeader(
      "Content-Disposition",
      'attachment; filename="KURD-HALO.mp4"'
    );

    res.sendFile(outputFile, async error => {
      await fs.promises.rm(folder, {
        recursive: true,
        force: true
      });

      if (error && !res.headersSent) {
        res.status(500).end("Download failed");
      }
    });

  } catch (error) {
    console.error("Mix error:", error.message);

    await fs.promises.rm(folder, {
      recursive: true,
      force: true
    });

    if (!res.headersSent) {
      res.status(500).json({
        error: "Audio mixing failed"
      });
    }
  }
});

const PORT = process.env.PORT || 10000;

app.listen(PORT, () => {
  console.log("KURD HALO Server started on port " + PORT);
});
