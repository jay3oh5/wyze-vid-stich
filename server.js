import express from 'express';
import cors from 'cors';
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { exec, spawn } from 'child_process';

const app = express();
app.use(cors());
app.use(express.json());

// Request logger middleware for debugging API calls
app.use((req, res, next) => {
  if (req.url.startsWith('/api/')) {
    console.log(`[Server API] ${new Date().toLocaleTimeString()} - ${req.method} ${req.url}`);
  }
  next();
});

const PORT = Number(process.env.PORT) || 3000;
const PROJECT_ROOT = path.resolve('.');
const THUMB_CACHE_DIR = path.resolve('./.tmp/thumbs');

// Global queue state
let stitchingJobs = [];
let activeChildProcess = null;
let isProcessingQueue = false;
const inflightThumbnails = new Map();

function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function logMessageServer(msg) {
  const timestamp = new Date().toLocaleTimeString();
  console.log(`[Stitcher Server] [${timestamp}] ${msg}`);
}

function logToJob(jobId, msg, isError = false) {
  const timestamp = new Date().toLocaleTimeString();
  const formattedMsg = `[${timestamp}] ${isError ? 'ERROR: ' : ''}${msg}`;
  const job = stitchingJobs.find(j => j.id === jobId);
  if (job) {
    job.logs.push(formattedMsg);
    if (isError) {
      job.error = formattedMsg;
    }
  }
  console.log(`[Job ${jobId}] ${formattedMsg}`);
}

function buildOutputFilename(day, hour) {
  const year = day.slice(0, 4);
  const month = day.slice(4, 6);
  const dateStr = day.slice(6, 8);
  const formattedDate = `${year}-${month}-${dateStr}`;

  const h = parseInt(hour, 10);
  const ampm = h >= 12 ? 'PM' : 'AM';
  const displayH = h % 12 === 0 ? 12 : h % 12;
  let hourPart = `${displayH}${ampm}`;
  if (displayH === 12 && ampm === 'AM') {
    hourPart = '!12AM';
  }
  return `${formattedDate}_${hourPart}.mp4`;
}

// Background queue worker
async function processQueue() {
  if (isProcessingQueue) return;
  isProcessingQueue = true;

  logMessageServer('Queue processor started.');
  try {
    while (true) {
      const nextJob = stitchingJobs.find(j => j.status === 'pending');
      if (!nextJob) {
        break;
      }
      await runJob(nextJob);
    }
  } catch (err) {
    console.error('Queue processing error:', err);
  } finally {
    isProcessingQueue = false;
    logMessageServer('Queue processor completed/idle.');
  }
}

