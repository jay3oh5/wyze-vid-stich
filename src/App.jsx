import { useState, useEffect, useRef, useCallback } from 'react';
import { AlertCircle, CheckCircle2, RefreshCw, Play, FolderOpen, X } from 'lucide-react';
import { TopBar } from './components/TopBar';
import { Sidebar } from './components/Sidebar';
import { CinemaPreviewStage } from './components/CinemaPreviewStage';
import { Timeline24h } from './components/Timeline24h';
import { HourPreviewGrid } from './components/HourPreviewGrid';
import { TheaterModal } from './components/TheaterModal';
import { ClipInspectorModal } from './components/ClipInspectorModal';
import { RenderQueueView } from './components/RenderQueueView';
import { SettingsView } from './components/SettingsView';
import { FolderBrowserModal } from './components/FolderBrowserModal';
import { ConfirmDialog } from './components/ConfirmDialog';
import {
  formatDateDisplay,
  formatHour12,
  formatBytes,
  getDaySummary,
  formatOutputLabel
} from './utils/footage';

function App() {
  // Persistent Settings
  const [sourceDir, setSourceDir] = useState(() => localStorage.getItem('wyze_sourceDir') || './mock_record');
  const [useSameFolder, setUseSameFolder] = useState(() => {
    const val = localStorage.getItem('wyze_useSameFolder');
    return val === null ? false : val === 'true';
  });
  const [customOutputDir, setCustomOutputDir] = useState(
    () => localStorage.getItem('wyze_customOutputDir') || './stitched_output'
  );
  const [overwrite, setOverwrite] = useState(() => localStorage.getItem('wyze_overwrite') === 'true');
  const [deleteAfterCompile, setDeleteAfterCompile] = useState(
    () => localStorage.getItem('wyze_deleteAfterCompile') === 'true'
  );
  const [autoOpenFolder, setAutoOpenFolder] = useState(
    () => localStorage.getItem('wyze_autoOpenFolder') === 'true'
  );
  const [sendNotification, setSendNotification] = useState(
    () => localStorage.getItem('wyze_sendNotification') === 'true'
  );

  // Navigation & UI state
  const [activeTab, setActiveTab] = useState('library');
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [toast, setToast] = useState(null);

  // Scanned library state
  const [days, setDays] = useState([]);
  const [selectedDay, setSelectedDay] = useState(null);
  const [stitchedOutputs, setStitchedOutputs] = useState([]);
  const [scanning, setScanning] = useState(true);
  const [scanError, setScanError] = useState('');
  const [selectedHours, setSelectedHours] = useState(new Set());

  // Large Cinema Preview Stage & Theater Modal state
  const [previewState, setPreviewState] = useState(null);
  const [theaterOpen, setTheaterOpen] = useState(false);

  // Modals state
  const [inspectTarget, setInspectTarget] = useState(null); // { day, hourObj }
  const [folderBrowserTarget, setFolderBrowserTarget] = useState(null); // 'source' | 'output' | null
  const [confirmState, setConfirmState] = useState(null);

  // Stitching queue state
  const [stitching, setStitching] = useState(false);
  const [status, setStatus] = useState({
    running: false,
    jobs: [],
    total: 0,
    current: 0,
    currentItem: '',
    logs: [],
    errors: []
  });

  const pollIntervalRef = useRef(null);
  const prevRunningJobsRef = useRef(new Set());

  const showToast = useCallback((type, message) => {
    setToast({ type, message });
  }, []);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 4500);
    return () => clearTimeout(t);
  }, [toast]);

  // Persist settings
  useEffect(() => {
    localStorage.setItem('wyze_sourceDir', sourceDir);
    localStorage.setItem('wyze_useSameFolder', useSameFolder.toString());
    localStorage.setItem('wyze_customOutputDir', customOutputDir);
    localStorage.setItem('wyze_overwrite', overwrite.toString());
    localStorage.setItem('wyze_deleteAfterCompile', deleteAfterCompile.toString());
    localStorage.setItem('wyze_autoOpenFolder', autoOpenFolder.toString());
    localStorage.setItem('wyze_sendNotification', sendNotification.toString());
  }, [
    sourceDir,
    useSameFolder,
    customOutputDir,
    overwrite,
    deleteAfterCompile,
    autoOpenFolder,
    sendNotification
  ]);

  useEffect(() => {
    if (sendNotification && typeof Notification !== 'undefined' && Notification.permission === 'default') {
      Notification.requestPermission();
    }
  }, [sendNotification]);

  const handleOpenFolder = useCallback(async (folderPath) => {
    try {
      const res = await fetch('/api/open-folder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: folderPath })
      });
      const data = await res.json();
      if (res.ok && data.resolvedPath) {
        showToast('info', `Output directory: ${data.resolvedPath}`);
      }
    } catch (err) {
      console.error('Failed to open folder:', err);
    }
  }, [showToast]);

  const refreshOutputs = useCallback(async (src = sourceDir, out = customOutputDir) => {
    try {
      const res = await fetch(
        `/api/outputs?sourceDir=${encodeURIComponent(src)}&outputDir=${encodeURIComponent(out)}`
      );
      if (res.ok) {
        const data = await res.json();
        setStitchedOutputs(data.outputs || []);
      }
    } catch (err) {
      console.error('Failed to load outputs:', err);
    }
  }, [sourceDir, customOutputDir]);

  const handleScan = useCallback(async (overrideSourceDir) => {
    const dirToScan = typeof overrideSourceDir === 'string' ? overrideSourceDir : sourceDir;
    setScanning(true);
    setScanError('');

    try {
      const response = await fetch('/api/scan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sourceDir: dirToScan,
          outputDir: useSameFolder ? '' : customOutputDir
        })
      });

      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error || 'Failed to scan directory');
      }

      const scannedDays = data.days || [];
      setDays(scannedDays);
      setStitchedOutputs(data.stitchedOutputs || []);
      setSelectedHours(new Set());

      if (scannedDays.length > 0) {
        const firstDay = scannedDays[0];
        setSelectedDay(firstDay.day);
        const firstHourWithClips = firstDay.hours.find(h => h.clips && h.clips.length > 0);
        if (firstHourWithClips) {
          const initialClip = firstHourWithClips.clips[0];
          const clipPath =
            firstHourWithClips.clipDetails?.[initialClip]?.path ||
            `${firstHourWithClips.hourDirPath}/${initialClip}`;
          setPreviewState({
            mode: 'hour',
            day: firstDay.day,
            hourObj: firstHourWithClips,
            clipFilename: initialClip,
            videoPath: clipPath,
            autoPlay: false
          });
        }
      } else {
        setSelectedDay(null);
      }
    } catch (err) {
      setScanError(err.message);
      setDays([]);
      setSelectedDay(null);
    } finally {
      setScanning(false);
    }
  }, [sourceDir, useSameFolder, customOutputDir]);

  const fetchStatus = useCallback(async () => {
    try {
      const response = await fetch('/api/status');
      if (!response.ok) throw new Error('Failed to query status');
      const data = await response.json();
      setStatus(data);

      if (data.jobs && Array.isArray(data.jobs)) {
        const runningJobs = data.jobs.filter(j => j.status === 'running' || j.status === 'pending');

        data.jobs.forEach(job => {
          if (
            prevRunningJobsRef.current.has(job.id) &&
            job.status !== 'running' &&
            job.status !== 'pending'
          ) {
            if (job.status === 'completed') {
              showToast(
                'success',
                `Compiled ${formatDateDisplay(job.day)} · ${formatHour12(job.hour)} successfully.`
              );
              refreshOutputs();
              if (
                sendNotification &&
                typeof Notification !== 'undefined' &&
                Notification.permission === 'granted'
              ) {
                new Notification('Stitch Complete', {
                  body: `Successfully compiled ${formatHour12(job.hour)} footage for ${job.day}.`
                });
              }
              if (autoOpenFolder) {
                const folderToOpen = job.useSameFolder
                  ? `${job.sourceDir}/${job.day}`
                  : job.outputDir;
                handleOpenFolder(folderToOpen);
              }
            } else if (job.status === 'failed') {
              showToast('error', `Compilation failed for ${formatHour12(job.hour)}: ${job.error || 'Unknown error'}`);
            }
          }
        });

        prevRunningJobsRef.current = new Set(runningJobs.map(j => j.id));
      }

      if (!data.running) {
        setStitching(false);
      }
    } catch (err) {
      console.error('Error fetching stitching status:', err);
    }
  }, [autoOpenFolder, handleOpenFolder, refreshOutputs, sendNotification, showToast]);

  // Initial auto-scan & status sync on mount
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const response = await fetch('/api/scan', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            sourceDir,
            outputDir: useSameFolder ? '' : customOutputDir
          })
        });
        const data = await response.json();
        if (cancelled) return;
        if (!response.ok) {
          setScanError(data.error || 'Failed to scan directory');
        } else {
          const scannedDays = data.days || [];
          setDays(scannedDays);
          setStitchedOutputs(data.stitchedOutputs || []);
          if (scannedDays.length > 0) {
            const firstDay = scannedDays[0];
            setSelectedDay(firstDay.day);
            const firstHourWithClips = firstDay.hours.find(h => h.clips && h.clips.length > 0);
            if (firstHourWithClips) {
              const initialClip = firstHourWithClips.clips[0];
              const clipPath =
                firstHourWithClips.clipDetails?.[initialClip]?.path ||
                `${firstHourWithClips.hourDirPath}/${initialClip}`;
              setPreviewState({
                mode: 'hour',
                day: firstDay.day,
                hourObj: firstHourWithClips,
                clipFilename: initialClip,
                videoPath: clipPath,
                autoPlay: false
              });
            }
          }
        }
      } catch (err) {
        if (!cancelled) setScanError(err.message);
      } finally {
        if (!cancelled) setScanning(false);
      }

      if (!cancelled) {
        try {
          const statusRes = await fetch('/api/status');
          if (statusRes.ok && !cancelled) {
            const statusData = await statusRes.json();
            setStatus(statusData);
            if (statusData.running) setStitching(true);
          }
        } catch (err) {
          console.error('Initial status sync failed:', err);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Poll status while stitching
  useEffect(() => {
    if (stitching) {
      pollIntervalRef.current = setInterval(fetchStatus, 500);
    } else if (pollIntervalRef.current) {
      clearInterval(pollIntervalRef.current);
      pollIntervalRef.current = null;
    }
    return () => {
      if (pollIntervalRef.current) {
        clearInterval(pollIntervalRef.current);
      }
    };
  }, [stitching, fetchStatus]);

  // Selection helpers
  const toggleHour = (day, hour) => {
    const key = `${day}_${hour}`;
    setSelectedHours(prev => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const handleSelectAllDay = (dayObj) => {
    setSelectedHours(prev => {
      const next = new Set(prev);
      dayObj.hours.forEach(h => next.add(`${dayObj.day}_${h.hour}`));
      return next;
    });
  };

  const handleSelectGapsDay = (dayObj) => {
    setSelectedHours(prev => {
      const next = new Set(prev);
      dayObj.hours.forEach(h => {
        if (h.missing.length > 0) next.add(`${dayObj.day}_${h.hour}`);
        else next.delete(`${dayObj.day}_${h.hour}`);
      });
      return next;
    });
  };

  const handleClearDaySelection = (dayObj) => {
    setSelectedHours(prev => {
      const next = new Set(prev);
      dayObj.hours.forEach(h => next.delete(`${dayObj.day}_${h.hour}`));
      return next;
    });
  };

  // Preview helpers
  const handleSelectMinuteClip = (day, hourObj, clipFilename, autoPlay = false) => {
    const clipPath =
      hourObj.clipDetails?.[clipFilename]?.path ||
      `${hourObj.hourDirPath}/${clipFilename}`;
    setPreviewState({
      mode: 'hour',
      day,
      hourObj,
      clipFilename,
      videoPath: clipPath,
      autoPlay
    });
    setActiveTab('library');
  };

  const handlePreviewHour = (day, hourObj, openTheaterImmediately = false) => {
    if (!hourObj?.clips?.length) return;
    const firstClip = hourObj.clips[0];
    handleSelectMinuteClip(day, hourObj, firstClip, openTheaterImmediately);
    if (openTheaterImmediately) {
      setTheaterOpen(true);
    }
  };

  const handlePlayStitchedOutput = (outputItem) => {
    setPreviewState({
      mode: 'compiled',
      title: outputItem.title || formatOutputLabel(outputItem.name),
      videoPath: outputItem.path,
      sizeBytes: outputItem.sizeBytes,
      autoPlay: true
    });
    setActiveTab('library');
  };

  // Submit stitching jobs
  const executeStitchRequest = async (hoursArray) => {
    const outputDirToUse = useSameFolder ? '' : (customOutputDir.trim() || './stitched_output');

    setStitching(true);
    setActiveTab('queue');

    try {
      const response = await fetch('/api/stitch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sourceDir,
          outputDir: outputDirToUse,
          hours: hoursArray,
          overwrite,
          useSameFolder,
          deleteAfterCompile
        })
      });

      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error || 'Failed to submit stitching jobs');
      }

      setSelectedHours(new Set());
      if (data.jobs) {
        data.jobs.forEach(j => prevRunningJobsRef.current.add(j.id));
      }
      fetchStatus();
    } catch (err) {
      setStitching(false);
      showToast('error', err.message);
    }
  };

  const handleStitchSelected = () => {
    if (selectedHours.size === 0 || stitching) return;
    const hoursArray = Array.from(selectedHours)
      .sort()
      .map(key => {
        const [day, hour] = key.split('_');
        return { day, hour };
      });

    if (deleteAfterCompile) {
      setConfirmState({
        title: 'Confirm Destructive Source Cleanup',
        message: `You are about to compile ${hoursArray.length} hour(s) and permanently delete the original 1-minute source clips afterward. Continue?`,
        confirmLabel: 'Compile & Delete Originals',
        destructive: true,
        onConfirm: () => {
          setConfirmState(null);
          executeStitchRequest(hoursArray);
        }
      });
      return;
    }

    executeStitchRequest(hoursArray);
  };

  const handleStitchCustomSelection = (day, hour, clips) => {
    if (!clips || clips.length === 0) return;
    setInspectTarget(null);

    const hoursArray = [{ day, hour, clips }];
    if (deleteAfterCompile) {
      setConfirmState({
        title: 'Confirm Destructive Source Cleanup',
        message: `This will stitch ${clips.length} selected clip(s) and permanently delete those source clips on completion. Continue?`,
        confirmLabel: 'Compile & Delete Originals',
        destructive: true,
        onConfirm: () => {
          setConfirmState(null);
          executeStitchRequest(hoursArray);
        }
      });
      return;
    }

    executeStitchRequest(hoursArray);
  };

  const handleCancelJob = async (id) => {
    try {
      const response = await fetch('/api/jobs/cancel', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id })
      });
      if (response.ok) {
        fetchStatus();
      }
    } catch (err) {
      console.error('Failed to cancel job:', err);
    }
  };

  const handleClearHistory = async () => {
    try {
      const response = await fetch('/api/jobs/clear', { method: 'POST' });
      if (response.ok) {
        fetchStatus();
      }
    } catch (err) {
      console.error('Failed to clear history:', err);
    }
  };

  const activeDayObj = days.find(d => d.day === selectedDay) || days[0] || null;
  const activeDaySummary = activeDayObj ? getDaySummary(activeDayObj) : null;
  const activeJobsCount = (status.jobs || []).filter(
    j => j.status === 'running' || j.status === 'pending'
  ).length;
  const activeRunningJob = (status.jobs || []).find(j => j.status === 'running');

  return (
    <div className="min-h-screen flex flex-col bg-[#090b10] text-[#f4f6fa]">
      <TopBar
        activeTab={activeTab}
        onSelectTab={setActiveTab}
        selectedCount={selectedHours.size}
        activeJobCount={activeJobsCount}
        stitching={stitching}
        scanning={scanning}
        hasDays={days.length > 0}
        onPrimaryAction={selectedHours.size > 0 ? handleStitchSelected : () => handleScan()}
        onToggleMobileMenu={() => setMobileMenuOpen(v => !v)}
      />

      {/* Compact Active Compile Strip when viewing Library/Settings */}
      {activeRunningJob && activeTab !== 'queue' && (
        <div className="bg-sky-500/10 border-b border-sky-400/20 px-4 lg:px-6 py-2 flex flex-wrap items-center justify-between gap-3 text-xs">
          <div className="flex items-center gap-2 text-sky-200 font-medium">
            <RefreshCw className="w-3.5 h-3.5 animate-spin text-sky-400" />
            <span>
              Compiling {formatDateDisplay(activeRunningJob.day)} · {formatHour12(activeRunningJob.hour)}
            </span>
            <span className="font-mono text-sky-300/80 tabular-nums">
              ({activeRunningJob.currentClipIndex || 0}/{activeRunningJob.totalClips || 0} clips)
            </span>
          </div>
          <button
            type="button"
            onClick={() => setActiveTab('queue')}
            className="text-sky-300 hover:text-white font-semibold underline underline-offset-2 cursor-pointer"
          >
            View Queue
          </button>
        </div>
      )}

      {/* Workspace Body */}
      <div className="flex-1 flex min-h-0">
        <Sidebar
          activeTab={activeTab}
          onSelectTab={setActiveTab}
          activeJobCount={activeJobsCount}
          sourceDir={sourceDir}
          days={days}
          selectedDay={activeDayObj?.day || null}
          onSelectDay={(dayStr) => {
            setSelectedDay(dayStr);
            setActiveTab('library');
            const dayObj = days.find(d => d.day === dayStr);
            const firstHour = dayObj?.hours?.find(h => h.clips?.length > 0);
            if (firstHour) {
              handlePreviewHour(dayStr, firstHour, false);
            }
          }}
          stitchedOutputs={stitchedOutputs}
          activePreviewPath={previewState?.videoPath || null}
          onPlayStitchedOutput={handlePlayStitchedOutput}
          onOpenBrowse={() => setFolderBrowserTarget('source')}
          onScan={() => handleScan()}
          scanning={scanning}
          mobileOpen={mobileMenuOpen}
          onCloseMobile={() => setMobileMenuOpen(false)}
        />

        <main className="flex-1 min-w-0 overflow-y-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="max-w-6xl mx-auto space-y-6">
            {/* Inline Toast Feedback */}
            {toast && (
              <div
                role="status"
                className={`px-4 py-3 rounded-xl border flex items-center justify-between gap-3 text-sm ${
                  toast.type === 'error'
                    ? 'bg-rose-500/10 border-rose-500/25 text-rose-200'
                    : toast.type === 'success'
                      ? 'bg-emerald-500/10 border-emerald-500/25 text-emerald-200'
                      : 'bg-sky-500/10 border-sky-500/25 text-sky-200'
                }`}
              >
                <div className="flex items-center gap-2.5">
                  {toast.type === 'error' ? (
                    <AlertCircle className="w-4 h-4 shrink-0" />
                  ) : (
                    <CheckCircle2 className="w-4 h-4 shrink-0" />
                  )}
                  <span>{toast.message}</span>
                </div>
                <button
                  type="button"
                  onClick={() => setToast(null)}
                  aria-label="Dismiss notification"
                  className="text-current/70 hover:text-current cursor-pointer"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
            )}

            {/* LIBRARY VIEW */}
            {activeTab === 'library' && (
              <>
                {scanError && (
                  <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/25 flex flex-wrap items-center justify-between gap-3">
                    <div className="flex items-center gap-2.5 text-sm text-rose-200">
                      <AlertCircle className="w-4 h-4 shrink-0" />
                      <span>{scanError}</span>
                    </div>
                    <button
                      type="button"
                      onClick={() => setFolderBrowserTarget('source')}
                      className="px-3 py-1.5 rounded-lg text-xs font-medium bg-white/[0.08] text-white hover:bg-white/[0.14] cursor-pointer"
                    >
                      Choose Another Folder
                    </button>
                  </div>
                )}

                {scanning && days.length === 0 ? (
                  <div className="space-y-6">
                    <div className="h-[380px] rounded-xl bg-[#111520] border border-white/[0.08] animate-pulse" />
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                      {[1, 2].map(n => (
                        <div key={n} className="h-64 rounded-xl bg-[#111520] border border-white/[0.08] animate-pulse" />
                      ))}
                    </div>
                  </div>
                ) : !activeDayObj ? (
                  <section className="bg-[#111520] border border-white/[0.08] rounded-xl p-12 text-center space-y-4">
                    <div className="w-12 h-12 rounded-xl bg-white/[0.05] border border-white/[0.08] flex items-center justify-center text-sky-400 mx-auto">
                      <FolderOpen className="w-6 h-6" />
                    </div>
                    <div>
                      <h1 className="text-xl font-bold text-white">No Wyze Footage Loaded</h1>
                      <p className="text-sm text-slate-400 mt-1.5 max-w-md mx-auto">
                        Select your Wyze microSD card record folder (containing YYYYMMDD subdirectories) to preview and stitch footage.
                      </p>
                    </div>
                    <div className="flex flex-wrap items-center justify-center gap-3 pt-2">
                      <button
                        type="button"
                        onClick={() => setFolderBrowserTarget('source')}
                        className="px-4 py-2 rounded-lg text-sm font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 cursor-pointer"
                      >
                        Browse Folders
                      </button>
                      <button
                        type="button"
                        onClick={() => handleScan()}
                        className="px-4 py-2 rounded-lg text-sm font-medium bg-white/[0.06] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] cursor-pointer"
                      >
                        Rescan Current Path
                      </button>
                    </div>
                  </section>
                ) : (
                  <>
                    {/* Day Header & Summary */}
                    <div className="flex flex-wrap items-end justify-between gap-4">
                      <div>
                        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-[#f4f6fa]">
                          {formatDateDisplay(activeDayObj.day, true)}
                        </h1>
                        {activeDaySummary && (
                          <div className="mt-1.5 flex flex-wrap items-center gap-2 text-sm text-slate-400 tabular-nums">
                            <span>{activeDaySummary.totalHours} recorded hours</span>
                            <span aria-hidden="true">·</span>
                            <span>{activeDaySummary.totalClips} clips</span>
                            <span aria-hidden="true">·</span>
                            <span>{activeDaySummary.coveragePct}% continuity</span>
                            <span aria-hidden="true">·</span>
                            <span className="font-mono">{formatBytes(activeDaySummary.totalSizeBytes)}</span>
                          </div>
                        )}
                      </div>

                      {selectedHours.size > 0 && (
                        <div className="flex items-center gap-3">
                          <span className="text-xs text-slate-400 tabular-nums">
                            {selectedHours.size} hour{selectedHours.size === 1 ? '' : 's'} ready to stitch
                          </span>
                          <button
                            type="button"
                            onClick={handleStitchSelected}
                            disabled={stitching}
                            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold bg-sky-500 text-slate-950 hover:bg-sky-400 disabled:opacity-40 transition-colors cursor-pointer"
                          >
                            <Play className="w-4 h-4 fill-current" />
                            <span>Stitch Selected</span>
                          </button>
                        </div>
                      )}
                    </div>

                    {/* Dominant Focal Anchor: Large Cinema Preview Stage */}
                    <CinemaPreviewStage
                      previewState={previewState}
                      onSelectMinuteClip={handleSelectMinuteClip}
                      onOpenTheater={() => setTheaterOpen(true)}
                      onOpenInspector={(day, hourObj) => setInspectTarget({ day, hourObj })}
                      isHourSelected={
                        previewState?.mode === 'hour' && previewState?.hourObj
                          ? selectedHours.has(`${previewState.day}_${previewState.hourObj.hour}`)
                          : false
                      }
                      onToggleSelectHour={toggleHour}
                    />

                    {/* 24-Hour Coverage Timeline */}
                    <Timeline24h
                      dayObj={activeDayObj}
                      activeHour={previewState?.mode === 'hour' ? previewState?.hourObj?.hour : null}
                      selectedHours={selectedHours}
                      onPreviewHour={(day, hourObj) => handlePreviewHour(day, hourObj, false)}
                      onToggleSelectHour={toggleHour}
                    />

                    {/* Large Visual Hour Preview Grid */}
                    <HourPreviewGrid
                      dayObj={activeDayObj}
                      selectedHours={selectedHours}
                      activePreviewHour={previewState?.mode === 'hour' ? previewState?.hourObj?.hour : null}
                      onToggleSelectHour={toggleHour}
                      onSelectAllDay={handleSelectAllDay}
                      onSelectGapsDay={handleSelectGapsDay}
                      onClearDaySelection={handleClearDaySelection}
                      onPreviewHour={(day, hourObj) => handlePreviewHour(day, hourObj, false)}
                      onOpenTheaterForHour={(day, hourObj) => handlePreviewHour(day, hourObj, true)}
                      onOpenInspector={(day, hourObj) => setInspectTarget({ day, hourObj })}
                    />
                  </>
                )}
              </>
            )}

            {/* RENDER QUEUE VIEW */}
            {activeTab === 'queue' && (
              <RenderQueueView
                status={status}
                stitching={stitching}
                onPlayOutput={handlePlayStitchedOutput}
                onOpenFolder={handleOpenFolder}
                onCancelJob={handleCancelJob}
                onClearHistory={handleClearHistory}
                onGoToLibrary={() => setActiveTab('library')}
              />
            )}

            {/* SETTINGS VIEW */}
            {activeTab === 'settings' && (
              <SettingsView
                sourceDir={sourceDir}
                onChangeSourceDir={setSourceDir}
                useSameFolder={useSameFolder}
                onChangeUseSameFolder={setUseSameFolder}
                customOutputDir={customOutputDir}
                onChangeCustomOutputDir={setCustomOutputDir}
                overwrite={overwrite}
                onChangeOverwrite={setOverwrite}
                autoOpenFolder={autoOpenFolder}
                onChangeAutoOpenFolder={setAutoOpenFolder}
                sendNotification={sendNotification}
                onChangeSendNotification={setSendNotification}
                deleteAfterCompile={deleteAfterCompile}
                onChangeDeleteAfterCompile={setDeleteAfterCompile}
                onBrowseSource={() => setFolderBrowserTarget('source')}
                onBrowseOutput={() => setFolderBrowserTarget('output')}
                onScan={() => {
                  handleScan();
                  setActiveTab('library');
                }}
                scanning={scanning}
                stitching={stitching}
              />
            )}
          </div>
        </main>
      </div>

      {/* Theater Lightbox Modal */}
      {theaterOpen && previewState && (
        <TheaterModal
          previewState={previewState}
          onClose={() => setTheaterOpen(false)}
          onSelectMinuteClip={handleSelectMinuteClip}
        />
      )}

      {/* Split-Pane Clip Inspector Modal */}
      {inspectTarget && (
        <ClipInspectorModal
          day={inspectTarget.day}
          hourObj={inspectTarget.hourObj}
          stitching={stitching}
          onClose={() => setInspectTarget(null)}
          onStitchCustom={handleStitchCustomSelection}
        />
      )}

      {/* Cross-Platform Directory Picker Modal */}
      {folderBrowserTarget && (
        <FolderBrowserModal
          title={
            folderBrowserTarget === 'source'
              ? 'Select Wyze Record Source Folder'
              : 'Select Destination Folder'
          }
          initialDir={folderBrowserTarget === 'source' ? sourceDir : (customOutputDir || '.')}
          onClose={() => setFolderBrowserTarget(null)}
          onSelect={(chosenPath) => {
            if (folderBrowserTarget === 'source') {
              setSourceDir(chosenPath);
              setFolderBrowserTarget(null);
              handleScan(chosenPath);
              setActiveTab('library');
            } else {
              setCustomOutputDir(chosenPath);
              setFolderBrowserTarget(null);
              refreshOutputs(sourceDir, chosenPath);
            }
          }}
        />
      )}

      {/* Destructive Action Confirmation Dialog */}
      {confirmState && (
        <ConfirmDialog
          title={confirmState.title}
          message={confirmState.message}
          confirmLabel={confirmState.confirmLabel}
          destructive={confirmState.destructive}
          onConfirm={confirmState.onConfirm}
          onCancel={() => setConfirmState(null)}
        />
      )}
    </div>
  );
}

export default App;
