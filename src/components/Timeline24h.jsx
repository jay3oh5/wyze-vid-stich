import { formatHour12, getHourCoverageStatus } from '../utils/footage';

export function Timeline24h({ dayObj, activeHour, selectedHours, onPreviewHour, onToggleSelectHour }) {
  const hoursMap = new Map((dayObj?.hours || []).map(h => [parseInt(h.hour, 10), h]));

  const slots = Array.from({ length: 24 }, (_, h) => {
    const hourStr = String(h).padStart(2, '0');
    const hourObj = hoursMap.get(h) || null;
    const status = hourObj ? getHourCoverageStatus(hourObj.clipCount) : 'empty';
    const isSelected = selectedHours.has(`${dayObj.day}_${hourStr}`);
    const isActive = activeHour === hourStr;
    return { h, hourStr, hourObj, status, isSelected, isActive };
  });

  return (
    <section
      aria-label="24-hour footage coverage timeline"
      className="bg-[#111520] border border-white/[0.08] rounded-xl p-4"
    >
      <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
        <div>
          <h3 className="text-sm font-semibold text-[#f4f6fa]">24-Hour Coverage Timeline</h3>
          <p className="text-xs text-slate-400 mt-0.5">
            Click any recorded hour to preview it above, or Shift-click to toggle stitch selection.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-4 text-xs text-slate-400">
          <span className="inline-flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-xs bg-emerald-500" aria-hidden="true" />
            Complete (60m)
          </span>
          <span className="inline-flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-xs bg-amber-500" aria-hidden="true" />
            Minor gaps
          </span>
          <span className="inline-flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-xs bg-rose-500" aria-hidden="true" />
            Severe gaps
          </span>
          <span className="inline-flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-xs bg-white/[0.07]" aria-hidden="true" />
            No footage
          </span>
        </div>
      </div>

      <div className="grid grid-cols-12 sm:grid-cols-24 gap-1" role="group" aria-label="Hourly slots">
        {slots.map(slot => {
          let fillClass = 'bg-white/[0.05] text-slate-600 cursor-default';
          if (slot.status === 'complete') {
            fillClass = 'bg-emerald-500/80 hover:bg-emerald-400 text-slate-950 cursor-pointer';
          } else if (slot.status === 'minor-gaps') {
            fillClass = 'bg-amber-500/80 hover:bg-amber-400 text-slate-950 cursor-pointer';
          } else if (slot.status === 'severe-gaps') {
            fillClass = 'bg-rose-500/80 hover:bg-rose-400 text-white cursor-pointer';
          }

          const ringClass = slot.isActive
            ? 'ring-2 ring-sky-400 ring-offset-2 ring-offset-[#111520]'
            : slot.isSelected
              ? 'ring-1 ring-white/80'
              : '';

          const label = slot.hourObj
            ? `${formatHour12(slot.hourStr)}: ${slot.hourObj.clipCount} of 60 clips`
            : `${formatHour12(slot.hourStr)}: No footage`;

          return (
            <button
              key={slot.hourStr}
              type="button"
              disabled={!slot.hourObj}
              title={label}
              aria-label={label}
              onClick={(e) => {
                if (!slot.hourObj) return;
                if (e.shiftKey) {
                  onToggleSelectHour(dayObj.day, slot.hourStr);
                } else {
                  onPreviewHour(dayObj.day, slot.hourObj);
                }
              }}
              className={`h-8 rounded-sm transition-all flex items-center justify-center font-mono text-[10px] font-semibold tabular-nums focus-visible:outline-2 focus-visible:outline-sky-400 ${fillClass} ${ringClass}`}
            >
              {slot.hourObj ? slot.hourStr : ''}
            </button>
          );
        })}
      </div>

      <div className="mt-2 hidden sm:flex justify-between font-mono text-[11px] text-slate-500 tabular-nums px-0.5">
        <span>12 AM</span>
        <span>6 AM</span>
        <span>12 PM</span>
        <span>6 PM</span>
        <span>11 PM</span>
      </div>
    </section>
  );
}