// Run a single job
async function runJob(job) {
  job.status = 'running';
  const startTime = Date.now();

  logToJob(job.id, `Starting compile job for ${job.day} Hour ${job.hour}...`);
  logToJob(job.id, `Source: ${job.sourceDir}`);
  logToJob(job.id, `Destination: ${job.useSameFolder ? 'Same folder as source clips' : job.outputDir}`);
  logToJob(job.id, `Overwrite mode: ${job.overwrite ? 'ON' : 'OFF'}`);
  logToJob(job.id, `Delete source clips on success: ${job.deleteAfterCompile ? 'ON' : 'OFF'}`);

  const tempDir = path.resolve('./.tmp');
  ensureDir(tempDir);

  const hourFolderPath = path.join(path.resolve(job.sourceDir), job.day, job.hour);
  if (!fs.existsSync(hourFolderPath)) {
    job.status = 'failed';
    logToJob(job.id, `Directory does not exist: ${hourFolderPath}`, true);
    return;
  }

  let mp4Files;
  if (job.clips && Array.isArray(job.clips) && job.clips.length > 0) {
    mp4Files = [...job.clips].sort();
  } else {
    mp4Files = fs.readdirSync(hourFolderPath).filter(name => name.endsWith('.mp4')).sort();
  }

  if (mp4Files.length === 0) {
    job.status = 'failed';
    logToJob(job.id, `No MP4 files to stitch in ${hourFolderPath}`, true);
    return;
  }

  job.totalClips = mp4Files.length;
  job.currentClipIndex = 0;

  const outputFileName = buildOutputFilename(job.day, job.hour);

  let outputPath;
  if (job.useSameFolder) {
    const dayFolderPath = path.join(path.resolve(job.sourceDir), job.day);
    outputPath = path.join(dayFolderPath, outputFileName);
  } else {
    const resolvedOutputDir = path.resolve(job.outputDir);
    if (!fs.existsSync(resolvedOutputDir)) {
      fs.mkdirSync(resolvedOutputDir, { recursive: true });
      logToJob(job.id, `Created output directory: ${resolvedOutputDir}`);
    }
    outputPath = path.join(resolvedOutputDir, outputFileName);
  }

  job.outputPath = outputPath;

  if (fs.existsSync(outputPath) && !job.overwrite) {
    job.status = 'completed';
    job.currentClipIndex = mp4Files.length;
    logToJob(job.id, `File already exists, skipping: ${outputFileName}`);
    try {
      const outStat = fs.statSync(outputPath);
      job.fileSize = outStat.size;
    } catch (err) {
      logToJob(job.id, `Failed to read file size: ${err.message}`);
    }
    return;
  }

  const listFilename = `list_${job.day}_${job.hour}_${Date.now()}.txt`;
  const listPath = path.join(tempDir, listFilename);

  const listContent = mp4Files.map(file => {
    const absoluteClipPath = path.join(hourFolderPath, file);
    const escapedPath = absoluteClipPath.replace(/'/g, "'\\''");
    return `file '${escapedPath}'`;
  }).join('\n');

  fs.writeFileSync(listPath, listContent, 'utf8');

  try {
    logToJob(job.id, `Stitching ${mp4Files.length} clips for ${job.day} ${job.hour}:00...`);

    await new Promise((resolve, reject) => {
      const args = ['-y', '-f', 'concat', '-safe', '0', '-i', listPath, '-c:v', 'copy', '-c:a', 'aac', outputPath];
      activeChildProcess = spawn('ffmpeg', args);

      activeChildProcess.stderr.on('data', (data) => {
        const lines = data.toString().split('\n');
        for (const line of lines) {
          if (line.trim()) {
            job.logs.push(`[FFmpeg] ${line.trim()}`);
            const openMatch = line.match(/Opening\s+'(.*)'\s+for\s+reading/i);
            if (openMatch) {
              const clipFullPath = openMatch[1];
              const clipName = path.basename(clipFullPath);
              job.currentClipName = clipName;
              job.currentClipIndex = Math.min(job.totalClips, (job.currentClipIndex || 0) + 1);
            }
          }
        }
      });

      activeChildProcess.on('close', (code) => {
        activeChildProcess = null;
        if (code === 0) {
          resolve();
        } else {
          reject(new Error(`FFmpeg process exited with code ${code}`));
        }
      });

      activeChildProcess.on('error', (err) => {
        activeChildProcess = null;
        reject(err);
      });
    });

    if (fs.existsSync(outputPath)) {
      const outStat = fs.statSync(outputPath);
      job.fileSize = outStat.size;
    }

    job.currentClipIndex = job.totalClips;
    job.status = 'completed';
    job.durationMs = Date.now() - startTime;
    logToJob(job.id, `Successfully compiled: ${outputFileName} in ${(job.durationMs / 1000).toFixed(1)}s.`);

    if (job.deleteAfterCompile) {
      logToJob(job.id, `Executing post-compile cleanup: deleting ${mp4Files.length} source clips...`);
      let deletedCount = 0;
      for (const file of mp4Files) {
        const fullClipPath = path.join(hourFolderPath, file);
        if (fs.existsSync(fullClipPath)) {
          fs.unlinkSync(fullClipPath);
          deletedCount++;
        }
      }
      logToJob(job.id, `Cleanup complete. Deleted ${deletedCount} source clips.`);

      try {
        const remainingFiles = fs.readdirSync(hourFolderPath);
        if (remainingFiles.length === 0) {
          fs.rmdirSync(hourFolderPath);
          logToJob(job.id, `Removed empty hour directory: ${job.hour}`);
        }
      } catch (e) {
        logToJob(job.id, `Could not remove empty hour folder: ${e.message}`);
      }
    }
  } catch (err) {
    job.status = 'failed';
    logToJob(job.id, `Failed to stitch: ${err.message}`, true);
  } finally {
    try {
      if (fs.existsSync(listPath)) {
        fs.unlinkSync(listPath);
      }
    } catch (cleanupErr) {
      console.error('Failed to delete temp file:', cleanupErr);
    }
  }
}

// Helper to collect existing compiled MP4 outputs
function listStitchedOutputs(sourceDir, customOutputDir) {
  const seen = new Set();
  const outputs = [];

  const scanFlatDir = (dirPath, origin) => {
    if (!dirPath) return;
    const resolved = path.resolve(dirPath);
    if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) return;
    const entries = fs.readdirSync(resolved);
    for (const name of entries) {
      if (!name.endsWith('.mp4')) continue;
      const fullPath = path.join(resolved, name);
      if (seen.has(fullPath)) continue;
      try {
        const stat = fs.statSync(fullPath);
        if (!stat.isFile()) continue;
        seen.add(fullPath);
        outputs.push({
          name,
          path: fullPath,
          sizeBytes: stat.size,
          mtimeMs: stat.mtimeMs,
          origin
        });
      } catch {
        // skip unreadable file
      }
    }
  };

  // Scan default ./stitched_output and customOutputDir
  scanFlatDir('./stitched_output', 'stitched_output');
  if (customOutputDir) {
    scanFlatDir(customOutputDir, 'custom_output');
  }

  // Also scan compiled MP4s stored inside YYYYMMDD day folders of sourceDir
  if (sourceDir) {
    const resolvedSource = path.resolve(sourceDir);
    if (fs.existsSync(resolvedSource) && fs.statSync(resolvedSource).isDirectory()) {
      const dayDirs = fs.readdirSync(resolvedSource).filter(name => {
        const full = path.join(resolvedSource, name);
        return /^\d{8}$/.test(name) && fs.existsSync(full) && fs.statSync(full).isDirectory();
      });
      for (const day of dayDirs) {
        scanFlatDir(path.join(resolvedSource, day), `day_${day}`);
      }
    }
  }

  outputs.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return outputs;
}

