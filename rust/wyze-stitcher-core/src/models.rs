use crate::error::StitcherError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputNamingFormat {
    TwentyFourHour,
    TwelveHourLegacy,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StitchMode {
    SingleHour,
    FullDay,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FootageDensity {
    Empty,
    SevereGaps,
    MinorGaps,
    Complete,
}

impl FootageDensity {
    pub fn from_clip_count(count: u32) -> Self {
        match count {
            0 => FootageDensity::Empty,
            1..=29 => FootageDensity::SevereGaps,
            30..=59 => FootageDensity::MinorGaps,
            _ => FootageDensity::Complete,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JobStatus {
    Pending,
    Running,
    RemuxingFallback,
    Completed,
    Failed,
    Cancelled,
}

impl JobStatus {
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            JobStatus::Completed | JobStatus::Failed | JobStatus::Cancelled
        )
    }
}

#[derive(Debug, Clone)]
pub struct HourRecord {
    pub hour: String,
    pub source_dir_path: String,
    pub clip_count: u32,
    pub total_size_bytes: u64,
    pub clips: Vec<String>,
    pub missing_minutes: Vec<String>,
    pub density: FootageDensity,
    pub has_non_aac_audio: bool,
}

#[derive(Debug, Clone)]
pub struct DayRecord {
    pub day: String,
    pub formatted_day: String,
    pub hours: Vec<HourRecord>,
}

#[derive(Debug, Clone)]
pub struct ScanResult {
    pub source_dir: String,
    pub days: Vec<DayRecord>,
    pub total_days: u32,
    pub total_hours: u32,
    pub total_clips: u32,
    pub scan_duration_ms: u64,
}

#[derive(Debug, Clone)]
pub struct StitchOptions {
    pub source_dir: String,
    pub custom_output_dir: Option<String>,
    pub use_same_folder: bool,
    pub overwrite: bool,
    pub delete_after_compile: bool,
    pub naming_format: OutputNamingFormat,
}

#[derive(Debug, Clone)]
pub struct StitchJobRequest {
    pub day: String,
    pub hour: String,
    pub mode: StitchMode,
    pub hour_dir_paths: Vec<String>,
    pub selected_clips: Option<Vec<String>>,
}

#[derive(Debug, Clone)]
pub struct StitchJobSnapshot {
    pub id: String,
    pub day: String,
    pub hour: String,
    pub mode: StitchMode,
    pub status: JobStatus,
    pub total_clips: u32,
    pub processed_clips: u32,
    pub progress: f32,
    pub current_clip_name: Option<String>,
    pub output_path: Option<String>,
    pub file_size_bytes: u64,
    pub duration_ms: u64,
    pub used_audio_fallback: bool,
    pub deleted_sources: bool,
    pub error_message: Option<String>,
    pub logs: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct JobProgressEvent {
    pub job_id: String,
    pub status: JobStatus,
    pub progress: f32,
    pub processed_clips: u32,
    pub total_clips: u32,
    pub current_clip_name: Option<String>,
}

/// Foreign push-event observer implemented in Swift (`StitcherStore`).
pub trait StitchEventListener: Send + Sync {
    fn on_job_updated(&self, snapshot: StitchJobSnapshot);
    fn on_job_progress(&self, event: JobProgressEvent);
    fn on_job_log(&self, job_id: String, line: String, is_error: bool);
    fn on_queue_idle(&self);
}

/// Foreign async fallback remuxer implemented in Swift using AVFoundation.
#[async_trait::async_trait]
pub trait AudioRemuxFallback: Send + Sync {
    async fn remux_clips_to_aac(
        &self,
        job_id: String,
        input_clip_paths: Vec<String>,
        temp_output_path: String,
    ) -> Result<(), StitcherError>;

    /// Synchronously aborts any active AVFoundation reader/writer session for `job_id`.
    fn cancel_remux(&self, job_id: String);
}
