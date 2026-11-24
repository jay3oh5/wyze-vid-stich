import { useEffect, useRef, useState } from 'react';
import {
  ChevronLeft,
  ChevronRight,
  Maximize2,
  SlidersHorizontal,
  CheckSquare,
  Square,
  Film,
  FastForward,
  Play
} from 'lucide-react';
import {
  formatDateDisplay,
  formatHour12,
  formatHourMinute12,
  formatBytes,
  buildMinuteSlots,
  getAdjacentClip
} from '../utils/footage';

const PLAYBACK_RATES = [0.5, 1, 2, 4];

export function CinemaPreviewStage({
  previewState,
  onSelectMinuteClip,
  onOpenTheater,
  onOpenInspector,
  isHourSelected,
  onToggleSelectHour
}) {
  const videoRef = useRef(null);
  const [playbackRate, setPlaybackRate] = useState(1);
  const [autoAdvance, setAutoAdvance] = useState(true);

  const videoPath = previewState?.videoPath || null;
  const isRawHour = previewState?.mode === 'hour' && previewState?.hourObj;
  const hourObj = isRawHour ? previewState.hourObj : null;
  const currentClip = previewState?.clipFilename || null;

  const prevClip = isRawHour ? getAdjacentClip(hourObj.clips, currentClip, -1) : null;
  const nextClip = isRawHour ? getAdjacentClip(hourObj.clips, currentClip, 1) : null;
  const minuteSlots = isRawHour ? buildMinuteSlots(hourObj.clips) : [];

  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.playbackRate = playbackRate;
    }
  }, [playbackRate, videoPath]);

  const handleVideoEnded = () => {
    if (autoAdvance && isRawHour && nextClip) {
      onSelectMinuteClip(previewState.day, hourObj, nextClip, true);
    }
  };

  if (!videoPath) {
    return (
      <section
        aria-label="Video preview stage"
        className="bg-[#111520] border border-white/[0.08] rounded-xl p-10 flex flex-col items-center justify-center text-center min-h-[340px]"
      >
        <div className="w-12 h-12 rounded-xl bg-white/[0.04] border border-white/[0.08] flex items-center justify-center text-slate-400 mb-4">
          <Film className="w-6 h-6" />
        </div>
        <h2 className="text-lg font-semibold text-[#f4f6fa]">Ready to Preview Footage</h2>
        <p className="text-sm text-slate-400 mt-1.5 max-w-md">
          Select any recorded hour below or a compiled video from the sidebar to review it in full widescreen here.
        </p>
      </section>
    );
  }

  const streamUrl = `/api/video-stream?path=${encodeURIComponent(videoPath)}`;
  const posterUrl = `/api/thumbnail?path=${encodeURIComponent(videoPath)}`;

  const headingTitle = isRawHour
    ? `${formatDateDisplay(previewState.day, true)} · ${formatHourMinute12(hourObj.hour, currentClip || '00')}`
    : previewState.title || 'Compiled Video Preview';

  const subtitleParts = [];
  if (isRawHour) {
    subtitleParts.push(`Hour ${formatHour12(hourObj.hour)}`);
    subtitleParts.push(`${hourObj.clipCount} of 60 min recorded`);
    if (hourObj.missing.length > 0) {
      subtitleParts.push(`${hourObj.missing.length} gaps`);
    }
    const clipInfo = hourObj.clipDetails?.[currentClip];
    if (clipInfo?.sizeBytes) {
      subtitleParts.push(formatBytes(clipInfo.sizeBytes));
    }
  } else {
    subtitleParts.push('Compiled Hourly MP4');
    if (previewState.sizeBytes) {
      subtitleParts.push(formatBytes(previewState.sizeBytes));
    }
  }

  return (
    <section
      aria-label="Cinema preview stage"
      className="bg-[#111520] border border-white/[0.08] rounded-xl overflow-hidden"
    >
      {/* Stage Top Header */}
      <div className="px-5 py-3.5 border-b border-white/[0.08] flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <h2 className="text-base sm:text-lg font-semibold text-[#f4f6fa] truncate">
            {headingTitle}
          </h2>
          <div className="flex flex-wrap items-center gap-2 text-xs text-slate-400 mt-0.5 tabular-nums">
            {subtitleParts.map((part, idx) => (
              <span key={part} className="inline-flex items-center gap-2">
                {idx > 0 && <span aria-hidden="true">·</span>}
                <span>{part}</span>
              </span>
            ))}
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {isRawHour && (
            <>
              <button
                type="button"
                onClick={() => onToggleSelectHour(previewState.day, hourObj.hour)}
                className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors whitespace-nowrap cursor-pointer ${
                  isHourSelected
                    ? 'bg-sky-500/15 border-sky-400/40 text-sky-200 hover:bg-sky-500/20'
                    : 'bg-white/[0.04] border-white/[0.08] text-slate-200 hover:bg-white/[0.08]'
                }`}
              >
                {isHourSelected ? (
                  <CheckSquare className="w-3.5 h-3.5 text-sky-400" />
                ) : (
                  <Square className="w-3.5 h-3.5 text-slate-400" />
                )}
                <span>{isHourSelected ? 'Selected for Stitch' : 'Select Hour'}</span>
              </button>

              <button
                type="button"
                onClick={() => onOpenInspector(previewState.day, hourObj)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.04] border border-white/[0.08] text-slate-200 hover:bg-white/[0.08] transition-colors whitespace-nowrap cursor-pointer"
              >
                <SlidersHorizontal className="w-3.5 h-3.5 text-slate-400" />
                <span>Inspect Clips</span>
              </button>
            </>
          )}

          <button
            type="button"
            onClick={onOpenTheater}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.06] border border-white/[0.12] text-white hover:bg-white/[0.12] transition-colors whitespace-nowrap cursor-pointer"
          >
            <Maximize2 className="w-3.5 h-3.5 text-sky-400" />
            <span>Expand Theater</span>
          </button>
        </div>
      </div>

      {/* Large 16:9 Cinema Video Viewport */}
      <div className="relative w-full bg-black aspect-video max-h-[460px] flex items-center justify-center">
        <video
          ref={videoRef}
          key={videoPath}
          src={streamUrl}
          poster={posterUrl}
          controls
          playsInline
          autoPlay={!!previewState.autoPlay}
          onEnded={handleVideoEnded}
          className="w-full h-full object-contain"
        />
      </div>

      {/* Transport Controls & Interactive 60-Minute Scrubber */}
      <div className="px-5 py-3.5 bg-[#0d1017] border-t border-white/[0.08] space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          {/* Step Controls for Raw Hour Mode */}
          {isRawHour ? (
            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                disabled={!prevClip}
                onClick={() => prevClip && onSelectMinuteClip(previewState.day, hourObj, prevClip, true)}
                className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-md text-xs font-medium bg-white/[0.04] border border-white/[0.08] text-slate-200 hover:bg-white/[0.08] disabled:opacity-35 disabled:cursor-not-allowed transition-colors cursor-pointer"
              >
                <ChevronLeft className="w-3.5 h-3.5" />
                <span>Prev Minute</span>
              </button>
              <button
                type="button"
                disabled={!nextClip}
                onClick={() => nextClip && onSelectMinuteClip(previewState.day, hourObj, nextClip, true)}
                className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-md text-xs font-medium bg-white/[0.04] border border-white/[0.08] text-slate-200 hover:bg-white/[0.08] disabled:opacity-35 disabled:cursor-not-allowed transition-colors cursor-pointer"
              >
                <span>Next Minute</span>
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
              <button
                type="button"
                onClick={() => setAutoAdvance(v => !v)}
                aria-pressed={autoAdvance}
                className={`inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md text-xs font-medium border transition-colors cursor-pointer ${
                  autoAdvance
                    ? 'bg-sky-500/12 border-sky-400/35 text-sky-300'
                    : 'bg-white/[0.03] border-white/[0.08] text-slate-400 hover:text-slate-200'
                }`}
              >
                <Play className="w-3 h-3" />
                <span>Auto-Advance: {autoAdvance ? 'On' : 'Off'}</span>
              </button>
            </div>
          ) : (
            <div className="font-mono text-xs text-slate-400 truncate max-w-md" title={videoPath}>
              {videoPath}
            </div>
          )}

          {/* Speed Selector */}
          <div className="flex items-center gap-2">
            <span className="inline-flex items-center gap-1 text-xs text-slate-400">
              <FastForward className="w-3.5 h-3.5" />
              Speed
            </span>
            <div className="inline-flex items-center p-0.5 rounded-lg bg-[#141925] border border-white/[0.08]">
              {PLAYBACK_RATES.map(rate => (
                <button
                  key={rate}
                  type="button"
                  onClick={() => setPlaybackRate(rate)}
                  className={`px-2 py-1 rounded-md font-mono text-xs tabular-nums transition-colors cursor-pointer ${
                    playbackRate === rate
                      ? 'bg-sky-500 text-slate-950 font-semibold'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  {rate}x
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* 60-Minute Visual Scrubber Strip */}
        {isRawHour && (
          <div>
            <div className="flex items-center justify-between text-[11px] text-slate-400 mb-1.5">
              <span>Minute-by-Minute Scrubber ({formatHour12(hourObj.hour)})</span>
              <span className="font-mono tabular-nums">
                Playing :{String(currentClip || '00').replace('.mp4', '')} · {hourObj.clipCount}/60 present
              </span>
            </div>
            <div
              className="grid gap-[2px]"
              style={{ gridTemplateColumns: 'repeat(60, minmax(0, 1fr))' }}
              role="group"
              aria-label="Minute clips scrubber"
            >
              {minuteSlots.map(slot => {
                const isCurrent = slot.filename === currentClip;
                const label = slot.present
                  ? `Preview ${formatHourMinute12(hourObj.hour, slot.minute)}`
                  : `${formatHourMinute12(hourObj.hour, slot.minute)} (Missing)`;

                return (
                  <button
                    key={slot.minute}
                    type="button"
                    disabled={!slot.present}
                    title={label}
                    aria-label={label}
                    onClick={() => slot.present && onSelectMinuteClip(previewState.day, hourObj, slot.filename, true)}
                    className={`h-6 rounded-[2px] transition-all focus-visible:outline-2 focus-visible:outline-sky-400 ${
                      isCurrent
                        ? 'bg-sky-400 ring-1 ring-white scale-y-110 z-10 cursor-pointer'
                        : slot.present
                          ? 'bg-emerald-500/55 hover:bg-emerald-400 cursor-pointer'
                          : 'bg-rose-500/25 cursor-not-allowed'
                    }`}
                  />
                );
              })}
            </div>
            <div className="flex justify-between font-mono text-[10px] text-slate-500 tabular-nums mt-1">
              <span>:00</span>
              <span>:15</span>
              <span>:30</span>
              <span>:45</span>
              <span>:59</span>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