// Cross-platform directory listing for the in-app Folder Browser modal
app.get('/api/fs/list', (req, res) => {
  const requested = typeof req.query.dir === 'string' && req.query.dir.trim()
    ? req.query.dir.trim()
    : PROJECT_ROOT;

  const resolved = path.resolve(requested);
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) {
    return res.status(404).json({ error: `Directory not found: ${requested}` });
  }

  try {
    const rawEntries = fs.readdirSync(resolved, { withFileTypes: true });
    const directories = [];

    for (const entry of rawEntries) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
      if (!entry.isDirectory()) continue;
      const fullPath = path.join(resolved, entry.name);
      let hasDayFolders = false;
      let mp4Count = 0;
      try {
        const children = fs.readdirSync(fullPath);
        hasDayFolders = children.some(c => /^\d{8}$/.test(c));
        mp4Count = children.filter(c => c.endsWith('.mp4')).length;
      } catch {
        // ignore permission errors on child inspection
      }
      directories.push({
        name: entry.name,
        path: fullPath,
        hasDayFolders,
        mp4Count
      });
    }

    directories.sort((a, b) => {
      if (a.hasDayFolders !== b.hasDayFolders) return a.hasDayFolders ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    const parentDir = path.dirname(resolved);
    const shortcuts = [
      { label: 'Sample Recordings', path: path.resolve('./mock_record') },
      { label: 'Stitched Output', path: path.resolve('./stitched_output') },
      { label: 'Workspace Root', path: PROJECT_ROOT }
    ].filter(item => fs.existsSync(item.path));

    res.json({
      currentDir: resolved,
      parentDir: parentDir !== resolved ? parentDir : null,
      directories,
      shortcuts
    });
  } catch (err) {
    res.status(500).json({ error: `Unable to read directory: ${err.message}` });
  }
});

