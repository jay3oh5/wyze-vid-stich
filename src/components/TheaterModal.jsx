import { useEffect, useRef, useState } from 'react';
import { X, ChevronLeft, ChevronRight, FastForward } from 'lucide-react';
import {
  formatDateDisplay,
  formatHourMinute12,
  formatBytes,
  getAdjacentClip
} from '../utils/footage';

const RATES = [0.5, 1, 2, 4];

export function TheaterModal({ previewState, onClose, onSelectMinuteClip }) {
  const videoRef = useRef(null);
  const [rate, setRate] = useState(1);

  const isRawHour = previewState?.mode === 'hour' && previewState?.hourObj;
  const hourObj = isRawHour ? previewState.hourObj : null;
  const currentClip = previewState?.clipFilename || null;

  const prevClip = isRawHour ? getAdjacentClip(hourObj.clips, currentClip, -1) : null;
  const nextClip = isRawHour ? getAdjacentClip(hourObj.clips, currentClip, 1) : null;

  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.playbackRate = rate;
    }
  }, [rate, previewState?.videoPath]);

  useEffect(() => {
    const onKeyDown = (e) => {
      if (e.key === 'Escape') {
        onClose();
      } else if (e.key === 'ArrowLeft' && prevClip && isRawHour) {
        onSelectMinuteClip(previewState.day, hourObj, prevClip, true);
      } else if (e.key === 'ArrowRight' && nextClip && isRawHour) {
        onSelectMinuteClip(previewState.day, hourObj, nextClip, true);
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose, prevClip, nextClip, isRawHour, previewState, hourObj, onSelectMinuteClip]);

  if (!previewState?.videoPath) return null;

  const title = isRawHour
    ? `${formatDateDisplay(previewState.day, true)} · ${formatHourMinute12(hourObj.hour, currentClip || '00')}`
    : previewState.title || 'Theater Playback';

  const streamUrl = `/api/video-stream?path=${encodeURIComponent(previewState.videoPath)}`;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Theater player: ${title}`}
      className="fixed inset-0 z-50 bg-black/90 backdrop-blur-md flex items-center justify-center p-3 sm:p-6"
      onClick={onClose}
    >
      <div
        className="w-full max-w-6xl bg-[#0d1017] border border-white/[0.12] rounded-2xl overflow-hidden shadow-2xl flex flex-col max-h-[94vh]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="px-5 py-3.5 border-b border-white/[0.08] flex items-center justify-between gap-4">
          <div className="min-w-0">
            <h2 className="text-base sm:text-lg font-semibold text-white truncate">{title}</h2>
            <p className="font-mono text-xs text-slate-400 truncate mt-0.5">
              {previewState.videoPath}
              {previewState.sizeBytes ? ` · ${formatBytes(previewState.sizeBytes)}` : ''}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close theater view"
            className="w-9 h-9 rounded-lg flex items-center justify-center text-slate-400 hover:text-white hover:bg-white/[0.08] transition-colors shrink-0 cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Expansive Video Surface */}
        <div className="relative bg-black flex-1 min-h-[320px] flex items-center justify-center overflow-hidden">
          <video
            ref={videoRef}
            key={previewState.videoPath}
            src={streamUrl}
            controls
            autoPlay
            playsInline
            onEnded={() => {
              if (isRawHour && nextClip) {
                onSelectMinuteClip(previewState.day, hourObj, nextClip, true);
              }
            }}
            className="w-full h-full max-h-[76vh] object-contain"
          />
        </div>

        {/* Footer Controls */}
        <div className="px-5 py-3 border-t border-white/[0.08] flex flex-wrap items-center justify-between gap-3 bg-[#090b10]">
          {isRawHour ? (
            <div className="flex items-center gap-2">
              <button
                type="button"
                disabled={!prevClip}
                onClick={() => prevClip && onSelectMinuteClip(previewState.day, hourObj, prevClip, true)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.06] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] disabled:opacity-35 disabled:cursor-not-allowed cursor-pointer"
              >
                <ChevronLeft className="w-4 h-4" />
                <span>Previous Minute</span>
              </button>
              <button
                type="button"
                disabled={!nextClip}
                onClick={() => nextClip && onSelectMinuteClip(previewState.day, hourObj, nextClip, true)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.06] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] disabled:opacity-35 disabled:cursor-not-allowed cursor-pointer"
              >
                <span>Next Minute</span>
                <ChevronRight className="w-4 h-4" />
              </button>
              <span className="hidden sm:inline text-xs text-slate-500 ml-2">
                Tip: Use Left / Right arrow keys to step clips
              </span>
            </div>
          ) : (
            <span className="text-xs text-slate-400">Press Escape to close theater view</span>
          )}

          <div className="flex items-center gap-2">
            <FastForward className="w-3.5 h-3.5 text-slate-400" />
            <div className="inline-flex items-center p-0.5 rounded-lg bg-[#141925] border border-white/[0.08]">
              {RATES.map(r => (
                <button
                  key={r}
                  type="button"
                  onClick={() => setRate(r)}
                  className={`px-2 py-1 rounded-md font-mono text-xs tabular-nums transition-colors cursor-pointer ${
                    rate === r
                      ? 'bg-sky-500 text-slate-950 font-semibold'
                      : 'text-slate-400 hover:text-white'
                  }`}
                >
                  {r}x
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
