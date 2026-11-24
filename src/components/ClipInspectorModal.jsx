import { useEffect, useState } from 'react';
import { X, Play, Check } from 'lucide-react';
import {
  formatDateDisplay,
  formatHour12,
  formatHourMinute12,
  formatBytes,
  buildMinuteSlots
} from '../utils/footage';

export function ClipInspectorModal({
  day,
  hourObj,
  stitching,
  onClose,
  onStitchCustom
}) {
  const [selectedClips, setSelectedClips] = useState(() => new Set(hourObj?.clips || []));
  const [previewClip, setPreviewClip] = useState(() => hourObj?.clips?.[0] || null);

  useEffect(() => {
    const onKeyDown = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  if (!day || !hourObj) return null;

  const minuteSlots = buildMinuteSlots(hourObj.clips);

  const toggleClip = (filename) => {
    setSelectedClips(prev => {
      const next = new Set(prev);
      if (next.has(filename)) {
        next.delete(filename);
      } else {
        next.add(filename);
      }
      return next;
    });
  };

  const selectAll = () => setSelectedClips(new Set(hourObj.clips));
  const selectNone = () => setSelectedClips(new Set());
  const invertSelection = () => {
    setSelectedClips(prev => {
      const next = new Set();
      for (const clip of hourObj.clips) {
        if (!prev.has(clip)) next.add(clip);
      }
      return next;
    });
  };

  const activeClipDetail = previewClip ? hourObj.clipDetails?.[previewClip] : null;
  const activeClipPath = activeClipDetail?.path || (previewClip && hourObj.hourDirPath ? `${hourObj.hourDirPath}/${previewClip}` : null);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Inspect clips for ${formatDateDisplay(day)} ${formatHour12(hourObj.hour)}`}
      className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-3 sm:p-6"
      onClick={onClose}
    >
      <div
        className="w-full max-w-5xl bg-[#111520] border border-white/[0.12] rounded-2xl overflow-hidden shadow-2xl flex flex-col max-h-[92vh]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Modal Header */}
        <div className="px-6 py-4 border-b border-white/[0.08] flex items-center justify-between gap-4">
          <div>
            <h2 className="text-lg font-semibold text-white">
              Clip Inspector · {formatDateDisplay(day)} · {formatHour12(hourObj.hour)}
            </h2>
            <p className="text-xs text-slate-400 mt-0.5 tabular-nums">
              {hourObj.clipCount} of 60 minutes recorded · {selectedClips.size} selected for export
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close clip inspector"
            className="w-9 h-9 rounded-lg flex items-center justify-center text-slate-400 hover:text-white hover:bg-white/[0.08] transition-colors cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Split Content: Large Live Preview Left + 60-Minute Selector Right */}
        <div className="grid grid-cols-1 lg:grid-cols-12 divide-y lg:divide-y-0 lg:divide-x divide-white/[0.08] overflow-y-auto flex-1">
          {/* Left: Large Live Clip Preview */}
          <div className="lg:col-span-6 p-5 flex flex-col gap-3 bg-[#0d1017]">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-slate-300">
                {previewClip
                  ? `Previewing ${formatHourMinute12(hourObj.hour, previewClip)}`
                  : 'Select a minute to preview'}
              </span>
              {activeClipDetail?.sizeBytes > 0 && (
                <span className="font-mono text-xs text-slate-400 tabular-nums">
                  {previewClip} · {formatBytes(activeClipDetail.sizeBytes)}
                </span>
              )}
            </div>

            <div className="relative aspect-video bg-black rounded-lg overflow-hidden border border-white/[0.08]">
              {activeClipPath ? (
                <video
                  key={activeClipPath}
                  src={`/api/video-stream?path=${encodeURIComponent(activeClipPath)}`}
                  poster={`/api/thumbnail?path=${encodeURIComponent(activeClipPath)}`}
                  controls
                  playsInline
                  className="w-full h-full object-contain"
                />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-xs text-slate-500">
                  No clip selected
                </div>
              )}
            </div>

            {previewClip && (
              <div className="flex items-center justify-between gap-3 pt-1">
                <span className="text-xs text-slate-400">
                  Include <span className="font-mono text-slate-200">{previewClip}</span> in stitch?
                </span>
                <button
                  type="button"
                  onClick={() => toggleClip(previewClip)}
                  className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors cursor-pointer ${
                    selectedClips.has(previewClip)
                      ? 'bg-sky-500/15 border-sky-400/40 text-sky-200'
                      : 'bg-white/[0.04] border-white/[0.08] text-slate-300 hover:bg-white/[0.08]'
                  }`}
                >
                  <Check className="w-3.5 h-3.5" />
                  <span>{selectedClips.has(previewClip) ? 'Included' : 'Excluded'}</span>
                </button>
              </div>
            )}
          </div>

          {/* Right: 60-Minute Grid */}
          <div className="lg:col-span-6 p-5 flex flex-col gap-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={selectAll}
                  className="px-2.5 py-1.5 text-xs font-medium rounded-md bg-white/[0.05] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] cursor-pointer"
                >
                  Select All
                </button>
                <button
                  type="button"
                  onClick={invertSelection}
                  className="px-2.5 py-1.5 text-xs font-medium rounded-md bg-white/[0.05] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] cursor-pointer"
                >
                  Invert
                </button>
                <button
                  type="button"
                  onClick={selectNone}
                  className="px-2.5 py-1.5 text-xs font-medium rounded-md bg-white/[0.05] border border-white/[0.08] text-slate-300 hover:bg-white/[0.1] cursor-pointer"
                >
                  Clear
                </button>
              </div>
              <span className="font-mono text-xs text-slate-400 tabular-nums">
                {selectedClips.size} / {hourObj.clipCount} clips
              </span>
            </div>

            <div className="grid grid-cols-6 sm:grid-cols-10 gap-1.5">
              {minuteSlots.map(slot => {
                const isIncluded = selectedClips.has(slot.filename);
                const isPreviewing = previewClip === slot.filename;

                return (
                  <button
                    key={slot.minute}
                    type="button"
                    disabled={!slot.present}
                    aria-label={`Toggle minute ${slot.minute} (${slot.present ? (isIncluded ? 'included' : 'excluded') : 'missing'})`}
                    onClick={() => {
                      if (!slot.present) return;
                      setPreviewClip(slot.filename);
                      toggleClip(slot.filename);
                    }}
                    className={`rounded-lg border py-2 px-1 flex flex-col items-center justify-center gap-0.5 transition-colors disabled:cursor-not-allowed cursor-pointer ${
                      !slot.present
                        ? 'bg-rose-500/5 border-rose-500/15 text-slate-600'
                        : isIncluded
                          ? 'bg-sky-500/15 border-sky-400/50 text-sky-100 hover:bg-sky-500/25'
                          : 'bg-white/[0.03] border-white/[0.08] text-slate-400 hover:bg-white/[0.08]'
                    } ${isPreviewing ? 'ring-2 ring-white ring-offset-1 ring-offset-[#111520]' : ''}`}
                  >
                    <span className="font-mono text-xs font-semibold tabular-nums leading-none">
                      {slot.minute}
                    </span>
                    <span className="text-[10px] leading-none mt-1">
                      {!slot.present ? '—' : isIncluded ? '✓' : 'off'}
                    </span>
                  </button>
                );
              })}
            </div>

            <p className="text-xs text-slate-500">
              Click any minute tile to preview it and toggle its inclusion. Missing minutes appear dimmed.
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-white/[0.08] bg-[#0d1017] flex flex-wrap items-center justify-between gap-3">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-lg text-sm font-medium bg-white/[0.05] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] transition-colors cursor-pointer"
          >
            Cancel
          </button>

          <button
            type="button"
            disabled={selectedClips.size === 0 || stitching}
            onClick={() => onStitchCustom(day, hourObj.hour, Array.from(selectedClips).sort())}
            className="inline-flex items-center gap-2 px-5 py-2 rounded-lg text-sm font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 disabled:opacity-40 disabled:cursor-not-allowed transition-colors cursor-pointer"
          >
            <Play className="w-4 h-4 fill-current" />
            <span>Stitch Selected ({selectedClips.size} min)</span>
          </button>
        </div>
      </div>
    </div>
  );
}
