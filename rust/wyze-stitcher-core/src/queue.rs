use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use chrono::Local;
use tokio::runtime::Runtime;
use tokio::sync::mpsc;
use uuid::Uuid;

use crate::error::StitcherError;
use crate::merger::{finalize_staged_output, merge_mp4_lossless, temp_staging_path};
use crate::models::{
    AudioRemuxFallback, JobProgressEvent, JobStatus, StitchEventListener, StitchJobRequest,
    StitchJobSnapshot, StitchOptions,
};
use crate::naming::format_output_filename;
use crate::scanner::detect_non_aac_audio;

struct InternalJob {
    snapshot: StitchJobSnapshot,
    options: StitchOptions,
    selected_clips: Option<Vec<String>>,
    cancel_flag: Arc<AtomicBool>,
}

struct QueueState {
    order: Vec<String>,
    jobs: HashMap<String, InternalJob>,
}

impl QueueState {
    fn new() -> Self {
        Self {
            order: Vec::new(),
            jobs: HashMap::new(),
        }
    }

    fn all_snapshots(&self) -> Vec<StitchJobSnapshot> {
        self.order
            .iter()
            .filter_map(|id| self.jobs.get(id).map(|j| j.snapshot.clone()))
            .collect()
    }
}

/// Background sequential stitching queue driven by an internal Tokio runtime.
pub struct JobQueue {
    runtime: Arc<Runtime>,
    state: Arc<Mutex<QueueState>>,
    tx: mpsc::UnboundedSender<String>,
    listener: Arc<dyn StitchEventListener>,
}

impl JobQueue {
    pub fn new(
        runtime: Arc<Runtime>,
        listener: Arc<dyn StitchEventListener>,
        remux_fallback: Arc<dyn AudioRemuxFallback>,
    ) -> Self {
        let state = Arc::new(Mutex::new(QueueState::new()));
        let (tx, rx) = mpsc::unbounded_channel::<String>();

        let worker_state = Arc::clone(&state);
        let worker_listener = Arc::clone(&listener);
        let worker_fallback = Arc::clone(&remux_fallback);

        runtime.spawn(async move {
            run_sequential_worker(rx, worker_state, worker_listener, worker_fallback).await;
        });

        Self {
            runtime,
            state,
            tx,
            listener,
        }
    }

    pub fn runtime(&self) -> &Arc<Runtime> {
        &self.runtime
    }

    pub fn enqueue(
        &self,
        options: StitchOptions,
        requests: Vec<StitchJobRequest>,
    ) -> Result<Vec<StitchJobSnapshot>, StitcherError> {
        if requests.is_empty() {
            return Ok(Vec::new());
        }

        let source_path = Path::new(&options.source_dir);
        if !source_path.exists() || !source_path.is_dir() {
            return Err(StitcherError::InvalidDirectory {
                path: options.source_dir,
            });
        }

        if !options.use_same_folder {
            let custom = options.custom_output_dir.as_deref().unwrap_or("").trim();
            if custom.is_empty() {
                return Err(StitcherError::InvalidDirectory {
                    path: "<missing custom output directory>".to_string(),
                });
            }
        }

        let mut created = Vec::with_capacity(requests.len());

        {
            let mut guard = self.state.lock().expect("queue state poisoned");
            for req in requests {
                let job_id = format!("{}_{}_{}", req.day, req.hour, &Uuid::new_v4().to_string()[..8]);
                let total_clips = req
                    .selected_clips
                    .as_ref()
                    .map(|c| c.len() as u32)
                    .unwrap_or(0);

                let snapshot = StitchJobSnapshot {
                    id: job_id.clone(),
                    day: req.day,
                    hour: req.hour,
                    status: JobStatus::Pending,
                    total_clips,
                    processed_clips: 0,
                    progress: 0.0,
                    current_clip_name: None,
                    output_path: None,
                    file_size_bytes: 0,
                    duration_ms: 0,
                    used_audio_fallback: false,
                    error_message: None,
                    logs: vec![timestamped("Job queued.")],
                };

                let internal = InternalJob {
                    snapshot: snapshot.clone(),
                    options: options.clone(),
                    selected_clips: req.selected_clips,
                    cancel_flag: Arc::new(AtomicBool::new(false)),
                };

                guard.order.push(job_id.clone());
                guard.jobs.insert(job_id.clone(), internal);
                created.push(snapshot);
                let _ = self.tx.send(job_id);
            }
        }

        for snap in &created {
            self.listener.on_job_updated(snap.clone());
        }

        Ok(created)
    }

