import { FolderOpen, RefreshCw, AlertTriangle } from 'lucide-react';

export function SettingsView({
  sourceDir,
  onChangeSourceDir,
  useSameFolder,
  onChangeUseSameFolder,
  customOutputDir,
  onChangeCustomOutputDir,
  overwrite,
  onChangeOverwrite,
  autoOpenFolder,
  onChangeAutoOpenFolder,
  sendNotification,
  onChangeSendNotification,
  deleteAfterCompile,
  onChangeDeleteAfterCompile,
  onBrowseSource,
  onBrowseOutput,
  onScan,
  scanning,
  stitching
}) {
  return (
    <div className="max-w-3xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#f4f6fa] tracking-tight">Settings & Paths</h1>
        <p className="text-sm text-slate-400 mt-1">
          Configure where Wyze recordings are read from and how compiled hourly videos are written.
        </p>
      </div>

      {/* Directories Section */}
      <section className="bg-[#111520] border border-white/[0.08] rounded-xl p-6 space-y-5">
        <div>
          <h2 className="text-base font-semibold text-[#f4f6fa]">Directories</h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Point to your Wyze microSD card record folder containing YYYYMMDD date folders.
          </p>
        </div>

        <div className="space-y-2">
          <label htmlFor="settings-source-dir" className="block text-xs font-medium text-slate-300">
            Wyze Record Folder (Source)
          </label>
          <div className="flex flex-col sm:flex-row gap-2.5">
            <input
              id="settings-source-dir"
              type="text"
              value={sourceDir}
              onChange={(e) => onChangeSourceDir(e.target.value)}
              placeholder="./mock_record or /Volumes/SD_CARD/record"
              className="flex-1 px-3.5 py-2.5 rounded-lg bg-[#090b10] border border-white/[0.1] text-sm font-mono text-slate-100 placeholder:text-slate-600 focus:outline-none focus:border-sky-400"
            />
            <button
              type="button"
              onClick={onBrowseSource}
              disabled={scanning || stitching}
              className="inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium bg-white/[0.06] border border-white/[0.1] text-slate-200 hover:bg-white/[0.1] disabled:opacity-40 whitespace-nowrap cursor-pointer"
            >
              <FolderOpen className="w-4 h-4 text-sky-400" />
              <span>Browse</span>
            </button>
            <button
              type="button"
              onClick={onScan}
              disabled={scanning || stitching}
              className="inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-sm font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 disabled:opacity-40 whitespace-nowrap cursor-pointer"
            >
              <RefreshCw className={`w-4 h-4 ${scanning ? 'animate-spin' : ''}`} />
              <span>{scanning ? 'Scanning...' : 'Scan Now'}</span>
            </button>
          </div>
        </div>

        <div className="pt-4 border-t border-white/[0.08] space-y-4">
          <label className="flex items-start gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={useSameFolder}
              onChange={(e) => onChangeUseSameFolder(e.target.checked)}
              className="mt-0.5 w-4 h-4 rounded accent-sky-500 cursor-pointer"
            />
            <div>
              <span className="text-sm font-medium text-slate-200 block">
                Save compiled videos inside each original day folder
              </span>
              <span className="text-xs text-slate-400 block mt-0.5 font-mono">
                Example: {sourceDir}/20260529/2026-05-29_1AM.mp4
              </span>
            </div>
          </label>

          {!useSameFolder && (
            <div className="space-y-2 pl-7">
              <label htmlFor="settings-output-dir" className="block text-xs font-medium text-slate-300">
                Custom Destination Directory
              </label>
              <div className="flex flex-col sm:flex-row gap-2.5">
                <input
                  id="settings-output-dir"
                  type="text"
                  value={customOutputDir}
                  onChange={(e) => onChangeCustomOutputDir(e.target.value)}
                  placeholder="./stitched_output"
                  className="flex-1 px-3.5 py-2.5 rounded-lg bg-[#090b10] border border-white/[0.1] text-sm font-mono text-slate-100 placeholder:text-slate-600 focus:outline-none focus:border-sky-400"
                />
                <button
                  type="button"
                  onClick={onBrowseOutput}
                  disabled={stitching}
                  className="inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-sm font-medium bg-white/[0.06] border border-white/[0.1] text-slate-200 hover:bg-white/[0.1] disabled:opacity-40 whitespace-nowrap cursor-pointer"
                >
                  <FolderOpen className="w-4 h-4 text-sky-400" />
                  <span>Browse</span>
                </button>
              </div>
            </div>
          )}
        </div>
      </section>

      {/* Compilation & Automation Options */}
      <section className="bg-[#111520] border border-white/[0.08] rounded-xl p-6 space-y-4">
        <div>
          <h2 className="text-base font-semibold text-[#f4f6fa]">Compilation Behavior</h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Video streams are copied losslessly without re-encoding; audio is normalized to AAC for universal playback.
          </p>
        </div>

        <div className="divide-y divide-white/[0.06]">
          <label className="flex items-start gap-3 py-3.5 cursor-pointer">
            <input
              type="checkbox"
              checked={overwrite}
              onChange={(e) => onChangeOverwrite(e.target.checked)}
              className="mt-0.5 w-4 h-4 rounded accent-sky-500 cursor-pointer"
            />
            <div>
              <span className="text-sm font-medium text-slate-200 block">
                Overwrite existing compiled files
              </span>
              <span className="text-xs text-slate-400 block mt-0.5">
                When off, hours that already have a compiled MP4 are skipped automatically.
              </span>
            </div>
          </label>

          <label className="flex items-start gap-3 py-3.5 cursor-pointer">
            <input
              type="checkbox"
              checked={autoOpenFolder}
              onChange={(e) => onChangeAutoOpenFolder(e.target.checked)}
              className="mt-0.5 w-4 h-4 rounded accent-sky-500 cursor-pointer"
            />
            <div>
              <span className="text-sm font-medium text-slate-200 block">
                Auto-open output folder on completion
              </span>
              <span className="text-xs text-slate-400 block mt-0.5">
                Opens the destination folder in Finder on macOS after each successful job.
              </span>
            </div>
          </label>

          <label className="flex items-start gap-3 py-3.5 cursor-pointer">
            <input
              type="checkbox"
              checked={sendNotification}
              onChange={(e) => onChangeSendNotification(e.target.checked)}
              className="mt-0.5 w-4 h-4 rounded accent-sky-500 cursor-pointer"
            />
            <div>
              <span className="text-sm font-medium text-slate-200 block">
                Send desktop notification when jobs finish
              </span>
              <span className="text-xs text-slate-400 block mt-0.5">
                Alerts you when a batch compilation completes or encounters an error.
              </span>
            </div>
          </label>

          <label className="flex items-start gap-3 pt-4 cursor-pointer">
            <input
              type="checkbox"
              checked={deleteAfterCompile}
              onChange={(e) => onChangeDeleteAfterCompile(e.target.checked)}
              className="mt-0.5 w-4 h-4 rounded accent-rose-500 cursor-pointer"
            />
            <div>
              <span className="text-sm font-medium text-rose-300 inline-flex items-center gap-1.5">
                <AlertTriangle className="w-4 h-4" />
                Delete 1-minute source clips after successful compile
              </span>
              <span className="text-xs text-slate-400 block mt-0.5">
                Permanently removes original minute clips once FFmpeg succeeds. You will always be asked to confirm before starting.
              </span>
            </div>
          </label>
        </div>
      </section>
    </div>
  );
}
