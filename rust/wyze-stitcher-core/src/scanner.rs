use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::Instant;

use rayon::prelude::*;

use crate::error::StitcherError;
use crate::models::{DayRecord, FootageDensity, HourRecord, ScanResult};
use crate::naming::format_day_display;

/// Scans a Wyze SD card `/record` directory in parallel using Rayon.
/// Expects structure: `<source_dir>/YYYYMMDD/HH/MM.mp4` where `MM` is `00..=59`.
pub fn scan_record_directory(source_dir: &str) -> Result<ScanResult, StitcherError> {
    let started = Instant::now();
    let root = PathBuf::from(source_dir);

    if !root.exists() || !root.is_dir() {
        return Err(StitcherError::InvalidDirectory {
            path: source_dir.to_string(),
        });
    }

    let mut day_entries: Vec<(String, PathBuf)> = fs::read_dir(&root)?
        .filter_map(|entry| entry.ok())
        .filter_map(|entry| {
            let path = entry.path();
            if !path.is_dir() {
                return None;
            }
            let name = entry.file_name().into_string().ok()?;
            if is_valid_day_dir(&name) {
                Some((name, path))
            } else {
                None
            }
        })
        .collect();

    day_entries.sort_by(|a, b| a.0.cmp(&b.0));

    // Scan each day directory concurrently across Rayon worker threads.
    let days: Vec<DayRecord> = day_entries
        .into_par_iter()
        .map(|(day, day_path)| scan_day_folder(day, &day_path))
        .collect::<Result<Vec<_>, _>>()?;

    let mut total_hours: u32 = 0;
    let mut total_clips: u32 = 0;
    for d in &days {
        total_hours += d.hours.len() as u32;
        for h in &d.hours {
            total_clips += h.clip_count;
        }
    }

    Ok(ScanResult {
        source_dir: root.to_string_lossy().to_string(),
        total_days: days.len() as u32,
        total_hours,
        total_clips,
        days,
        scan_duration_ms: started.elapsed().as_millis() as u64,
    })
}

fn scan_day_folder(day: String, day_path: &Path) -> Result<DayRecord, StitcherError> {
    let mut hour_entries: Vec<(String, PathBuf)> = fs::read_dir(day_path)?
        .filter_map(|entry| entry.ok())
        .filter_map(|entry| {
            let path = entry.path();
            if !path.is_dir() {
                return None;
            }
            let name = entry.file_name().into_string().ok()?;
            if is_valid_hour_dir(&name) {
                Some((name, path))
            } else {
                None
            }
        })
        .collect();

    hour_entries.sort_by(|a, b| a.0.cmp(&b.0));

    let mut hours: Vec<HourRecord> = hour_entries
        .into_par_iter()
        .map(|(hour, hour_path)| scan_hour_folder(hour, &hour_path))
        .collect::<Result<Vec<_>, _>>()?;

    hours.sort_by(|a, b| a.hour.cmp(&b.hour));

    let formatted_day = format_day_display(&day);
    Ok(DayRecord {
        day,
        formatted_day,
        hours,
    })
}

fn scan_hour_folder(hour: String, hour_path: &Path) -> Result<HourRecord, StitcherError> {
    let mut present_minutes = HashSet::with_capacity(60);
    let mut clips: Vec<String> = Vec::with_capacity(60);

    for entry in fs::read_dir(hour_path)?.flatten() {
        let name = match entry.file_name().into_string() {
            Ok(n) => n,
            Err(_) => continue,
        };
        if let Some(min_str) = parse_minute_clip_name(&name) {
            present_minutes.insert(min_str.to_string());
            clips.push(name);
        }
    }

    clips.sort();

    let mut missing_minutes = Vec::new();
    for m in 0..60u32 {
        let min_str = format!("{m:02}");
        if !present_minutes.contains(&min_str) {
            missing_minutes.push(min_str);
        }
    }

    let has_non_aac_audio = clips
        .first()
        .map(|first_clip| detect_non_aac_audio(&hour_path.join(first_clip)))
        .unwrap_or(false);

    let clip_count = clips.len() as u32;
    let density = FootageDensity::from_clip_count(clip_count);

    Ok(HourRecord {
        hour,
        clip_count,
        clips,
        missing_minutes,
        density,
        has_non_aac_audio,
    })
}

fn is_valid_day_dir(name: &str) -> bool {
    name.len() == 8 && name.bytes().all(|b| b.is_ascii_digit())
}

fn is_valid_hour_dir(name: &str) -> bool {
    if name.len() != 2 || !name.bytes().all(|b| b.is_ascii_digit()) {
        return false;
    }
    name.parse::<u32>().map(|h| h < 24).unwrap_or(false)
}