    pub fn cancel(&self, job_id: &str) -> Result<StitchJobSnapshot, StitcherError> {
        let updated = {
            let mut guard = self.state.lock().expect("queue state poisoned");
            let job = guard
                .jobs
                .get_mut(job_id)
                .ok_or_else(|| StitcherError::JobNotFound {
                    job_id: job_id.to_string(),
                })?;

            job.cancel_flag.store(true, Ordering::SeqCst);

            if job.snapshot.status == JobStatus::Pending {
                job.snapshot.status = JobStatus::Cancelled;
                job.snapshot.error_message = Some("Cancelled before starting.".to_string());
                job.snapshot
                    .logs
                    .push(timestamped("Job cancelled in queue."));
            } else if matches!(
                job.snapshot.status,
                JobStatus::Running | JobStatus::RemuxingFallback
            ) {
                job.snapshot
                    .logs
                    .push(timestamped("Cancellation requested; stopping after current step..."));
            }

            job.snapshot.clone()
        };

        self.listener.on_job_updated(updated.clone());
        Ok(updated)
    }

    pub fn get_all(&self) -> Vec<StitchJobSnapshot> {
        let guard = self.state.lock().expect("queue state poisoned");
        guard.all_snapshots()
    }

    pub fn clear_finished(&self) -> Vec<StitchJobSnapshot> {
        let remaining = {
            let mut guard = self.state.lock().expect("queue state poisoned");
            let mut active_order = Vec::new();
            for id in &guard.order {
                if let Some(j) = guard.jobs.get(id) {
                    if !j.snapshot.status.is_terminal() {
                        active_order.push(id.clone());
                    }
                }
            }
            guard.order = active_order;
            let active_ids: std::collections::HashSet<String> =
                guard.order.iter().cloned().collect();
            guard.jobs.retain(|id, _| active_ids.contains(id));
            guard.all_snapshots()
        };
        remaining
    }
}

async fn run_sequential_worker(
    mut rx: mpsc::UnboundedReceiver<String>,
    state: Arc<Mutex<QueueState>>,
    listener: Arc<dyn StitchEventListener>,
    remux_fallback: Arc<dyn AudioRemuxFallback>,
) {
    while let Some(job_id) = rx.recv().await {
        execute_single_job(&job_id, &state, &listener, &remux_fallback).await;

        let has_more_active = {
            let guard = state.lock().expect("queue state poisoned");
            guard.jobs.values().any(|j| {
                matches!(
                    j.snapshot.status,
                    JobStatus::Pending | JobStatus::Running | JobStatus::RemuxingFallback
                )
            })
        };

        if !has_more_active {
            listener.on_queue_idle();
        }
    }
}

