use std::fs;
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

/// Runs container-level lossless MP4 concatenation using `mp4_merge::join_files`.
/// Reports normalized progress `0.0..=1.0` via `on_progress`, throttled to avoid
/// flooding the UniFFI callback boundary.
pub fn merge_mp4_lossless<F>(
    input_clips: &[PathBuf],
    temp_output: &Path,
    cancel_flag: &Arc<AtomicBool>,
    mut on_progress: F,
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
        .map(|p| {
            p.file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "clip.mp4".to_string())
        })
        .collect();

    let mut last_emitted_progress: f32 = -1.0;
    let mut last_emitted_at = Instant::now() - Duration::from_secs(1);

    let merge_result = mp4_merge::join_files(input_clips, temp_output, |raw_progress: f32| {
        let clamped = raw_progress.clamp(0.0, 1.0);
        let now = Instant::now();
        let should_emit = (clamped - last_emitted_progress).abs() >= 0.015
            || now.duration_since(last_emitted_at) >= Duration::from_millis(80)
            || clamped >= 1.0;

        if should_emit {
            last_emitted_progress = clamped;
            last_emitted_at = now;

            let idx = ((clamped * total_clips as f32).floor() as usize)
                .min(clip_names.len().saturating_sub(1));
            let processed = ((clamped * total_clips as f32).round() as u32).min(total_clips);
            on_progress(clamped, processed, clip_names.get(idx).cloned());
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
