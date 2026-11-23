use thiserror::Error;

/// Structured errors mapped across UniFFI to native Swift Error cases.
#[derive(Debug, Error)]
pub enum StitcherError {
    #[error("Invalid or inaccessible directory: {path}")]
    InvalidDirectory { path: String },

    #[error("I/O error: {message}")]
    IoError { message: String },

    #[error("No valid MP4 clips found in {hour_path}")]
    NoClipsFound { hour_path: String },

    #[error("Container-level MP4 merge failed: {reason}")]
    Mp4MergeFailed { reason: String },

    #[error("AVFoundation audio remux fallback failed: {reason}")]
    FallbackRemuxFailed { reason: String },

    #[error("Stitching job not found: {job_id}")]
    JobNotFound { job_id: String },

    #[error("Job cancelled by user")]
    Cancelled,
}

impl From<std::io::Error> for StitcherError {
    fn from(err: std::io::Error) -> Self {
        StitcherError::IoError {
            message: err.to_string(),
        }
    }
}
