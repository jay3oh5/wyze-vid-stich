use std::cell::{Cell, RefCell};
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::error::StitcherError;

/// Creates an atomic sibling staging path (e.g. `.stitch_<job_id>.tmp.mp4`)
/// so partial or cancelled renders never pollute the target output filename.
pub fn temp_staging_path(final_output: &Path, job_id: &str) -> PathBuf {
    let parent = final_output.parent().unwrap_or_else(|| Path::new("."));
    parent.join(format!(".stitch_{job_id}.tmp.mp4"))
}

/// Strictly validates every input clip before stitching (fail-fast policy).
/// Detects missing files, 0-byte clips, and truncated/invalid MP4 container headers,
/// returning an actionable error identifying the exact clip filename.
pub fn validate_clips_strict(input_clips: &[PathBuf]) -> Result<(), StitcherError> {
    const VALID_TOP_BOXES: &[[u8; 4]] = &[
        *b"ftyp",
        *b"moov",
        *b"mdat",
        *b"free",
        *b"skip",
        *b"wide",
        *b"uuid",
        *b"pdin",
    ];

    for path in input_clips {
        let display_label = format_clip_label(path);
        let meta = fs::metadata(path).map_err(|err| StitcherError::Mp4MergeFailed {
            reason: format!("Unreadable clip '{display_label}': {err}"),
        })?;

        if meta.len() == 0 {
            return Err(StitcherError::Mp4MergeFailed {
                reason: format!(
                    "Corrupt or empty clip detected: {display_label} (0 bytes). Inspect and exclude this minute to continue."
                ),
            });
        }

        if meta.len() < 8 {
            return Err(StitcherError::Mp4MergeFailed {
                reason: format!(
                    "Truncated MP4 clip detected: {display_label} ({} bytes). Inspect and exclude this minute to continue.",
                    meta.len()
                ),
            });
        }

        let mut file = File::open(path).map_err(|err| StitcherError::Mp4MergeFailed {
            reason: format!("Could not open clip '{display_label}': {err}"),
        })?;
        let mut header = [0u8; 8];
        file.read_exact(&mut header)
            .map_err(|err| StitcherError::Mp4MergeFailed {
                reason: format!("Corrupt MP4 header in '{display_label}': {err}"),
            })?;

        let box_size = u32::from_be_bytes([header[0], header[1], header[2], header[3]]);
        let box_type = &header[4..8];
        let valid_size = box_size == 0 || box_size == 1 || box_size >= 8;
        let valid_type = VALID_TOP_BOXES.iter().any(|t| t == box_type);

        if !valid_size || !valid_type {
            return Err(StitcherError::Mp4MergeFailed {
                reason: format!(
                    "Invalid MP4 container header in '{display_label}'. Inspect and exclude this minute to continue."
                ),
            });
        }
    }

    Ok(())
}

fn format_clip_label(path: &Path) -> String {
    let filename = path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| path.to_string_lossy().to_string());
    if let Some(parent_name) = path.parent().and_then(|p| p.file_name()) {
        format!("{}/{}", parent_name.to_string_lossy(), filename)
    } else {
        filename
    }
}

