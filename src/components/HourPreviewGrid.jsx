import { useState } from 'react';
import {
  Play,
  SlidersHorizontal,
  Check,
  AlertTriangle,
  CheckCircle2,
  Film,
  Maximize2
} from 'lucide-react';
import {
  formatHour12,
  formatHourRange,
  formatBytes,
  getHourCoverageStatus,
  filterHours,
  buildMinuteSlots
} from '../utils/footage';

const GRID_SIZE_CLASSES = {
  standard: 'grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5',
  large: 'grid-cols-1 md:grid-cols-2 gap-6',
  cinema: 'grid-cols-1 gap-6'
};

function HourThumbnail({ clipPath, alt }) {
  const [failed, setFailed] = useState(false);

  if (!clipPath || failed) {
    return (
      <div className="w-full h-full bg-gradient-to-br from-[#161c2c] to-[#0d111b] flex flex-col items-center justify-center text-slate-500">
        <Film className="w-8 h-8 mb-1.5 opacity-60" />
        <span className="text-xs">Preview Ready</span>
      </div>
    );
  }

  return (
    <img
      src={`/api/thumbnail?path=${encodeURIComponent(clipPath)}`}
      alt={alt}
      loading="lazy"
      referrerPolicy="no-referrer"
      onError={() => setFailed(true)}
      className="w-full h-full object-cover transition-transform duration-300 ease-out group-hover:scale-[1.03]"
    />
  );
}

