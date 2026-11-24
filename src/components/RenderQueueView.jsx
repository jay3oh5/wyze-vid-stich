import { useState } from 'react';
import {
  Play,
  FolderOpen,
  XCircle,
  CheckCircle2,
  Clock,
  RefreshCw,
  Trash2,
  Terminal,
  ChevronDown,
  ChevronUp,
  AlertTriangle
} from 'lucide-react';
import { formatDateDisplay, formatHour12, formatBytes } from '../utils/footage';

export function RenderQueueView({
  status,
  stitching,
  onPlayOutput,
  onOpenFolder,
  onCancelJob,
  onClearHistory,
  onGoToLibrary
}) {
  const [expandedLogJobId, setExpandedLogJobId] = useState(null);
  const jobs = status?.jobs || [];

  const runningCount = jobs.filter(j => j.status === 'running' || j.status === 'pending').length;
  const completedCount = jobs.filter(j => j.status === 'completed').length;
  const failedCount = jobs.filter(j => j.status === 'failed').length;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[#f4f6fa] tracking-tight">Render Queue</h1>
          <p className="text-sm text-slate-400 mt-1 tabular-nums">
            {jobs.length === 0
              ? 'No compilation jobs submitted in this session.'
              : `${runningCount} active · ${completedCount} completed · ${failedCount} failed`}
          </p>
        </div>

        <div className="flex items-center gap-2">
          {jobs.length > 0 && (
            <button
              type="button"
              onClick={onClearHistory}
              disabled={stitching}
              className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-lg text-xs font-medium bg-white/[0.04] border border-white/[0.08] text-slate-200 hover:bg-white/[0.08] disabled:opacity-40 disabled:cursor-not-allowed transition-colors cursor-pointer"
            >
              <Trash2 className="w-3.5 h-3.5 text-slate-400" />
              <span>Clear Finished</span>
            </button>
          )}
        </div>
      </div>

      {jobs.length === 0 ? (
        <section className="bg-[#111520] border border-white/[0.08] rounded-xl p-12 text-center">
          <h2 className="text-base font-semibold text-[#f4f6fa]">Your render queue is empty</h2>
          <p className="text-sm text-slate-400 mt-1.5 max-w-md mx-auto">
            Select one or more recorded hours from the Footage Library and click Stitch Selected to compile lossless hourly MP4 files.
          </p>
          <button
            type="button"
            onClick={onGoToLibrary}
            className="mt-5 px-4 py-2 rounded-lg text-sm font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 transition-colors cursor-pointer"
          >
            Browse Footage Library
          </button>
        </section>
      ) : (
        <section className="bg-[#111520] border border-white/[0.08] rounded-xl divide-y divide-white/[0.08] overflow-hidden">
          {jobs.map(job => {
            const isRunning = job.status === 'running';
            const isPending = job.status === 'pending';
            const isCompleted = job.status === 'completed';
            const isFailed = job.status === 'failed';
            const progress = job.totalClips > 0
              ? Math.round(((job.currentClipIndex || 0) / job.totalClips) * 100)
              : 0;
            const isLogOpen = expandedLogJobId === job.id;

            return (
              <div key={job.id} className="p-5 space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-4">
                  <div className="min-w-0 space-y-1">
                    <div className="flex flex-wrap items-center gap-2.5">
                      {isRunning && (
                        <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-sky-400">
                          <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                          Compiling
                        </span>
                      )}
                      {isPending && (
                        <span className="inline-flex items-center gap-1.5 text-xs font-medium text-slate-400">
                          <Clock className="w-3.5 h-3.5" />
                          Queued
                        </span>
                      )}
                      {isCompleted && (
                        <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-emerald-400">
                          <CheckCircle2 className="w-3.5 h-3.5" />
                          Completed
                        </span>
                      )}
                      {isFailed && (
                        <span className="inline-flex items-center gap-1.5 text-xs font-semibold text-rose-400">
                          <XCircle className="w-3.5 h-3.5" />
                          Failed
                        </span>
                      )}

                      <span className="text-slate-600" aria-hidden="true">·</span>
                      <span className="text-sm font-semibold text-[#f4f6fa]">
                        {formatDateDisplay(job.day)} · {formatHour12(job.hour)}
                      </span>
                    </div>

                    <div className="flex flex-wrap items-center gap-2 text-xs text-slate-400 font-mono tabular-nums">
                      <span>{job.totalClips || 0} clips</span>
                      {isCompleted && job.fileSize > 0 && (
                        <>
                          <span aria-hidden="true">·</span>
                          <span>{formatBytes(job.fileSize)}</span>
                        </>
                      )}
                      {isCompleted && job.durationMs > 0 && (
                        <>
                          <span aria-hidden="true">·</span>
                          <span>{(job.durationMs / 1000).toFixed(1)}s</span>
                        </>
                      )}
                      {job.outputPath && (
                        <>
                          <span aria-hidden="true">·</span>
                          <span className="truncate max-w-sm" title={job.outputPath}>
                            {job.outputPath}
                          </span>
                        </>
                      )}
                    </div>
                  </div>

                  {/* Row Actions */}
                  <div className="flex flex-wrap items-center gap-2 shrink-0">
                    {(isRunning || isPending) && (
                      <button
                        type="button"
                        onClick={() => onCancelJob(job.id)}
                        className="px-3 py-1.5 rounded-lg text-xs font-medium bg-rose-500/12 border border-rose-500/30 text-rose-300 hover:bg-rose-500/20 transition-colors cursor-pointer"
                      >
                        {isRunning ? 'Cancel' : 'Remove'}
                      </button>
                    )}

                    {isCompleted && job.outputPath && (
                      <>
                        <button
                          type="button"
                          onClick={() =>
                            onPlayOutput({
                              path: job.outputPath,
                              title: `${formatDateDisplay(job.day)} · ${formatHour12(job.hour)}`,
                              sizeBytes: job.fileSize
                            })
                          }
                          className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg text-xs font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 transition-colors cursor-pointer"
                        >
                          <Play className="w-3.5 h-3.5 fill-current" />
                          <span>Play</span>
                        </button>
                        <button
                          type="button"
                          onClick={() =>
                            onOpenFolder(
                              job.useSameFolder ? `${job.sourceDir}/${job.day}` : job.outputDir
                            )
                          }
                          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.04] border border-white/[0.08] text-slate-200 hover:bg-white/[0.08] transition-colors cursor-pointer"
                        >
                          <FolderOpen className="w-3.5 h-3.5 text-slate-400" />
                          <span>Reveal</span>
                        </button>
                      </>
                    )}

                    <button
                      type="button"
                      onClick={() => setExpandedLogJobId(isLogOpen ? null : job.id)}
                      aria-expanded={isLogOpen}
                      className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-medium bg-white/[0.03] border border-white/[0.08] text-slate-400 hover:text-slate-200 hover:bg-white/[0.07] transition-colors cursor-pointer"
                    >
                      <Terminal className="w-3.5 h-3.5" />
                      <span>Logs</span>
                      {isLogOpen ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                </div>

                {/* Progress Bar for active job */}
                {isRunning && (
                  <div className="space-y-1.5">
                    <div className="flex items-center justify-between text-xs text-slate-400 font-mono tabular-nums">
                      <span>
                        {job.currentClipName
                          ? `Appending ${job.currentClipName} (${job.currentClipIndex || 0}/${job.totalClips})`
                          : 'Preparing FFmpeg stream copy...'}
                      </span>
                      <span>{progress}%</span>
                    </div>
                    <div className="h-1.5 w-full bg-white/[0.06] rounded-full overflow-hidden">
                      <div
                        className="h-full bg-sky-400 rounded-full transition-all duration-200"
                        style={{ width: `${progress}%` }}
                      />
                    </div>
                  </div>
                )}

                {isFailed && job.error && (
                  <div className="flex items-start gap-2 p-3 rounded-lg bg-rose-500/10 border border-rose-500/20 text-xs text-rose-300">
                    <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
                    <span>{job.error}</span>
                  </div>
                )}

                {isLogOpen && (
                  <div className="rounded-lg bg-[#07090e] border border-white/[0.08] p-3 max-h-52 overflow-y-auto font-mono text-xs text-slate-300 space-y-1">
                    {(job.logs || []).map((line, i) => (
                      <div
                        key={i}
                        className={
                          line.includes('ERROR:')
                            ? 'text-rose-400'
                            : line.includes('Successfully')
                              ? 'text-emerald-400'
                              : 'text-slate-400'
                        }
                      >
                        {line}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </section>
      )}
    </div>
  );
}