// Endpoint to open macOS folder picker (kept for native macOS compatibility)
app.get('/api/browse', (req, res) => {
  if (process.platform !== 'darwin') {
    return res.json({ path: null, canceled: true, fallbackToModal: true });
  }
  const { prompt } = req.query;
  const safePrompt = String(prompt || 'Select a folder').replace(/["\\]/g, '');
  const cmd = `osascript -e 'POSIX path of (choose folder with prompt "${safePrompt}")'`;

  exec(cmd, (error, stdout, stderr) => {
    if (error) {
      if (stderr.includes('User canceled') || error.message.includes('User canceled')) {
        return res.json({ path: null, canceled: true });
      }
      return res.json({ path: null, canceled: true, fallbackToModal: true });
    }
    res.json({ path: stdout.trim(), canceled: false });
  });
});

// Endpoint to scan a record directory
app.post('/api/scan', (req, res) => {
  const { sourceDir, outputDir } = req.body;
  if (!sourceDir) {
    return res.status(400).json({ error: 'Source directory is required.' });
  }

  const resolvedPath = path.resolve(sourceDir);
  if (!fs.existsSync(resolvedPath)) {
    return res.status(404).json({ error: `Source directory does not exist: ${sourceDir}` });
  }

  const stats = fs.statSync(resolvedPath);
  if (!stats.isDirectory()) {
    return res.status(400).json({ error: `Source path is not a directory: ${sourceDir}` });
  }

  try {
    const days = [];
    const dayDirs = fs.readdirSync(resolvedPath).filter(name => {
      const fullPath = path.join(resolvedPath, name);
      return fs.statSync(fullPath).isDirectory() && /^\d{8}$/.test(name);
    });

    dayDirs.sort();

    for (const day of dayDirs) {
      const dayPath = path.join(resolvedPath, day);
      const hourDirs = fs.readdirSync(dayPath).filter(name => {
        const fullPath = path.join(dayPath, name);
        return fs.statSync(fullPath).isDirectory() && /^\d{2}$/.test(name);
      });

      hourDirs.sort();

      const hours = [];
      for (const hour of hourDirs) {
        const hourPath = path.join(dayPath, hour);
        const mp4Files = fs.readdirSync(hourPath).filter(name => name.endsWith('.mp4'));

        const presentMinutes = new Set();
        const clips = [];
        const clipDetails = {};
        let totalSizeBytes = 0;

        for (const file of mp4Files) {
          const match = file.match(/^(\d{2})\.mp4$/);
          if (match) {
            const minStr = match[1];
            const minNum = parseInt(minStr, 10);
            if (minNum >= 0 && minNum < 60) {
              presentMinutes.add(minStr);
              clips.push(file);
              try {
                const clipStat = fs.statSync(path.join(hourPath, file));
                totalSizeBytes += clipStat.size;
                clipDetails[file] = {
                  sizeBytes: clipStat.size,
                  path: path.join(hourPath, file)
                };
              } catch {
                clipDetails[file] = {
                  sizeBytes: 0,
                  path: path.join(hourPath, file)
                };
              }
            }
          }
        }

        clips.sort();

        const missing = [];
        for (let i = 0; i < 60; i++) {
          const minStr = i.toString().padStart(2, '0');
          if (!presentMinutes.has(minStr)) {
            missing.push(minStr);
          }
        }

        const representativeClip = clips.length > 0
          ? clips[Math.floor(clips.length / 2)]
          : null;
        const previewClipPath = representativeClip
          ? path.join(hourPath, representativeClip)
          : null;

        // Check if an existing stitched file matches this day + hour
        const expectedFilename = buildOutputFilename(day, hour);
        const legacyFilename = `${day}_${hour}.mp4`;
        const candidatePaths = [
          path.join(dayPath, expectedFilename),
          path.join(dayPath, legacyFilename),
          path.resolve('./stitched_output', expectedFilename),
          path.resolve('./stitched_output', legacyFilename)
        ];
        if (outputDir) {
          candidatePaths.push(
            path.resolve(outputDir, expectedFilename),
            path.resolve(outputDir, legacyFilename)
          );
        }
        const existingCompiledPath = candidatePaths.find(p => fs.existsSync(p)) || null;

        hours.push({
          hour,
          clipCount: clips.length,
          clips,
          clipDetails,
          missing,
          totalSizeBytes,
          hourDirPath: hourPath,
          previewClipPath,
          existingCompiledPath
        });
      }

      days.push({
        day,
        formattedDay: `${day.slice(0, 4)}-${day.slice(4, 6)}-${day.slice(6, 8)}`,
        hours
      });
    }

    const stitchedOutputs = listStitchedOutputs(sourceDir, outputDir);

    res.json({
      resolvedSourceDir: resolvedPath,
      days,
      stitchedOutputs
    });
  } catch (error) {
    console.error('Error scanning folder:', error);
    res.status(500).json({ error: `Failed to scan directory: ${error.message}` });
  }
});

// List compiled stitched outputs
app.get('/api/outputs', (req, res) => {
  const sourceDir = typeof req.query.sourceDir === 'string' ? req.query.sourceDir : './mock_record';
  const outputDir = typeof req.query.outputDir === 'string' ? req.query.outputDir : '';
  const outputs = listStitchedOutputs(sourceDir, outputDir);
  res.json({ outputs });
});

// Generate and cache real JPEG thumbnails from MP4 files using FFmpeg
app.get('/api/thumbnail', async (req, res) => {
  const videoPath = req.query.path;
  if (!videoPath || typeof videoPath !== 'string') {
    return res.status(400).send('Path parameter is required.');
  }

  const resolved = path.resolve(videoPath);
  if (!resolved.endsWith('.mp4')) {
    return res.status(403).send('Access denied. Only mp4 thumbnails are permitted.');
  }

  if (!fs.existsSync(resolved)) {
    return res.status(404).send('Video file not found.');
  }

  try {
    ensureDir(THUMB_CACHE_DIR);
    const stat = fs.statSync(resolved);
    const cacheKey = crypto
      .createHash('sha1')
      .update(`${resolved}:${stat.mtimeMs}:${stat.size}`)
      .digest('hex');
    const thumbPath = path.join(THUMB_CACHE_DIR, `${cacheKey}.jpg`);

    if (!fs.existsSync(thumbPath)) {
      let promise = inflightThumbnails.get(cacheKey);
      if (!promise) {
        promise = new Promise((resolvePromise, rejectPromise) => {
          const args = [
            '-y',
            '-ss', '00:00:00.1',
            '-i', resolved,
            '-frames:v', '1',
            '-vf', 'scale=640:360:force_original_aspect_ratio=increase,crop=640:360',
            '-q:v', '3',
            thumbPath
          ];
          const child = spawn('ffmpeg', args);
          child.on('close', (code) => {
            if (code === 0 && fs.existsSync(thumbPath)) {
              resolvePromise(thumbPath);
            } else {
              rejectPromise(new Error(`Thumbnail extraction failed (code ${code})`));
            }
          });
          child.on('error', rejectPromise);
        }).finally(() => {
          inflightThumbnails.delete(cacheKey);
        });
        inflightThumbnails.set(cacheKey, promise);
      }
      await promise;
    }

    res.setHeader('Content-Type', 'image/jpeg');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    fs.createReadStream(thumbPath).pipe(res);
  } catch (err) {
    console.error('Thumbnail error:', err.message);
    res.status(500).send('Unable to generate thumbnail.');
  }
});

// Endpoint to start the stitching process (adds jobs to queue)
app.post('/api/stitch', (req, res) => {
  const { sourceDir, outputDir, hours, overwrite, useSameFolder, deleteAfterCompile } = req.body;

  if (!sourceDir || !hours || !Array.isArray(hours) || hours.length === 0) {
    return res.status(400).json({ error: 'Invalid parameters. sourceDir and non-empty hours array are required.' });
  }

  if (!useSameFolder && !outputDir) {
    return res.status(400).json({ error: 'Output directory is required when custom destination is enabled.' });
  }

  const createdJobs = [];

  for (const item of hours) {
    const { day, hour, clips } = item;
    const jobId = `${day}_${hour}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;

    const newJob = {
      id: jobId,
      day,
      hour,
      clips,
      sourceDir,
      outputDir,
      overwrite,
      useSameFolder,
      deleteAfterCompile: !!deleteAfterCompile,
      status: 'pending',
      totalClips: clips ? clips.length : 0,
      currentClipIndex: 0,
      currentClipName: '',
      outputPath: '',
      logs: ['[System] Job queued.'],
      error: null,
      createdAt: new Date().toLocaleTimeString(),
      durationMs: 0,
      fileSize: 0
    };

    stitchingJobs.push(newJob);
    createdJobs.push(newJob);
  }

  logMessageServer(`Queued ${createdJobs.length} new stitching jobs.`);
  processQueue();

  res.json({ message: 'Stitching jobs queued.', jobs: createdJobs });
});

// Endpoint to query current stitching status and full job history
app.get('/api/status', (req, res) => {
  const activeJob = stitchingJobs.find(j => j.status === 'running');
  const running = !!activeJob || stitchingJobs.some(j => j.status === 'pending');

  const total = stitchingJobs.length;
  const current = stitchingJobs.filter(j => j.status === 'completed' || j.status === 'failed').length;
  const currentItem = activeJob ? `${activeJob.day} ${activeJob.hour}:00` : '';
  const logs = activeJob ? activeJob.logs : (stitchingJobs[stitchingJobs.length - 1]?.logs || []);
  const errors = stitchingJobs.filter(j => j.status === 'failed').map(j => j.error).filter(Boolean);

  res.json({
    running,
    jobs: stitchingJobs,
    total,
    current,
    currentItem,
    logs,
    errors
  });
});

// Endpoint to cancel a pending or running job
app.post('/api/jobs/cancel', (req, res) => {
  const { id } = req.body;
  if (!id) {
    return res.status(400).json({ error: 'Job ID is required.' });
  }

  const job = stitchingJobs.find(j => j.id === id);
  if (!job) {
    return res.status(404).json({ error: 'Job not found.' });
  }

  if (job.status === 'running') {
    logToJob(job.id, 'Cancellation request received. Terminating FFmpeg process...');
    if (activeChildProcess) {
      try {
        activeChildProcess.kill('SIGKILL');
      } catch (err) {
        console.error('Failed to kill FFmpeg process:', err);
      }
      activeChildProcess = null;
    }
    job.status = 'failed';
    job.error = 'Job cancelled by user.';
    logToJob(job.id, 'Job execution aborted.');
  } else if (job.status === 'pending') {
    job.status = 'failed';
    job.error = 'Job cancelled by user in queue.';
    logToJob(job.id, 'Job cancelled before starting.');
  }

  res.json({ message: 'Job status updated.', job });
});

// Endpoint to clear completed/failed job history
app.post('/api/jobs/clear', (req, res) => {
  stitchingJobs = stitchingJobs.filter(j => j.status === 'pending' || j.status === 'running');
  res.json({ message: 'History cleared.', jobs: stitchingJobs });
});

// Endpoint to open folders natively (macOS Finder) or report resolved path
app.post('/api/open-folder', (req, res) => {
  const { path: folderPath } = req.body;
  if (!folderPath) {
    return res.status(400).json({ error: 'Folder path is required.' });
  }

  const resolved = path.resolve(folderPath);
  if (!fs.existsSync(resolved)) {
    return res.status(404).json({ error: `Folder does not exist: ${resolved}` });
  }

  if (process.platform !== 'darwin') {
    return res.json({ success: true, resolvedPath: resolved, message: 'Folder path ready.' });
  }

  exec(`open "${resolved}"`, (error) => {
    if (error) {
      console.error('Failed to open folder:', error);
      return res.status(500).json({ error: `Failed to open folder: ${error.message}` });
    }
    res.json({ success: true, resolvedPath: resolved });
  });
});

// Secure endpoint for HTML5 Range-based Video Streaming
app.get('/api/video-stream', (req, res) => {
  const videoPath = req.query.path;
  if (!videoPath || typeof videoPath !== 'string') {
    return res.status(400).send('Path parameter is required.');
  }

  const resolved = path.resolve(videoPath);

  if (!resolved.endsWith('.mp4')) {
    return res.status(403).send('Access denied. Only mp4 video playback is permitted.');
  }

  if (!fs.existsSync(resolved)) {
    return res.status(404).send('Video file not found.');
  }

  const stat = fs.statSync(resolved);
  const fileSize = stat.size;
  const range = req.headers.range;

  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;

    if (start >= fileSize || end >= fileSize) {
      res.status(416).send(`Requested range not satisfiable\n${start} - ${end} / ${fileSize}`);
      return;
    }

    const chunksize = (end - start) + 1;
    const file = fs.createReadStream(resolved, { start, end });
    const head = {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunksize,
      'Content-Type': 'video/mp4',
    };

    res.writeHead(206, head);
    file.pipe(res);
  } else {
    const head = {
      'Accept-Ranges': 'bytes',
      'Content-Length': fileSize,
      'Content-Type': 'video/mp4',
    };
    res.writeHead(200, head);
    fs.createReadStream(resolved).pipe(res);
  }
});

async function startServer() {
  if (process.env.NODE_ENV !== 'production') {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: {
        middlewareMode: true,
        hmr: false,
        allowedHosts: true
      },
      appType: 'spa'
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.resolve('dist');
    app.use(express.static(distPath));
    app.use((req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`[Stitcher Server] Running on http://0.0.0.0:${PORT}`);
  });
}

startServer().catch((err) => {
  console.error('[Stitcher Server] Failed to start:', err);
  process.exit(1);
});