export function HourPreviewGrid({
  dayObj,
  selectedHours,
  activePreviewHour,
  onToggleSelectHour,
  onSelectAllDay,
  onSelectGapsDay,
  onClearDaySelection,
  onPreviewHour,
  onOpenTheaterForHour,
  onOpenInspector
}) {
  const [filterMode, setFilterMode] = useState('all');
  const [previewSize, setPreviewSize] = useState('large');

  const hours = dayObj?.hours || [];
  const filteredHours = filterHours(hours, filterMode, selectedHours, dayObj.day);

  const selectedInDayCount = hours.filter(h =>
    selectedHours.has(`${dayObj.day}_${h.hour}`)
  ).length;
  const gapHoursCount = hours.filter(h => h.missing.length > 0).length;
  const completeHoursCount = hours.filter(h => h.missing.length === 0 && h.clipCount === 60).length;

  const filters = [
    { id: 'all', label: `All (${hours.length})` },
    { id: 'complete', label: `Complete (${completeHoursCount})` },
    { id: 'gaps', label: `With Gaps (${gapHoursCount})` },
    { id: 'selected', label: `Selected (${selectedInDayCount})` }
  ];

  const sizeOptions = [
    { id: 'standard', label: '3-Up' },
    { id: 'large', label: 'Large' },
    { id: 'cinema', label: 'Cinema' }
  ];

  return (
    <section aria-label="Hourly footage previews" className="space-y-4">
      {/* Toolbar: Filter Tabs + Preview Size + Batch Actions */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <div
            className="inline-flex items-center p-1 rounded-lg bg-[#111520] border border-white/[0.08]"
            role="group"
            aria-label="Filter hours"
          >
            {filters.map(f => (
              <button
                key={f.id}
                type="button"
                onClick={() => setFilterMode(f.id)}
                className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors whitespace-nowrap cursor-pointer ${
                  filterMode === f.id
                    ? 'bg-white/[0.12] text-white'
                    : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                {f.label}
              </button>
            ))}
          </div>

          <div
            className="inline-flex items-center p-1 rounded-lg bg-[#111520] border border-white/[0.08]"
            role="group"
            aria-label="Preview card size"
          >
            {sizeOptions.map(opt => (
              <button
                key={opt.id}
                type="button"
                onClick={() => setPreviewSize(opt.id)}
                className={`px-2.5 py-1.5 text-xs font-medium rounded-md transition-colors whitespace-nowrap cursor-pointer ${
                  previewSize === opt.id
                    ? 'bg-sky-500 text-slate-950 font-semibold'
                    : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => onSelectAllDay(dayObj)}
            className="px-3 py-1.5 text-xs font-medium rounded-lg bg-white/[0.04] border border-white/[0.08] text-slate-200 hover:bg-white/[0.08] transition-colors whitespace-nowrap cursor-pointer"
          >
            Select All
          </button>
          <button
            type="button"
            onClick={() => onSelectGapsDay(dayObj)}
            className="px-3 py-1.5 text-xs font-medium rounded-lg bg-white/[0.04] border border-white/[0.08] text-slate-200 hover:bg-white/[0.08] transition-colors whitespace-nowrap cursor-pointer"
          >
            Select Gaps
          </button>
          <button
            type="button"
            onClick={() => onClearDaySelection(dayObj)}
            disabled={selectedInDayCount === 0}
            className="px-3 py-1.5 text-xs font-medium rounded-lg bg-white/[0.04] border border-white/[0.08] text-slate-300 hover:bg-white/[0.08] disabled:opacity-40 disabled:cursor-not-allowed transition-colors whitespace-nowrap cursor-pointer"
          >
            Clear
          </button>
        </div>
      </div>

      {/* Grid of Large Visual Preview Cards */}
      {filteredHours.length === 0 ? (
        <div className="bg-[#111520] border border-white/[0.08] rounded-xl p-10 text-center">
          <p className="text-sm text-slate-400">No hours match the selected filter.</p>
          <button
            type="button"
            onClick={() => setFilterMode('all')}
            className="mt-3 px-4 py-2 text-xs font-medium rounded-lg bg-white/[0.06] hover:bg-white/[0.1] text-white transition-colors cursor-pointer"
          >
            Show All Hours
          </button>
        </div>
      ) : (
        <div className={`grid ${GRID_SIZE_CLASSES[previewSize]}`}>
          {filteredHours.map(hourObj => {
            const key = `${dayObj.day}_${hourObj.hour}`;
            const isSelected = selectedHours.has(key);
            const isPreviewing = activePreviewHour === hourObj.hour;
            const status = getHourCoverageStatus(hourObj.clipCount);
            const minuteSlots = buildMinuteSlots(hourObj.clips);

            return (
              <article
                key={hourObj.hour}
                className={`group rounded-xl overflow-hidden border transition-colors bg-[#111520] ${
                  isSelected
                    ? 'border-sky-400/70 ring-1 ring-sky-400/30'
                    : isPreviewing
                      ? 'border-white/30'
                      : 'border-white/[0.08] hover:border-white/[0.18]'
                }`}
              >
                {/* Large 16:9 Real Video Thumbnail */}
                <div className="relative aspect-video bg-black overflow-hidden">
                  <HourThumbnail
                    clipPath={hourObj.previewClipPath}
                    alt={`Video frame preview for ${dayObj.formattedDay} ${formatHour12(hourObj.hour)}`}
                  />

                  {/* Measured Bottom Gradient Scrim for high contrast on bright frames */}
                  <div
                    aria-hidden="true"
                    className="pointer-events-none absolute inset-x-0 bottom-0 h-28 bg-gradient-to-t from-black/95 via-black/60 to-transparent"
                  />

                  {/* Click-to-preview overlay button */}
                  <button
                    type="button"
                    onClick={() => onPreviewHour(dayObj.day, hourObj)}
                    aria-label={`Preview ${formatHour12(hourObj.hour)} in cinema stage`}
                    className="absolute inset-0 flex items-center justify-center bg-black/0 group-hover:bg-black/25 transition-colors cursor-pointer focus-visible:outline-2 focus-visible:outline-inset focus-visible:outline-sky-400"
                  >
                    <span className="w-12 h-12 rounded-full bg-black/65 border border-white/25 text-white flex items-center justify-center opacity-85 group-hover:opacity-100 group-hover:scale-105 transition-all">
                      <Play className="w-5 h-5 fill-current ml-0.5" />
                    </span>
                  </button>

                  {/* Top-left Select Checkbox Button */}
                  <button
                    type="button"
                    onClick={() => onToggleSelectHour(dayObj.day, hourObj.hour)}
                    aria-pressed={isSelected}
                    aria-label={`Select ${formatHour12(hourObj.hour)} for stitching`}
                    className={`absolute top-3 left-3 z-10 inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-semibold border backdrop-blur-sm transition-colors cursor-pointer ${
                      isSelected
                        ? 'bg-sky-500 border-sky-400 text-slate-950'
                        : 'bg-black/65 border-white/20 text-white hover:bg-black/80'
                    }`}
                  >
                    <span
                      className={`w-3.5 h-3.5 rounded-xs flex items-center justify-center border ${
                        isSelected
                          ? 'border-slate-950/40 bg-slate-950/15'
                          : 'border-white/40'
                      }`}
                    >
                      {isSelected && <Check className="w-3 h-3 stroke-[3]" />}
                    </span>
                    <span>{isSelected ? 'Selected' : 'Select'}</span>
                  </button>

                  {/* Top-right Expand Theater Icon Button */}
                  <button
                    type="button"
                    onClick={() => onOpenTheaterForHour(dayObj.day, hourObj)}
                    aria-label={`Open ${formatHour12(hourObj.hour)} in full theater view`}
                    title="Open in Theater View"
                    className="absolute top-3 right-3 z-10 w-8 h-8 rounded-lg bg-black/65 border border-white/20 text-slate-200 hover:text-white hover:bg-black/85 backdrop-blur-sm flex items-center justify-center transition-colors cursor-pointer"
                  >
                    <Maximize2 className="w-3.5 h-3.5" />
                  </button>

                  {/* Bottom Scrim Timecode & Clip Count */}
                  <div className="pointer-events-none absolute inset-x-3.5 bottom-3 flex items-end justify-between gap-2">
                    <div>
                      <div className="text-base font-bold text-white tracking-tight">
                        {formatHour12(hourObj.hour)}
                      </div>
                      <div className="text-xs text-slate-300 font-mono tabular-nums">
                        {formatHourRange(hourObj.hour)}
                      </div>
                    </div>
                    <div className="font-mono text-xs font-medium text-white/90 tabular-nums">
                      {hourObj.clipCount}/60 min
                    </div>
                  </div>

                  {/* Real 60-minute coverage micro-strip along bottom edge */}
                  <div
                    aria-hidden="true"
                    className="pointer-events-none absolute inset-x-0 bottom-0 h-1 grid"
                    style={{ gridTemplateColumns: 'repeat(60, minmax(0, 1fr))' }}
                  >
                    {minuteSlots.map(slot => (
                      <span
                        key={slot.minute}
                        className={slot.present ? 'bg-emerald-400/90' : 'bg-rose-500/75'}
                      />
                    ))}
                  </div>
                </div>

                {/* Clean Card Footer (Zero-Pill Metadata + Clear Actions) */}
                <div className="p-4 flex flex-wrap items-center justify-between gap-3">
                  <div className="flex flex-wrap items-center gap-2 text-xs text-slate-400 tabular-nums">
                    {status === 'complete' ? (
                      <span className="inline-flex items-center gap-1 text-emerald-400 font-medium">
                        <CheckCircle2 className="w-3.5 h-3.5" />
                        Complete
                      </span>
                    ) : status === 'minor-gaps' ? (
                      <span className="inline-flex items-center gap-1 text-amber-400 font-medium">
                        <AlertTriangle className="w-3.5 h-3.5" />
                        {hourObj.missing.length} missing
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 text-rose-400 font-medium">
                        <AlertTriangle className="w-3.5 h-3.5" />
                        {hourObj.missing.length} missing
                      </span>
                    )}
                    <span aria-hidden="true">·</span>
                    <span className="font-mono">{formatBytes(hourObj.totalSizeBytes)}</span>
                    {hourObj.existingCompiledPath && (
                      <>
                        <span aria-hidden="true">·</span>
                        <span className="text-sky-400">Compiled</span>
                      </>
                    )}
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => onOpenInspector(dayObj.day, hourObj)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.04] border border-white/[0.08] text-slate-200 hover:bg-white/[0.08] transition-colors whitespace-nowrap cursor-pointer"
                    >
                      <SlidersHorizontal className="w-3.5 h-3.5 text-slate-400" />
                      <span>Inspect Clips</span>
                    </button>
                  </div>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}