async fn execute_single_job(
    job_id: &str,
    state: &Arc<Mutex<QueueState>>,
    listener: &Arc<dyn StitchEventListener>,
    remux_fallback: &Arc<dyn AudioRemuxFallback>,
) {
    let started = Instant::now();

    let (day, hour, options, selected_clips, cancel_flag) = {
        let mut guard = state.lock().expect("queue state poisoned");
        let Some(job) = guard.jobs.get_mut(job_id) else {
            return;
        };
        if job.cancel_flag.load(Ordering::SeqCst) || job.snapshot.status == JobStatus::Cancelled {
            job.snapshot.status = JobStatus::Cancelled;
            let snap = job.snapshot.clone();
            drop(guard);
            listener.on_job_updated(snap);
            return;
        }
        job.snapshot.status = JobStatus::Running;
        let data = (
            job.snapshot.day.clone(),
            job.snapshot.hour.clone(),
            job.options.clone(),
            job.selected_clips.clone(),
            Arc::clone(&job.cancel_flag),
        );
        let snap = job.snapshot.clone();
        drop(guard);
        listener.on_job_updated(snap);
        data
    };

    push_log(
        state,
        listener,
        job_id,
        format!("Starting compile for {day} Hour {hour}:00"),
        false,
    );

    let hour_folder = PathBuf::from(&options.source_dir).join(&day).join(&hour);
    if !hour_folder.exists() || !hour_folder.is_dir() {
        fail_job(
            state,
            listener,
            job_id,
            format!("Hour directory does not exist: {}", hour_folder.display()),
        );
        return;
    }

    // Resolve ordered list of clip filenames.
    let mut clip_filenames: Vec<String> = match selected_clips {
        Some(custom) if !custom.is_empty() => custom,
        _ => match fs::read_dir(&hour_folder) {
            Ok(entries) => entries
                .flatten()
                .filter_map(|e| e.file_name().into_string().ok())
                .filter(|name| name.ends_with(".mp4"))
                .collect(),
            Err(err) => {
                fail_job(
                    state,
                    listener,
                    job_id,
                    format!("Failed to read hour directory: {err}"),
                );
                return;
            }
        },
    };
    clip_filenames.sort();

    if clip_filenames.is_empty() {
        fail_job(
            state,
            listener,
            job_id,
            format!("No MP4 clips found in {}", hour_folder.display()),
        );
        return;
    }

    let clip_paths: Vec<PathBuf> = clip_filenames
        .iter()
        .map(|name| hour_folder.join(name))
        .collect();

    let output_filename = format_output_filename(&day, &hour, options.naming_format);
    let final_output = if options.use_same_folder {
        PathBuf::from(&options.source_dir)
            .join(&day)
            .join(&output_filename)
    } else {
        let dest_dir = PathBuf::from(options.custom_output_dir.as_deref().unwrap_or(""));
        if !dest_dir.exists() {
            if let Err(err) = fs::create_dir_all(&dest_dir) {
                fail_job(
                    state,
                    listener,
                    job_id,
                    format!("Failed to create output directory: {err}"),
                );
                return;
            }
        }
        dest_dir.join(&output_filename)
    };

    // Update total_clips & resolved output path in snapshot.
    {
        let mut guard = state.lock().expect("queue state poisoned");
        if let Some(job) = guard.jobs.get_mut(job_id) {
            job.snapshot.total_clips = clip_paths.len() as u32;
            job.snapshot.output_path = Some(final_output.to_string_lossy().to_string());
            let snap = job.snapshot.clone();
            drop(guard);
            listener.on_job_updated(snap);
        }
    }

    // Skip cleanly if output exists and overwrite is disabled.
    if final_output.exists() && !options.overwrite {
        let existing_size = fs::metadata(&final_output).map(|m| m.len()).unwrap_or(0);
        push_log(
            state,
            listener,
            job_id,
            format!("Output already exists and overwrite is OFF — skipped: {output_filename}"),
            false,
        );
        complete_job(
            state,
            listener,
            job_id,
            existing_size,
            started.elapsed().as_millis() as u64,
            false,
        );
        return;
    }

    let temp_output = temp_staging_path(&final_output, job_id);
    let total_clips = clip_paths.len() as u32;

    // Pre-check audio FourCC in first clip to detect legacy Wyze μ-law / PCM audio.
    let needs_audio_remux = clip_paths
        .first()
        .map(|p| detect_non_aac_audio(p))
        .unwrap_or(false);

    let mut used_fallback = false;

    if !needs_audio_remux {
        push_log(
            state,
            listener,
            job_id,
            format!("Running lossless mp4-merge on {total_clips} clips..."),
            false,
        );

        let merge_clips = clip_paths.clone();
        let merge_temp = temp_output.clone();
        let merge_cancel = Arc::clone(&cancel_flag);
        let progress_state = Arc::clone(state);
        let progress_listener = Arc::clone(listener);
        let progress_job_id = job_id.to_string();

        let join_res = tokio::task::spawn_blocking(move || {
            merge_mp4_lossless(&merge_clips, &merge_temp, &merge_cancel, |progress, processed, clip_name| {
                {
                    let mut guard = progress_state.lock().expect("queue state poisoned");
                    if let Some(job) = guard.jobs.get_mut(&progress_job_id) {
                        job.snapshot.progress = progress;
                        job.snapshot.processed_clips = processed;
                        job.snapshot.current_clip_name = clip_name.clone();
                    }
                }
                progress_listener.on_job_progress(JobProgressEvent {
                    job_id: progress_job_id.clone(),
                    status: JobStatus::Running,
                    progress,
                    processed_clips: processed,
                    total_clips,
                    current_clip_name: clip_name,
                });
            })
        })
        .await;

        match join_res {
            Ok(Ok(())) => {
                push_log(
                    state,
                    listener,
                    job_id,
                    "Lossless container merge succeeded.".to_string(),
                    false,
                );
            }
            Ok(Err(StitcherError::Cancelled)) => {
                mark_cancelled(state, listener, job_id);
                return;
            }
            Ok(Err(err)) => {
                push_log(
                    state,
                    listener,
                    job_id,
                    format!("mp4-merge reported incompatibility ({err}); switching to AVFoundation AAC remux fallback..."),
                    false,
                );
                used_fallback = true;
            }
            Err(join_err) => {
                fail_job(
                    state,
                    listener,
                    job_id,
                    format!("Worker thread panicked: {join_err}"),
                );
                return;
            }
        }
    } else {
        push_log(
            state,
            listener,
            job_id,
            "Legacy non-AAC Wyze audio track detected (e.g. μ-law PCM); routing directly to AVFoundation AAC remux fallback...".to_string(),
            false,
        );
        used_fallback = true;
    }

    if used_fallback {
        if cancel_flag.load(Ordering::SeqCst) {
            mark_cancelled(state, listener, job_id);
            return;
        }

        // Transition status to RemuxingFallback so SwiftUI displays the AVFoundation badge.
        {
            let mut guard = state.lock().expect("queue state poisoned");
            if let Some(job) = guard.jobs.get_mut(job_id) {
                job.snapshot.status = JobStatus::RemuxingFallback;
                job.snapshot.used_audio_fallback = true;
                job.snapshot.progress = 0.0;
                job.snapshot.current_clip_name = Some("AVFoundation AAC Remux".to_string());
                let snap = job.snapshot.clone();
                drop(guard);
                listener.on_job_updated(snap);
            }
        }

        let input_strs: Vec<String> = clip_paths
            .iter()
            .map(|p| p.to_string_lossy().to_string())
            .collect();
        let temp_str = temp_output.to_string_lossy().to_string();

        match remux_fallback
            .remux_clips_to_aac(job_id.to_string(), input_strs, temp_str)
            .await
        {
            Ok(()) => {
                if cancel_flag.load(Ordering::SeqCst) {
                    let _ = fs::remove_file(&temp_output);
                    mark_cancelled(state, listener, job_id);
                    return;
                }
                push_log(
                    state,
                    listener,
                    job_id,
                    "AVFoundation video-passthrough + AAC audio remux succeeded.".to_string(),
                    false,
                );
            }
            Err(StitcherError::Cancelled) => {
                let _ = fs::remove_file(&temp_output);
                mark_cancelled(state, listener, job_id);
                return;
            }
            Err(err) => {
                let _ = fs::remove_file(&temp_output);
                fail_job(state, listener, job_id, err.to_string());
                return;
            }
        }
    }

    // Atomically move verified staged MP4 to final path before any optional cleanup.
    let final_size = match finalize_staged_output(&temp_output, &final_output) {
        Ok(bytes) => bytes,
        Err(err) => {
            fail_job(state, listener, job_id, err.to_string());
            return;
        }
    };

    let elapsed_ms = started.elapsed().as_millis() as u64;
    push_log(
        state,
        listener,
        job_id,
        format!(
            "Compiled {} ({:.1} MB) in {:.1}s.",
            output_filename,
            final_size as f64 / (1024.0 * 1024.0),
            elapsed_ms as f64 / 1000.0
        ),
        false,
    );

    // Optional destructive post-compile cleanup (runs ONLY after verified atomic output).
    if options.delete_after_compile {
        push_log(
            state,
            listener,
            job_id,
            format!("Post-compile cleanup: deleting {} source clips...", clip_paths.len()),
            false,
        );
        let mut deleted_count = 0usize;
        for clip_path in &clip_paths {
            if fs::remove_file(clip_path).is_ok() {
                deleted_count += 1;
            }
        }
        push_log(
            state,
            listener,
            job_id,
            format!("Cleanup complete: removed {deleted_count} source clips."),
            false,
        );

        if let Ok(mut remaining) = fs::read_dir(&hour_folder) {
            if remaining.next().is_none() && fs::remove_dir(&hour_folder).is_ok() {
                push_log(
                    state,
                    listener,
                    job_id,
                    format!("Removed empty hour directory: {hour}"),
                    false,
                );
            }
        }
    }

    complete_job(state, listener, job_id, final_size, elapsed_ms, used_fallback);
}

