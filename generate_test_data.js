import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

const TARGET_DIR = path.resolve('./mock_record');
const TEMP_CLIP = path.join(TARGET_DIR, 'temp_base.mp4');

console.log('--- Generating Mock Wyze Record Folder ---');

try {
  // Ensure target folder exists
  if (fs.existsSync(TARGET_DIR)) {
    fs.rmSync(TARGET_DIR, { recursive: true, force: true });
  }
  fs.mkdirSync(TARGET_DIR, { recursive: true });

  // Generate a tiny 1-second base MP4 file using FFmpeg
  console.log('Generating base 1-second video file using FFmpeg...');
  const ffmpegCmd = `ffmpeg -y -f lavfi -i testsrc=duration=1:size=320x240:rate=15 -f lavfi -i sine=frequency=1000:duration=1 -c:v libx264 -c:a aac -pix_fmt yuv420p "${TEMP_CLIP}"`;
  execSync(ffmpegCmd, { stdio: 'ignore' });
  
  if (!fs.existsSync(TEMP_CLIP)) {
    throw new Error('Failed to generate base video clip.');
  }

  // Create structure
  const day = '20260529';
  console.log(`Creating mock folder structure for day: ${day}`);

  // Hour 00: Has missing clips (04, 15, 32)
  const hr00Path = path.join(TARGET_DIR, day, '00');
  fs.mkdirSync(hr00Path, { recursive: true });
  const missing00 = new Set(['04', '15', '32']);
  for (let m = 0; m < 60; m++) {
    const minStr = m.toString().padStart(2, '0');
    if (!missing00.has(minStr)) {
      fs.copyFileSync(TEMP_CLIP, path.join(hr00Path, `${minStr}.mp4`));
    }
  }
  console.log('Created hour 00 (57/60 files, missing 04, 15, 32)');

  // Hour 01: Fully complete (60/60 files)
  const hr01Path = path.join(TARGET_DIR, day, '01');
  fs.mkdirSync(hr01Path, { recursive: true });
  for (let m = 0; m < 60; m++) {
    const minStr = m.toString().padStart(2, '0');
    fs.copyFileSync(TEMP_CLIP, path.join(hr01Path, `${minStr}.mp4`));
  }
  console.log('Created hour 01 (60/60 files, complete)');

  // Hour 02: Partially complete (only first 10 minutes)
  const hr02Path = path.join(TARGET_DIR, day, '02');
  fs.mkdirSync(hr02Path, { recursive: true });
  for (let m = 0; m < 10; m++) {
    const minStr = m.toString().padStart(2, '0');
    fs.copyFileSync(TEMP_CLIP, path.join(hr02Path, `${minStr}.mp4`));
  }
  console.log('Created hour 02 (10/60 files, partial)');

  // Clean up temp base file
  fs.unlinkSync(TEMP_CLIP);
  console.log(`\nSuccess! Mock folder created at: ${TARGET_DIR}`);

} catch (err) {
  console.error('Error generating mock data:', err);
}
