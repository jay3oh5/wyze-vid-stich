mod error;
mod merger;
mod models;
mod naming;
mod queue;
mod scanner;

use std::sync::Arc;

use tokio::runtime::Builder;

pub use crate::error::StitcherError;
pub use crate::models::{
    AudioRemuxFallback, DayRecord, FootageDensity, HourRecord, JobProgressEvent, JobStatus,
    OutputNamingFormat, ScanResult, StitchEventListener, StitchJobRequest, StitchJobSnapshot,
    StitchOptions,
};
use crate::queue::JobQueue;

uniffi::include_scaffolding!("wyze_stitcher");

/// Returns the crate version string for diagnostics and About info.
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Formats a preview output filename for Settings UI.
pub fn preview_output_filename(day: String, hour: String, format: OutputNamingFormat) -> String {
    naming::format_output_filename(&day, &hour, format)
}

/// Primary UniFFI-exported engine coordinating parallel scanning and sequential stitching.
pub struct StitcherEngine {
    queue: JobQueue,
}

impl StitcherEngine {
    pub fn new(
        listener: Arc<dyn StitchEventListener>,
        remux_fallback: Arc<dyn AudioRemuxFallback>,
    ) -> Self {
        let runtime = Arc::new(
            Builder::new_multi_thread()
                .enable_all()
                .thread_name("wyze-stitcher-worker")
                .build()
                .expect("Failed to initialize Tokio runtime"),
        );

        let queue = JobQueue::new(runtime, listener, remux_fallback);
        Self { queue }
    }

    /// Runs the multi-threaded Rayon directory scanner off the Swift MainActor.
    pub async fn scan_directory(&self, source_dir: String) -> Result<ScanResult, StitcherError> {
        let handle = self
            .queue
            .runtime()
            .spawn_blocking(move || scanner::scan_record_directory(&source_dir));

        handle.await.map_err(|err| StitcherError::IoError {
            message: format!("Scanner task failed: {err}"),
        })?
    }

    /// Validates options and appends one or more hourly jobs to the sequential queue.
    pub fn enqueue_jobs(
        &self,
        options: StitchOptions,
        requests: Vec<StitchJobRequest>,
    ) -> Result<Vec<StitchJobSnapshot>, StitcherError> {
        self.queue.enqueue(options, requests)
    }

    /// Cancels a pending job immediately or signals abort on the active job.
    pub fn cancel_job(&self, job_id: String) -> Result<StitchJobSnapshot, StitcherError> {
        self.queue.cancel(&job_id)
    }

    /// Returns all queued, active, and historical jobs in insertion order.
    pub fn get_jobs(&self) -> Vec<StitchJobSnapshot> {
        self.queue.get_all()
    }

    /// Clears Completed, Failed, and Cancelled jobs while preserving Pending/Running jobs.
    pub fn clear_finished_jobs(&self) -> Vec<StitchJobSnapshot> {
        self.queue.clear_finished()
    }
}
