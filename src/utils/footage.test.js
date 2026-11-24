import test from 'node:test';
import assert from 'node:assert/strict';
import {
  formatHour12,
  formatHourShort,
  formatHourMinute12,
  formatHourRange,
  formatDateDisplay,
  formatBytes,
  getHourCoverageStatus,
  getDaySummary,
  filterHours,
  buildMinuteSlots,
  getAdjacentClip,
  formatOutputLabel
} from './footage.js';

test('formatHour12 converts 24h strings accurately', () => {
  assert.equal(formatHour12('00'), '12:00 AM');
  assert.equal(formatHour12('01'), '1:00 AM');
  assert.equal(formatHour12('12'), '12:00 PM');
  assert.equal(formatHour12('15'), '3:00 PM');
  assert.equal(formatHour12('23'), '11:00 PM');
});

test('formatHourShort and formatHourRange produce readable ranges', () => {
  assert.equal(formatHourShort('00'), '12 AM');
  assert.equal(formatHourShort('13'), '1 PM');
  assert.equal(formatHourRange('00'), '12:00 – 12:59 AM');
  assert.equal(formatHourMinute12('00', '05.mp4'), '12:05 AM');
  assert.equal(formatHourMinute12('14', '30'), '2:30 PM');
});

test('formatDateDisplay formats YYYYMMDD dates with optional weekday', () => {
  assert.equal(formatDateDisplay('20260529'), 'May 29, 2026');
  assert.equal(formatDateDisplay('20260529', true), 'Fri, May 29, 2026');
});

test('formatBytes formats sizes across B, KB, MB, GB', () => {
  assert.equal(formatBytes(0), '0 B');
  assert.equal(formatBytes(512), '512 B');
  assert.equal(formatBytes(18432), '18.0 KB');
  assert.equal(formatBytes(991234), '968 KB');
  assert.equal(formatBytes(1572864), '1.5 MB');
});

test('getHourCoverageStatus classifies clip counts', () => {
  assert.equal(getHourCoverageStatus(0), 'empty');
  assert.equal(getHourCoverageStatus(10), 'severe-gaps');
  assert.equal(getHourCoverageStatus(57), 'minor-gaps');
  assert.equal(getHourCoverageStatus(60), 'complete');
});

test('getDaySummary aggregates hours, clips, and bytes', () => {
  const summary = getDaySummary({
    day: '20260529',
    hours: [
      { hour: '00', clipCount: 57, missing: ['04', '15', '32'], totalSizeBytes: 1000000 },
      { hour: '01', clipCount: 60, missing: [], totalSizeBytes: 1100000 },
      { hour: '02', clipCount: 10, missing: Array.from({ length: 50 }, (_, i) => String(i + 10)), totalSizeBytes: 180000 }
    ]
  });
  assert.equal(summary.totalHours, 3);
  assert.equal(summary.totalClips, 127);
  assert.equal(summary.totalPossibleClips, 180);
  assert.equal(summary.coveragePct, 71);
  assert.equal(summary.completeHoursCount, 1);
  assert.equal(summary.gapHoursCount, 2);
  assert.equal(summary.totalSizeBytes, 2280000);
});

test('filterHours supports all, complete, gaps, and selected modes', () => {
  const hours = [
    { hour: '00', clipCount: 57, missing: ['04', '15', '32'] },
    { hour: '01', clipCount: 60, missing: [] },
    { hour: '02', clipCount: 10, missing: ['10'] }
  ];
  const selected = new Set(['20260529_02']);

  assert.equal(filterHours(hours, 'all', selected, '20260529').length, 3);
  assert.deepEqual(filterHours(hours, 'complete', selected, '20260529').map(h => h.hour), ['01']);
  assert.deepEqual(filterHours(hours, 'gaps', selected, '20260529').map(h => h.hour), ['00', '02']);
  assert.deepEqual(filterHours(hours, 'selected', selected, '20260529').map(h => h.hour), ['02']);
});

test('buildMinuteSlots and getAdjacentClip handle missing clips cleanly', () => {
  const clips = ['00.mp4', '01.mp4', '03.mp4'];
  const slots = buildMinuteSlots(clips);
  assert.equal(slots.length, 60);
  assert.equal(slots[0].present, true);
  assert.equal(slots[2].present, false);
  assert.equal(slots[3].present, true);

  assert.equal(getAdjacentClip(clips, '00.mp4', 1), '01.mp4');
  assert.equal(getAdjacentClip(clips, '01.mp4', 1), '03.mp4');
  assert.equal(getAdjacentClip(clips, '03.mp4', 1), null);
  assert.equal(getAdjacentClip(clips, '03.mp4', -1), '01.mp4');
  assert.equal(getAdjacentClip(clips, '00.mp4', -1), null);
});

test('formatOutputLabel formats both legacy and standard output filenames', () => {
  assert.equal(formatOutputLabel('20260529_00.mp4'), 'May 29, 2026 · 12:00 AM');
  assert.equal(formatOutputLabel('2026-05-29_!12AM.mp4'), 'May 29, 2026 · 12:00 AM');
  assert.equal(formatOutputLabel('2026-05-29_2PM.mp4'), 'May 29, 2026 · 2:00 PM');
});
