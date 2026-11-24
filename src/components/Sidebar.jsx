import { FolderOpen, RefreshCw, Calendar, PlayCircle, X } from 'lucide-react';
import {
  formatDateDisplay,
  formatBytes,
  getDaySummary,
  formatOutputLabel
} from '../utils/footage';

export function Sidebar({
  activeTab,
  onSelectTab,
  activeJobCount,
  sourceDir,
  days,
  selectedDay,
  onSelectDay,
  stitchedOutputs,
  activePreviewPath,
  onPlayStitchedOutput,
  onOpenBrowse,
  onScan,
  scanning,
  mobileOpen,
  onCloseMobile
}) {
  const mobileNavItems = [
    { id: 'library', label: 'Footage Library' },
    {
      id: 'queue',
      label: activeJobCount > 0 ? `Render Queue (${activeJobCount})` : 'Render Queue'
    },
    { id: 'settings', label: 'Settings' }
  ];

  const sidebarBody = (
    <div className="flex flex-col h-full bg-[#0d1017] border-r border-white/[0.08] w-[272px] shrink-0">
      {/* Mobile Workspace Navigation */}
      <div className="md:hidden p-3 border-b border-white/[0.08] flex flex-col gap-1">
        {mobileNavItems.map(item => (
          <button
            key={item.id}
            type="button"
            onClick={() => {
              onSelectTab(item.id);
              if (onCloseMobile) onCloseMobile();
            }}
            className={`w-full text-left px-3 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer ${
              activeTab === item.id
                ? 'bg-sky-500/15 text-sky-300'
                : 'text-slate-300 hover:bg-white/[0.05] hover:text-white'
            }`}
          >
            {item.label}
          </button>
        ))}
      </div>

      {/* Source Folder Controls */}
      <div className="p-4 border-b border-white/[0.08]">
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs font-medium text-slate-400">Source Directory</span>
          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={onOpenBrowse}
              aria-label="Browse source folder"
              className="px-2 py-1 text-xs font-medium text-slate-300 hover:text-white hover:bg-white/[0.06] rounded transition-colors cursor-pointer"
            >
              Change
            </button>
            <button
              type="button"
              onClick={onScan}
              disabled={scanning}
              aria-label="Rescan source directory"
              className="p-1.5 text-slate-400 hover:text-white hover:bg-white/[0.06] rounded transition-colors disabled:opacity-40 cursor-pointer"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${scanning ? 'animate-spin' : ''}`} />
            </button>
            {mobileOpen && (
              <button
                type="button"
                onClick={onCloseMobile}
                aria-label="Close sidebar"
                className="lg:hidden p-1.5 text-slate-400 hover:text-white rounded"
              >
                <X className="w-4 h-4" />
              </button>
            )}
          </div>
        </div>
        <button
          type="button"
          onClick={onOpenBrowse}
          title={sourceDir}
          className="w-full flex items-center gap-2 px-2.5 py-2 rounded-lg bg-[#141925] border border-white/[0.08] hover:border-white/[0.18] text-left transition-colors cursor-pointer"
        >
          <FolderOpen className="w-4 h-4 text-sky-400 shrink-0" />
          <span className="font-mono text-xs text-slate-200 truncate">{sourceDir}</span>
        </button>
      </div>

      {/* Recorded Days */}
      <div className="flex-1 overflow-y-auto divide-y divide-white/[0.06]">
        <div className="p-4">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-xs font-semibold text-slate-400 flex items-center gap-1.5">
              <Calendar className="w-3.5 h-3.5" />
              Recorded Days
            </h2>
            <span className="font-mono text-xs text-slate-500 tabular-nums">
              {days.length}
            </span>
          </div>

          {days.length === 0 ? (
            <p className="text-xs text-slate-500 leading-relaxed">
              No YYYYMMDD folders detected in this directory yet.
            </p>
          ) : (
            <ul className="space-y-1.5">
              {days.map(dayObj => {
                const isSelected = selectedDay === dayObj.day;
                const summary = getDaySummary(dayObj);
                return (
                  <li key={dayObj.day}>
                    <button
                      type="button"
                      onClick={() => {
                        onSelectDay(dayObj.day);
                        if (onCloseMobile) onCloseMobile();
                      }}
                      className={`w-full text-left px-3 py-2.5 rounded-lg border transition-colors cursor-pointer ${
                        isSelected
                          ? 'bg-sky-500/12 border-sky-400/35 text-white'
                          : 'bg-transparent border-transparent hover:bg-white/[0.04] text-slate-300'
                      }`}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-sm font-medium truncate">
                          {formatDateDisplay(dayObj.day)}
                        </span>
                        <span className="font-mono text-xs text-slate-400 tabular-nums shrink-0">
                          {summary.totalHours}h
                        </span>
                      </div>
                      <div className="mt-1 flex items-center gap-1.5 text-xs text-slate-400 tabular-nums">
                        <span>{summary.totalClips} clips</span>
                        <span aria-hidden="true">·</span>
                        <span>{formatBytes(summary.totalSizeBytes)}</span>
                      </div>
                      {/* Subtle completeness bar */}
                      <div className="mt-2 h-1 w-full bg-white/[0.06] rounded-full overflow-hidden">
                        <div
                          className={`h-full rounded-full ${
                            summary.coveragePct === 100
                              ? 'bg-emerald-500'
                              : summary.coveragePct >= 60
                                ? 'bg-sky-400'
                                : 'bg-amber-500'
                          }`}
                          style={{ width: `${summary.coveragePct}%` }}
                        />
                      </div>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        {/* Stitched Outputs Library */}
        <div className="p-4">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-xs font-semibold text-slate-400 flex items-center gap-1.5">
              <PlayCircle className="w-3.5 h-3.5" />
              Compiled Videos
            </h2>
            <span className="font-mono text-xs text-slate-500 tabular-nums">
              {stitchedOutputs.length}
            </span>
          </div>

          {stitchedOutputs.length === 0 ? (
            <p className="text-xs text-slate-500 leading-relaxed">
              Stitched hourly videos will appear here for instant playback.
            </p>
          ) : (
            <ul className="space-y-1.5">
              {stitchedOutputs.map(item => {
                const isPlaying = activePreviewPath === item.path;
                return (
                  <li key={item.path}>
                    <button
                      type="button"
                      onClick={() => {
                        onPlayStitchedOutput(item);
                        if (onCloseMobile) onCloseMobile();
                      }}
                      className={`w-full text-left px-3 py-2.5 rounded-lg border transition-colors cursor-pointer ${
                        isPlaying
                          ? 'bg-emerald-500/12 border-emerald-400/35 text-white'
                          : 'bg-transparent border-transparent hover:bg-white/[0.04] text-slate-300'
                      }`}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-xs font-medium text-slate-100 truncate">
                          {formatOutputLabel(item.name)}
                        </span>
                      </div>
                      <div className="mt-1 flex items-center justify-between gap-2 text-[11px] text-slate-400 font-mono tabular-nums">
                        <span className="truncate">{item.name}</span>
                        <span className="shrink-0">{formatBytes(item.sizeBytes)}</span>
                      </div>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </div>
    </div>
  );

  return (
    <>
      {/* Desktop persistent sidebar */}
      <aside className="hidden lg:flex shrink-0" aria-label="Footage navigation">
        {sidebarBody}
      </aside>

      {/* Mobile slide-over drawer */}
      {mobileOpen && (
        <div className="fixed inset-0 z-50 lg:hidden flex">
          <div
            className="fixed inset-0 bg-black/70 backdrop-blur-xs"
            onClick={onCloseMobile}
            aria-hidden="true"
          />
          <aside className="relative z-10 flex h-full" aria-label="Footage navigation">
            {sidebarBody}
          </aside>
        </div>
      )}
    </>
  );
}
