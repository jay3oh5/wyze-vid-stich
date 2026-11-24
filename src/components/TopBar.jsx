import { Film, Play, RefreshCw, Menu } from 'lucide-react';

export function TopBar({
  activeTab,
  onSelectTab,
  selectedCount,
  activeJobCount,
  stitching,
  scanning,
  hasDays,
  onPrimaryAction,
  onToggleMobileMenu
}) {
  const navItems = [
    { id: 'library', label: 'Footage Library' },
    {
      id: 'queue',
      label: activeJobCount > 0 ? `Render Queue (${activeJobCount})` : 'Render Queue'
    },
    { id: 'settings', label: 'Settings' }
  ];

  const canStitch = selectedCount > 0 && !stitching;

  return (
    <header className="sticky top-0 z-30 h-16 bg-[#090b10]/95 backdrop-blur-md border-b border-white/[0.08] px-3 sm:px-4 lg:px-6 flex items-center justify-between gap-3 sm:gap-6 lg:gap-8">
      {/* Zone 1: Brand wordmark (single line, clean) */}
      <div className="flex items-center gap-2 sm:gap-3 min-w-0 shrink">
        <button
          type="button"
          onClick={onToggleMobileMenu}
          aria-label="Toggle navigation menu"
          className="lg:hidden inline-flex items-center justify-center w-9 h-9 rounded-lg text-slate-300 hover:text-white hover:bg-white/[0.06] transition-colors shrink-0 cursor-pointer"
        >
          <Menu className="w-5 h-5" />
        </button>
        <button
          type="button"
          onClick={() => onSelectTab('library')}
          className="flex items-center gap-2 sm:gap-2.5 text-left whitespace-nowrap min-w-0 focus-visible:outline-2 focus-visible:outline-sky-400 focus-visible:outline-offset-2 rounded cursor-pointer"
        >
          <span className="inline-flex items-center justify-center w-8 h-8 rounded-lg bg-sky-500/15 border border-sky-400/25 text-sky-400 shrink-0">
            <Film className="w-4 h-4" />
          </span>
          <span className="font-semibold tracking-tight text-sm sm:text-base text-[#f4f6fa] whitespace-nowrap truncate">
            Wyze Video Stitcher
          </span>
        </button>
      </div>

      {/* Zone 2: Clean single-line navigation links (desktop/tablet) */}
      <nav aria-label="Primary workspace navigation" className="hidden md:flex items-center gap-6 shrink-0">
        {navItems.map(item => {
          const isActive = activeTab === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => onSelectTab(item.id)}
              aria-current={isActive ? 'page' : undefined}
              className={`relative py-5 px-2 text-sm font-medium transition-colors whitespace-nowrap shrink-0 cursor-pointer focus-visible:outline-2 focus-visible:outline-sky-400 ${
                isActive
                  ? 'text-[#f4f6fa]'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {item.label}
              {isActive && (
                <span
                  aria-hidden="true"
                  className="absolute inset-x-1 bottom-0 h-0.5 bg-sky-400 rounded-full"
                />
              )}
            </button>
          );
        })}
      </nav>

      {/* Zone 3: Single primary CTA */}
      <div className="shrink-0">
        {hasDays && selectedCount > 0 ? (
          <button
            type="button"
            onClick={onPrimaryAction}
            disabled={!canStitch}
            className="inline-flex items-center gap-1.5 sm:gap-2 px-3 sm:px-4 py-2 rounded-lg text-xs sm:text-sm font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 disabled:opacity-40 disabled:cursor-not-allowed transition-colors whitespace-nowrap shrink-0 cursor-pointer"
          >
            <Play className="w-3.5 h-3.5 sm:w-4 sm:h-4 fill-current" />
            <span className="sm:hidden">Stitch ({selectedCount})</span>
            <span className="hidden sm:inline">Stitch Selected ({selectedCount})</span>
          </button>
        ) : (
          <button
            type="button"
            onClick={onPrimaryAction}
            disabled={scanning || stitching}
            className="inline-flex items-center gap-1.5 sm:gap-2 px-3 sm:px-4 py-2 rounded-lg text-xs sm:text-sm font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 disabled:opacity-40 disabled:cursor-not-allowed transition-colors whitespace-nowrap shrink-0 cursor-pointer"
          >
            <RefreshCw className={`w-3.5 h-3.5 sm:w-4 sm:h-4 ${scanning ? 'animate-spin' : ''}`} />
            <span className="sm:hidden">{scanning ? 'Scanning' : 'Rescan'}</span>
            <span className="hidden sm:inline">{scanning ? 'Scanning...' : 'Rescan Folder'}</span>
          </button>
        )}
      </div>
    </header>
  );
}
