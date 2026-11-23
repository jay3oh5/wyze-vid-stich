use std::collections::HashSet;
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::Instant;

use rayon::prelude::*;

use crate::error::StitcherError;
use crate::models::{DayRecord, FootageDensity, HourRecord, ScanResult};
use crate::naming::format_day_display;

/// Scans a Wyze SD card directory in parallel using Rayon.
/// Adaptively supports:
/// - Single hour folder (e.g. `.../11` containing `00.mp4`..`59.mp4`)
/// - Single day folder (e.g. `.../20241020` containing `HH/MM.mp4`)
/// - SD card root containing a `record` folder
/// - Standard Wyze directory: `<source_dir>/YYYYMMDD/HH/MM.mp4`
/// - Parent folder containing hour subfolders
pub fn scan_record_directory(source_dir: &str) -> Result<ScanResult, StitcherError> {
    let started = Instant::now();
    let root = PathBuf::from(source_dir);

    if !root.exists() || !root.is_dir() {
        return Err(StitcherError::InvalidDirectory {
            path: source_dir.to_string(),
        });
    }

    let days = discover_and_scan_hierarchy(&root)?;

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

fn discover_and_scan_hierarchy(root: &Path) -> Result<Vec<DayRecord>, StitcherError> {
    // Case 1: The user selected an hour directory directly (e.g. ".../11" with "00.mp4"..."59.mp4")
    if has_minute_clips(root) {
        let hour = extract_hour_from_name(root.file_name().and_then(|n| n.to_str()).unwrap_or(""))
            .unwrap_or_else(|| "00".to_string());
        let day = get_day_for_folder(root);
        let hour_record = scan_hour_folder(hour, root)?;
        let formatted_day = format_day_display(&day);
        return Ok(vec![DayRecord {
            day,
            formatted_day,
            hours: vec![hour_record],
        }]);
    }

    // Case 2: SD card root containing a "record" folder
    let record_sub = root.join("record");
    if record_sub.is_dir() && !has_minute_clips(root) {
        let sub_days = discover_and_scan_hierarchy(&record_sub)?;
        if !sub_days.is_empty() {
            return Ok(sub_days);
        }
    }

    // Case 3: The directory contains hour subfolders directly (e.g. ".../20241020" or user folder with "11", "12", etc.)
    let mut hour_entries = Vec::new();
    if let Ok(entries) = fs::read_dir(root) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                    if let Some(hour) = extract_hour_from_name(name) {
                        if has_minute_clips(&p) {
                            hour_entries.push((hour, p));
                        }
                    }
                }
            }
        }
    }
    if !hour_entries.is_empty() {
        hour_entries.sort_by(|a, b| a.0.cmp(&b.0));
        let day = get_day_for_folder(root);
        let hours: Vec<HourRecord> = hour_entries
            .into_par_iter()
            .map(|(hour, hour_path)| scan_hour_folder(hour, &hour_path))
            .collect::<Result<Vec<_>, _>>()?;
        let formatted_day = format_day_display(&day);
        return Ok(vec![DayRecord {
            day,
            formatted_day,
            hours,
        }]);
    }

    // Case 4: Standard Wyze folder containing YYYYMMDD subfolders
    let mut day_entries: Vec<(String, PathBuf)> = fs::read_dir(root)?
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

    if !day_entries.is_empty() {
        day_entries.sort_by(|a, b| a.0.cmp(&b.0));
        let days: Vec<DayRecord> = day_entries
            .into_par_iter()
            .map(|(day, day_path)| scan_day_folder(day, &day_path))
            .collect::<Result<Vec<_>, _>>()?;
        let valid_days: Vec<DayRecord> = days.into_iter().filter(|d| !d.hours.is_empty()).collect();
        if !valid_days.is_empty() {
            return Ok(valid_days);
        }
    }

    // Case 5: Shallow inspection of immediate subdirectories
    if let Ok(entries) = fs::read_dir(root) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
                if !name.starts_with('.') && !name.starts_with('$') {
                    if let Ok(sub_days) = discover_and_scan_hierarchy(&p) {
                        if !sub_days.is_empty() {
                            return Ok(sub_days);
                        }
                    }
                }
            }
        }
    }

    Ok(vec![])
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
            if let Some(hour) = extract_hour_from_name(&name) {
                Some((hour, path))
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

pub fn has_minute_clips(dir: &Path) -> bool {
    if let Ok(entries) = fs::read_dir(dir) {
        entries.flatten().any(|e| {
            e.file_name()
                .to_str()
                .and_then(|s| parse_minute_clip_name(s))
                .is_some()
        })
    } else {
        false
    }
}

pub fn extract_hour_from_name(name: &str) -> Option<String> {
    if is_valid_hour_dir(name) {
        return Some(name.to_string());
    }
    let first = name.split_whitespace().next().unwrap_or("");
    if is_valid_hour_dir(first) {
        return Some(first.to_string());
    }
    None
}

fn get_day_for_folder(dir: &Path) -> String {
    // 1. Folder name is 8-digit date
    if let Some(name) = dir.file_name().and_then(|n| n.to_str()) {
        if is_valid_day_dir(name) {
            return name.to_string();
        }
    }
    // 2. Parent folder name is 8-digit date
    if let Some(parent) = dir.parent() {
        if let Some(name) = parent.file_name().and_then(|n| n.to_str()) {
            if is_valid_day_dir(name) {
                return name.to_string();
            }
        }
    }
    // 3. Inspect modified date of the clips
    if let Some(date_str) = find_clip_mtime_date(dir) {
        return date_str;
    }
    // 4. Default to today
    chrono::Local::now().format("%Y%m%d").to_string()
}

fn find_clip_mtime_date(dir: &Path) -> Option<String> {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_file() && p.extension().map(|e| e == "mp4").unwrap_or(false) {
                if let Ok(meta) = p.metadata() {
                    if let Ok(mtime) = meta.modified() {
                        let dt: chrono::DateTime<chrono::Local> = mtime.into();
                        return Some(dt.format("%Y%m%d").to_string());
                    }
                }
            } else if p.is_dir() {
                if let Ok(sub) = fs::read_dir(&p) {
                    for sub_entry in sub.flatten() {
                        let sub_p = sub_entry.path();
                        if sub_p.is_file() && sub_p.extension().map(|e| e == "mp4").unwrap_or(false) {
                            if let Ok(meta) = sub_p.metadata() {
                                if let Ok(mtime) = meta.modified() {
                                    let dt: chrono::DateTime<chrono::Local> = mtime.into();
                                    return Some(dt.format("%Y%m%d").to_string());
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    None
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

    #[test]
    fn scans_direct_hour_directory() {
        let dir = tempdir().unwrap();
        let hour_dir = dir.path().join("11");
        fs::create_dir_all(&hour_dir).unwrap();

        for m in 0..60 {
            fs::write(hour_dir.join(format!("{m:02}.mp4")), b"stub").unwrap();
        }

        let result = scan_record_directory(hour_dir.to_str().unwrap()).unwrap();
        assert_eq!(result.total_days, 1);
        assert_eq!(result.total_hours, 1);
        assert_eq!(result.total_clips, 60);
        assert_eq!(result.days[0].hours[0].hour, "11");
        assert_eq!(result.days[0].hours[0].density, FootageDensity::Complete);
        assert!(result.days[0].hours[0].missing_minutes.is_empty());
    }

    #[test]
    fn scans_direct_day_directory() {
        let dir = tempdir().unwrap();
        let day_dir = dir.path().join("20241020");
        let hour_dir = day_dir.join("14");
        fs::create_dir_all(&hour_dir).unwrap();

        for m in 0..30 {
            fs::write(hour_dir.join(format!("{m:02}.mp4")), b"stub").unwrap();
        }

        let result = scan_record_directory(day_dir.to_str().unwrap()).unwrap();
        assert_eq!(result.total_days, 1);
        assert_eq!(result.total_hours, 1);
        assert_eq!(result.total_clips, 30);
        assert_eq!(result.days[0].day, "20241020");
        assert_eq!(result.days[0].hours[0].hour, "14");
    }

    #[test]
    fn scans_sd_card_root_with_record_dir() {
        let dir = tempdir().unwrap();
        let hour_dir = dir.path().join("record").join("20241020").join("09");
        fs::create_dir_all(&hour_dir).unwrap();

        for m in 0..10 {
            fs::write(hour_dir.join(format!("{m:02}.mp4")), b"stub").unwrap();
        }

        let result = scan_record_directory(dir.path().to_str().unwrap()).unwrap();
        assert_eq!(result.total_days, 1);
        assert_eq!(result.total_hours, 1);
        assert_eq!(result.total_clips, 10);
        assert_eq!(result.days[0].day, "20241020");
        assert_eq!(result.days[0].hours[0].hour, "09");
    }
}
