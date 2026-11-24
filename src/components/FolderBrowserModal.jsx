import { useEffect, useState } from 'react';
import { Folder, ArrowUp, X, Check, AlertCircle, Film } from 'lucide-react';

export function FolderBrowserModal({ title, initialDir, onSelect, onClose }) {
  const [currentDir, setCurrentDir] = useState(initialDir || '.');
  const [parentDir, setParentDir] = useState(null);
  const [directories, setDirectories] = useState([]);
  const [shortcuts, setShortcuts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const loadDir = async (dirToLoad) => {
    setLoading(true);
    setError('');
    try {
      const res = await fetch(`/api/fs/list?dir=${encodeURIComponent(dirToLoad || '.')}`);
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error || 'Unable to list folder');
      }
      setCurrentDir(data.currentDir);
      setParentDir(data.parentDir);
      setDirectories(data.directories || []);
      setShortcuts(data.shortcuts || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch(`/api/fs/list?dir=${encodeURIComponent(initialDir || '.')}`);
        const data = await res.json();
        if (cancelled) return;
        if (!res.ok) {
          setError(data.error || 'Unable to list folder');
        } else {
          setCurrentDir(data.currentDir);
          setParentDir(data.parentDir);
          setDirectories(data.directories || []);
          setShortcuts(data.shortcuts || []);
        }
      } catch (err) {
        if (!cancelled) setError(err.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [initialDir]);

  useEffect(() => {
    const onKeyDown = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={title || 'Select Folder'}
      className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-2xl bg-[#111520] border border-white/[0.12] rounded-2xl overflow-hidden shadow-2xl flex flex-col max-h-[85vh]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-4 border-b border-white/[0.08] flex items-center justify-between gap-4">
          <h2 className="text-base font-semibold text-white">{title || 'Select Directory'}</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close folder browser"
            className="w-8 h-8 rounded-lg flex items-center justify-center text-slate-400 hover:text-white hover:bg-white/[0.08] cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Quick Shortcuts */}
        {shortcuts.length > 0 && (
          <div className="px-5 py-3 border-b border-white/[0.08] bg-[#0d1017] flex flex-wrap items-center gap-2">
            <span className="text-xs text-slate-500 mr-1">Quick Locations:</span>
            {shortcuts.map(item => (
              <button
                key={item.path}
                type="button"
                onClick={() => loadDir(item.path)}
                className="px-2.5 py-1 rounded-md text-xs font-medium bg-white/[0.05] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] transition-colors cursor-pointer"
              >
                {item.label}
              </button>
            ))}
          </div>
        )}

        {/* Current Path Bar */}
        <div className="px-5 py-3 border-b border-white/[0.08] flex items-center gap-2 bg-[#090b10]">
          <button
            type="button"
            disabled={!parentDir || loading}
            onClick={() => parentDir && loadDir(parentDir)}
            aria-label="Go to parent directory"
            className="p-2 rounded-lg bg-white/[0.05] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] disabled:opacity-35 disabled:cursor-not-allowed cursor-pointer"
          >
            <ArrowUp className="w-4 h-4" />
          </button>
          <div className="flex-1 px-3 py-2 rounded-lg bg-[#111520] border border-white/[0.08] font-mono text-xs text-slate-200 truncate">
            {currentDir}
          </div>
        </div>

        {/* Folder List */}
        <div className="flex-1 overflow-y-auto p-3 min-h-[240px]">
          {error ? (
            <div className="p-4 rounded-lg bg-rose-500/10 border border-rose-500/20 text-xs text-rose-300 flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{error}</span>
            </div>
          ) : loading ? (
            <div className="space-y-2 p-2">
              {[1, 2, 3, 4].map(n => (
                <div key={n} className="h-10 rounded-lg bg-white/[0.04] animate-pulse" />
              ))}
            </div>
          ) : directories.length === 0 ? (
            <div className="py-12 text-center text-xs text-slate-500">
              No subdirectories inside this folder. Click &ldquo;Use This Folder&rdquo; to select it.
            </div>
          ) : (
            <ul className="space-y-1">
              {directories.map(dir => (
                <li key={dir.path}>
                  <button
                    type="button"
                    onClick={() => loadDir(dir.path)}
                    className="w-full px-3 py-2.5 rounded-lg hover:bg-white/[0.05] flex items-center justify-between gap-3 text-left transition-colors cursor-pointer"
                  >
                    <span className="flex items-center gap-2.5 min-w-0">
                      <Folder className={`w-4 h-4 shrink-0 ${dir.hasDayFolders ? 'text-sky-400' : 'text-slate-400'}`} />
                      <span className="text-sm text-slate-200 truncate">{dir.name}</span>
                    </span>
                    <span className="text-xs text-slate-400 shrink-0 font-mono tabular-nums">
                      {dir.hasDayFolders ? (
                        <span className="inline-flex items-center gap-1 text-sky-400">
                          <Film className="w-3.5 h-3.5" />
                          Wyze footage
                        </span>
                      ) : dir.mp4Count > 0 ? (
                        `${dir.mp4Count} mp4`
                      ) : (
                        ''
                      )}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="px-5 py-3.5 border-t border-white/[0.08] bg-[#0d1017] flex items-center justify-between gap-3">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-lg text-sm font-medium bg-white/[0.05] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] cursor-pointer"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => onSelect(currentDir)}
            className="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 cursor-pointer"
          >
            <Check className="w-4 h-4" />
            <span>Use This Folder</span>
          </button>
        </div>
      </div>
    </div>
  );
}