fn timestamped(msg: &str) -> String {
    let now = Local::now().format("%H:%M:%S");
    format!("[{now}] {msg}")
}

fn push_log(
    state: &Arc<Mutex<QueueState>>,
    listener: &Arc<dyn StitchEventListener>,
    job_id: &str,
    msg: String,
    is_error: bool,
) {
    let line = if is_error {
        timestamped(&format!("ERROR: {msg}"))
    } else {
        timestamped(&msg)
    };
    {
        let mut guard = state.lock().expect("queue state poisoned");
        if let Some(job) = guard.jobs.get_mut(job_id) {
            job.snapshot.logs.push(line.clone());
        }
    }
    listener.on_job_log(job_id.to_string(), line, is_error);
}

fn complete_job(
    state: &Arc<Mutex<QueueState>>,
    listener: &Arc<dyn StitchEventListener>,
    job_id: &str,
    file_size_bytes: u64,
    duration_ms: u64,
    used_audio_fallback: bool,
) {
    let snap = {
        let mut guard = state.lock().expect("queue state poisoned");
        let Some(job) = guard.jobs.get_mut(job_id) else {
            return;
        };
        job.snapshot.status = JobStatus::Completed;
        job.snapshot.progress = 1.0;
        job.snapshot.processed_clips = job.snapshot.total_clips;
        job.snapshot.current_clip_name = None;
        job.snapshot.file_size_bytes = file_size_bytes;
        job.snapshot.duration_ms = duration_ms;
        job.snapshot.used_audio_fallback = used_audio_fallback;
        job.snapshot.clone()
    };
    listener.on_job_updated(snap);
}