fn parse_minute_clip_name(name: &str) -> Option<&str> {
    let stem = name.strip_suffix(".mp4")?;
    if stem.len() != 2 || !stem.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let m = stem.parse::<u32>().ok()?;
    if m < 60 {
        Some(stem)
    } else {
        None
    }
}

/// Fast zero-decode MP4 box header sniffer that inspects the `moov` atom for
/// legacy non-AAC audio codecs commonly emitted by older Wyze v2/v3 cameras
/// (`ulaw`, `alaw`, `twos`, `sowt`, `lpcm`, `raw `).
/// Returns `true` if a legacy non-AAC audio sample entry is detected so the
/// queue can seamlessly route the hour through the AVFoundation AAC remux fallback.
pub fn detect_non_aac_audio(mp4_path: &Path) -> bool {
    let Ok(mut file) = File::open(mp4_path) else {
        return false;
    };

    let Ok(file_len) = file.metadata().map(|m| m.len()) else {
        return false;
    };

    // Walk top-level ISO-BMFF boxes to locate `moov` without reading media payloads (`mdat`).
    let mut offset: u64 = 0;
    let mut header = [0u8; 8];

    while offset + 8 <= file_len {
        if file.seek(SeekFrom::Start(offset)).is_err() {
            break;
        }
        if file.read_exact(&mut header).is_err() {
            break;
        }

        let size32 = u32::from_be_bytes([header[0], header[1], header[2], header[3]]) as u64;
        let box_type = &header[4..8];

        let box_size = if size32 == 1 {
            let mut ext = [0u8; 8];
            if file.read_exact(&mut ext).is_err() {
                break;
            }
            u64::from_be_bytes(ext)
        } else if size32 == 0 {
            file_len.saturating_sub(offset)
        } else {
            size32
        };

        if box_size < 8 {
            break;
        }

        if box_type == b"moov" {
            // Cap read at 2 MiB to keep scanning instant even on unusually large metadata boxes.
            let read_len = (box_size as usize).min(2 * 1024 * 1024);
            let mut moov_bytes = vec![0u8; read_len];
            if file.seek(SeekFrom::Start(offset)).is_ok()
                && file.read_exact(&mut moov_bytes).is_ok()
            {
                return contains_non_aac_audio_fourcc(&moov_bytes);
            }
            break;
        }

        offset = offset.saturating_add(box_size);
    }

    false
}

fn contains_non_aac_audio_fourcc(moov_bytes: &[u8]) -> bool {
    const LEGACY_AUDIO_FOURCCS: &[[u8; 4]] = &[
        *b"ulaw", // μ-law PCM (common on Wyze Cam v2 / v3)
        *b"alaw", // A-law PCM
        *b"twos", // Uncompressed big-endian PCM
        *b"sowt", // Uncompressed little-endian PCM
        *b"lpcm", // Linear PCM
    ];

    // Look for `stsd` sample description boxes followed by a legacy audio FourCC.
    let mut i = 0;
    while i + 24 <= moov_bytes.len() {
        if &moov_bytes[i..i + 4] == b"stsd" {
            // stsd layout: [4 bytes "stsd"][4 bytes version+flags][4 bytes entry_count]
            //              [4 bytes entry_size][4 bytes format_fourcc]
            let fourcc = &moov_bytes[i + 16..i + 20];
            if LEGACY_AUDIO_FOURCCS.iter().any(|c| c == fourcc) {
                return true;
            }
        }
        i += 1;
    }

    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn scans_mock_wyze_hierarchy_and_detects_missing_gaps() {
        let dir = tempdir().unwrap();
        let hour_dir = dir.path().join("20260529").join("00");
        fs::create_dir_all(&hour_dir).unwrap();

        for m in [0, 1, 2, 5] {
            fs::write(hour_dir.join(format!("{m:02}.mp4")), b"stub").unwrap();
        }
        // Non-minute file should be ignored
        fs::write(hour_dir.join("notes.txt"), b"ignore").unwrap();

        let result = scan_record_directory(dir.path().to_str().unwrap()).unwrap();
        assert_eq!(result.total_days, 1);
        assert_eq!(result.total_hours, 1);
        assert_eq!(result.total_clips, 4);
        assert_eq!(result.days[0].formatted_day, "2026-05-29");
        assert_eq!(result.days[0].hours[0].density, FootageDensity::SevereGaps);
        assert_eq!(result.days[0].hours[0].missing_minutes.len(), 56);
        assert!(result.days[0].hours[0].missing_minutes.contains(&"03".to_string()));
    }
}