/// Runs container-level lossless MP4 concatenation using `mp4_merge::join_files`.
/// Reports normalized progress `0.0..=1.0` via `on_progress`, throttled to avoid
/// flooding the UniFFI callback boundary.
pub fn merge_mp4_lossless<F>(
    input_clips: &[PathBuf],
    temp_output: &Path,
    cancel_flag: &Arc<AtomicBool>,
    on_progress: F,
) -> Result<(), StitcherError>
where
    F: FnMut(f32, u32, Option<String>),
{
    if input_clips.is_empty() {
        return Err(StitcherError::Mp4MergeFailed {
            reason: "No input clips provided".to_string(),
        });
    }

    if cancel_flag.load(Ordering::SeqCst) {
        return Err(StitcherError::Cancelled);
    }

    if let Some(parent) = temp_output.parent() {
        if !parent.exists() {
            fs::create_dir_all(parent)?;
        }
    }

    let total_clips = input_clips.len() as u32;
    let clip_names: Vec<String> = input_clips
        .iter()
        .map(|p| format_clip_label(p))
        .collect();

    let last_emitted_progress = Cell::new(-1.0f32);
    let last_emitted_at = Cell::new(Instant::now() - Duration::from_secs(1));
    let on_progress = RefCell::new(on_progress);

    let temp_output_buf = temp_output.to_path_buf();
    let merge_result = mp4_merge::join_files(input_clips, &temp_output_buf, |raw_progress: f64| {
        let raw_progress = raw_progress as f32;
        let clamped = raw_progress.clamp(0.0, 1.0);
        let now = Instant::now();
        let prev_progress = last_emitted_progress.get();
        let prev_at = last_emitted_at.get();
        let should_emit = (clamped - prev_progress).abs() >= 0.015
            || now.duration_since(prev_at) >= Duration::from_millis(80)
            || clamped >= 1.0;

        if should_emit {
            last_emitted_progress.set(clamped);
            last_emitted_at.set(now);

            let idx = ((clamped * total_clips as f32).floor() as usize)
                .min(clip_names.len().saturating_sub(1));
            let processed = ((clamped * total_clips as f32).round() as u32).min(total_clips);
            (on_progress.borrow_mut())(clamped, processed, clip_names.get(idx).cloned());
        }
    });

    if cancel_flag.load(Ordering::SeqCst) {
        let _ = fs::remove_file(temp_output);
        return Err(StitcherError::Cancelled);
    }

    match merge_result {
        Ok(()) => Ok(()),
        Err(err) => {
            let _ = fs::remove_file(temp_output);
            Err(StitcherError::Mp4MergeFailed {
                reason: err.to_string(),
            })
        }
    }
}

/// Verifies that the staging MP4 exists and is non-empty, then atomically renames
/// it into the final destination path and returns its byte size.
pub fn finalize_staged_output(temp_output: &Path, final_output: &Path) -> Result<u64, StitcherError> {
    let metadata = fs::metadata(temp_output).map_err(|err| StitcherError::IoError {
        message: format!("Staged output missing after compile: {err}"),
    })?;

    if metadata.len() == 0 {
        let _ = fs::remove_file(temp_output);
        return Err(StitcherError::Mp4MergeFailed {
            reason: "Compiled output file was empty (0 bytes)".to_string(),
        });
    }

    if final_output.exists() {
        fs::remove_file(final_output)?;
    }

    fs::rename(temp_output, final_output)?;
    Ok(metadata.len())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn strict_validation_fails_fast_on_zero_byte_clip() {
        let dir = tempdir().unwrap();
        let bad_clip = dir.path().join("14.mp4");
        fs::write(&bad_clip, b"").unwrap();

        let err = validate_clips_strict(&[bad_clip]).unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("14.mp4"));
        assert!(msg.contains("0 bytes"));
    }

    #[test]
    fn strict_validation_fails_fast_on_invalid_header() {
        let dir = tempdir().unwrap();
        let bad_clip = dir.path().join("22.mp4");
        fs::write(&bad_clip, b"NOT_AN_MP4_FILE_HEADER").unwrap();

        let err = validate_clips_strict(&[bad_clip]).unwrap_err();
        assert!(err.to_string().contains("22.mp4"));
    }

    #[test]
    fn strict_validation_accepts_valid_ftyp_box() {
        let dir = tempdir().unwrap();
        let good_clip = dir.path().join("00.mp4");
        // Valid 16-byte ISO-BMFF ftyp header
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&16u32.to_be_bytes());
        bytes.extend_from_slice(b"ftyp");
        bytes.extend_from_slice(b"isom\0\0\0\0");
        fs::write(&good_clip, &bytes).unwrap();

        assert!(validate_clips_strict(&[good_clip]).is_ok());
    }
}