fn fail_job(
    state: &Arc<Mutex<QueueState>>,
    listener: &Arc<dyn StitchEventListener>,
    job_id: &str,
    reason: String,
) {
    let line = timestamped(&format!("ERROR: {reason}"));
    let snap = {
        let mut guard = state.lock().expect("queue state poisoned");
        let Some(job) = guard.jobs.get_mut(job_id) else {
            return;
        };
        job.snapshot.status = JobStatus::Failed;
        job.snapshot.error_message = Some(reason);
        job.snapshot.logs.push(line.clone());
        job.snapshot.clone()
    };
    listener.on_job_log(job_id.to_string(), line, true);
    listener.on_job_updated(snap);
}

fn mark_cancelled(
    state: &Arc<Mutex<QueueState>>,
    listener: &Arc<dyn StitchEventListener>,
    job_id: &str,
) {
    let line = timestamped("Job cancelled by user.");
    let snap = {
        let mut guard = state.lock().expect("queue state poisoned");
        let Some(job) = guard.jobs.get_mut(job_id) else {
            return;
        };
        job.snapshot.status = JobStatus::Cancelled;
        job.snapshot.error_message = Some("Job cancelled by user.".to_string());
        job.snapshot.logs.push(line.clone());
        job.snapshot.clone()
    };
    listener.on_job_log(job_id.to_string(), line, false);
    listener.on_job_updated(snap);
}
