/**
 * Pure formatting, filtering, and timeline helpers for Wyze SD card footage.
 */

const MONTH_NAMES = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

const WEEKDAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/**
 * Format a 2-digit 24h hour string ("00".."23") to "12:00 AM".."11:00 PM".
 */
export function formatHour12(hourStr) {
  const h = parseInt(hourStr, 10);
  if (Number.isNaN(h) || h < 0 || h > 23) return String(hourStr ?? '');
  const ampm = h >= 12 ? 'PM' : 'AM';
  const displayH = h % 12 === 0 ? 12 : h % 12;
  return `${displayH}:00 ${ampm}`;
}

/**
 * Format a 2-digit hour string to a compact label ("12 AM", "1 PM").
 */
export function formatHourShort(hourStr) {
  const h = parseInt(hourStr, 10);
  if (Number.isNaN(h) || h < 0 || h > 23) return String(hourStr ?? '');
  const ampm = h >= 12 ? 'PM' : 'AM';
  const displayH = h % 12 === 0 ? 12 : h % 12;
  return `${displayH} ${ampm}`;
}

/**
 * Format an hour + minute pair into a readable timestamp ("12:05 AM").
 */
export function formatHourMinute12(hourStr, minuteStr) {
  const h = parseInt(hourStr, 10);
  if (Number.isNaN(h) || h < 0 || h > 23) return `${hourStr}:${minuteStr}`;
  const ampm = h >= 12 ? 'PM' : 'AM';
  const displayH = h % 12 === 0 ? 12 : h % 12;
  const minPadded = String(minuteStr).replace(/\.mp4$/i, '').padStart(2, '0');
  return `${displayH}:${minPadded} ${ampm}`;
}

/**
 * Format an hour range ("00" -> "12:00 AM – 12:59 AM").
 */
export function formatHourRange(hourStr) {
  const h = parseInt(hourStr, 10);
  if (Number.isNaN(h) || h < 0 || h > 23) return String(hourStr ?? '');
  const ampm = h >= 12 ? 'PM' : 'AM';
  const displayH = h % 12 === 0 ? 12 : h % 12;
  return `${displayH}:00 – ${displayH}:59 ${ampm}`;
}

/**
 * Format "YYYYMMDD" to human-readable date ("Fri, May 29, 2026" or "May 29, 2026").
 */
export function formatDateDisplay(dayStr, includeWeekday = false) {
  if (!dayStr || !/^\d{8}$/.test(dayStr)) return String(dayStr ?? '');
  const year = parseInt(dayStr.slice(0, 4), 10);
  const monthIdx = parseInt(dayStr.slice(4, 6), 10) - 1;
  const day = parseInt(dayStr.slice(6, 8), 10);
  const monthName = MONTH_NAMES[monthIdx] || dayStr.slice(4, 6);

  if (!includeWeekday) {
    return `${monthName} ${day}, ${year}`;
  }

  const utcDate = new Date(Date.UTC(year, monthIdx, day));
  const weekday = WEEKDAY_NAMES[utcDate.getUTCDay()];
  return `${weekday}, ${monthName} ${day}, ${year}`;
}

/**
 * Format bytes to human-readable string ("968 KB", "14.2 MB", "1.45 GB").
 */
export function formatBytes(bytes) {
  if (!bytes || bytes <= 0) return '0 B';
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(kb >= 100 ? 0 : 1)} KB`;
  const mb = kb / 1024;
  if (mb < 1024) return `${mb.toFixed(mb >= 100 ? 0 : 1)} MB`;
  const gb = mb / 1024;
  return `${gb.toFixed(2)} GB`;
}

/**
 * Classify hour completeness from clip count (0..60).
 */
export function getHourCoverageStatus(clipCount) {
  if (!clipCount || clipCount <= 0) return 'empty';
  if (clipCount >= 60) return 'complete';
  if (clipCount >= 30) return 'minor-gaps';
  return 'severe-gaps';
}

/**
 * Compute aggregate statistics for a scanned day.
 */
export function getDaySummary(dayObj) {
  const hours = dayObj?.hours || [];
  let totalClips = 0;
  let gapHoursCount = 0;
  let completeHoursCount = 0;
  let totalSizeBytes = 0;

  for (const h of hours) {
    const count = h.clipCount || 0;
    totalClips += count;
    totalSizeBytes += h.totalSizeBytes || 0;
    if (count >= 60) {
      completeHoursCount += 1;
    } else if (count > 0) {
      gapHoursCount += 1;
    }
  }

  const totalPossibleClips = hours.length * 60;
  const coveragePct = totalPossibleClips > 0
    ? Math.round((totalClips / totalPossibleClips) * 100)
    : 0;

  return {
    totalHours: hours.length,
    totalClips,
    totalPossibleClips,
    coveragePct,
    gapHoursCount,
    completeHoursCount,
    totalSizeBytes
  };
}

/**
 * Filter a day's hour objects by filter mode ('all' | 'complete' | 'gaps' | 'selected').
 */
export function filterHours(hours, filterMode, selectedHoursSet, dayStr) {
  if (!Array.isArray(hours)) return [];
  switch (filterMode) {
    case 'complete':
      return hours.filter(h => (h.missing?.length || 0) === 0 && h.clipCount === 60);
    case 'gaps':
      return hours.filter(h => (h.missing?.length || 0) > 0);
    case 'selected':
      return hours.filter(h => selectedHoursSet?.has(`${dayStr}_${h.hour}`));
    case 'all':
    default:
      return hours;
  }
}

/**
 * Build a 60-element minute slot array ("00".."59") from an hour's present clip filenames.
 */
export function buildMinuteSlots(clips) {
  const clipSet = new Set(clips || []);
  const slots = [];
  for (let m = 0; m < 60; m++) {
    const minute = String(m).padStart(2, '0');
    const filename = `${minute}.mp4`;
    slots.push({
      index: m,
      minute,
      filename,
      present: clipSet.has(filename)
    });
  }
  return slots;
}

/**
 * Find the next or previous available clip filename in sorted clips array.
 */
export function getAdjacentClip(clips, currentFilename, direction) {
  if (!Array.isArray(clips) || clips.length === 0) return null;
  const idx = clips.indexOf(currentFilename);
  if (idx === -1) {
    return direction >= 0 ? clips[0] : clips[clips.length - 1];
  }
  const nextIdx = idx + (direction >= 0 ? 1 : -1);
  if (nextIdx < 0 || nextIdx >= clips.length) return null;
  return clips[nextIdx];
}

/**
 * Parse a compiled output filename into a clean user-facing label.
 */
export function formatOutputLabel(filename) {
  if (!filename) return 'Compiled Video';
  const base = filename.replace(/\.mp4$/i, '');
  // Legacy format: YYYYMMDD_HH
  const legacyMatch = base.match(/^(\d{8})_(\d{2})$/);
  if (legacyMatch) {
    return `${formatDateDisplay(legacyMatch[1])} · ${formatHour12(legacyMatch[2])}`;
  }
  // Standard format: YYYY-MM-DD_!12AM or YYYY-MM-DD_1PM
  const stdMatch = base.match(/^(\d{4})-(\d{2})-(\d{2})_!?(\d{1,2})(AM|PM)$/i);
  if (stdMatch) {
    const dayStr = `${stdMatch[1]}${stdMatch[2]}${stdMatch[3]}`;
    return `${formatDateDisplay(dayStr)} · ${stdMatch[4]}:00 ${stdMatch[5].toUpperCase()}`;
  }
  return base;
}
