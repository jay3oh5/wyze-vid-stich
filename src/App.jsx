import { useState, useEffect, useRef } from 'react';
import { 
  Video, 
  FolderOpen, 
  Play, 
  Check, 
  AlertTriangle, 
  AlertCircle, 
  ChevronRight, 
  RefreshCw, 
  Layers,
  Sparkles
} from 'lucide-react';

function App() {
  // Load initial states from LocalStorage or fall back to default settings
  const [sourceDir, setSourceDir] = useState(() => {
    return localStorage.getItem('wyze_sourceDir') || './mock_record';
  });
  const [useSameFolder, setUseSameFolder] = useState(() => {
    const val = localStorage.getItem('wyze_useSameFolder');
    return val === null ? true : val === 'true';
  });
  const [customOutputDir, setCustomOutputDir] = useState(() => {
    return localStorage.getItem('wyze_customOutputDir') || '';
  });
  const [overwrite, setOverwrite] = useState(() => {
    const val = localStorage.getItem('wyze_overwrite');
    return val === 'true';
  });
  const [deleteAfterCompile, setDeleteAfterCompile] = useState(() => {
    return localStorage.getItem('wyze_deleteAfterCompile') === 'true';
  });
  const [autoOpenFolder, setAutoOpenFolder] = useState(() => {
    return localStorage.getItem('wyze_autoOpenFolder') === 'true';
  });
  const [sendNotification, setSendNotification] = useState(() => {
    return localStorage.getItem('wyze_sendNotification') === 'true';
  });

  const [days, setDays] = useState([]);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState('');
  
  const [expandedDays, setExpandedDays] = useState(new Set());
  const [selectedHours, setSelectedHours] = useState(new Set());
  
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

  // Video player state
  const [activeVideoPath, setActiveVideoPath] = useState(null);
  const [activeVideoTitle, setActiveVideoTitle] = useState('');

  // Inspector state
  const [inspectingDay, setInspectingDay] = useState(null);
  const [inspectingHour, setInspectingHour] = useState(null);
  const [inspectorClips, setInspectorClips] = useState(new Set());

  const pollIntervalRef = useRef(null);
  const consoleEndRef = useRef(null);
  const prevRunningJobsRef = useRef(new Set());

  // Sync settings changes to LocalStorage
  useEffect(() => {
    localStorage.setItem('wyze_sourceDir', sourceDir);
    localStorage.setItem('wyze_useSameFolder', useSameFolder.toString());
    localStorage.setItem('wyze_customOutputDir', customOutputDir);
    localStorage.setItem('wyze_overwrite', overwrite.toString());
    localStorage.setItem('wyze_deleteAfterCompile', deleteAfterCompile.toString());
    localStorage.setItem('wyze_autoOpenFolder', autoOpenFolder.toString());
    localStorage.setItem('wyze_sendNotification', sendNotification.toString());
  }, [sourceDir, useSameFolder, customOutputDir, overwrite, deleteAfterCompile, autoOpenFolder, sendNotification]);

  // Auto scroll terminal logs
  useEffect(() => {
    if (consoleEndRef.current) {
      consoleEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [status.logs]);

  // Request notifications permission on settings mount/toggle
  useEffect(() => {
    if (sendNotification && Notification.permission === 'default') {
      Notification.requestPermission();
    }
  }, [sendNotification]);

  // Poll status when stitching is active
  useEffect(() => {
    if (stitching) {
      pollIntervalRef.current = setInterval(fetchStatus, 600);
    } else {
      if (pollIntervalRef.current) {
        clearInterval(pollIntervalRef.current);
      }
    }
    return () => {
      if (pollIntervalRef.current) {
        clearInterval(pollIntervalRef.current);
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stitching]);

  // Helper to format 24h string "HH" to 12h standard format "h:00 AM/PM"
  const formatHour = (hourStr) => {
    const h = parseInt(hourStr, 10);
    const ampm = h >= 12 ? 'PM' : 'AM';
    const displayH = h % 12 === 0 ? 12 : h % 12;
    return `${displayH}:00 ${ampm}`;
  };

  // Helper to format active compile item string "YYYYMMDD HH:00" to "YYYY-MM-DD h:00 AM/PM"
  const formatCurrentItem = (item) => {
    if (!item) return '';
    const parts = item.split(' ');
    if (parts.length === 2) {
      const [day, hourMin] = parts;
      const [hour] = hourMin.split(':');
      const formattedDay = `${day.slice(0, 4)}-${day.slice(4, 6)}-${day.slice(6, 8)}`;
      return `${formattedDay} ${formatHour(hour)}`;
    }
    return item;
  };

  const triggerNotification = (title, body) => {
    if (sendNotification && Notification.permission === 'granted') {
      new Notification(title, { body });
    }
  };

  const handleOpenFolder = async (folderPath) => {
    try {
      await fetch('/api/open-folder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: folderPath })
      });
    } catch (err) {
      console.error('Failed to open folder:', err);
    }
  };

  const fetchStatus = async () => {
    try {
      const response = await fetch('/api/status');
      if (!response.ok) throw new Error('Failed to query status');
      const data = await response.json();
      setStatus(data);

      if (data.jobs && Array.isArray(data.jobs)) {
        const runningJobs = data.jobs.filter(j => j.status === 'running');
        
        // Check for transition from running -> finished for notification/folder trigger
        data.jobs.forEach(job => {
          if (prevRunningJobsRef.current.has(job.id) && job.status !== 'running' && job.status !== 'pending') {
            if (job.status === 'completed') {
              triggerNotification('Stitch Complete', `Successfully compiled ${formatHour(job.hour)} footage for ${job.day}.`);
              if (autoOpenFolder) {
                const folderToOpen = job.useSameFolder 
                  ? `${job.sourceDir}/${job.day}` 
                  : job.outputDir;
                handleOpenFolder(folderToOpen);
              }
            } else if (job.status === 'failed') {
              triggerNotification('Stitch Failed', `Error compiling ${formatHour(job.hour)} for ${job.day}: ${job.error}`);
            }
          }
        });
        
        // Update ref
        const currentRunning = new Set(runningJobs.map(j => j.id));
        prevRunningJobsRef.current = currentRunning;
      }

      if (!data.running) {
        setStitching(false);
      }
    } catch (err) {
      console.error('Error fetching stitching status:', err);
    }
  };

  const handleBrowseSource = async () => {
    try {
      const response = await fetch('/api/browse?prompt=Select Wyze Camera record folder');
      if (!response.ok) throw new Error('Browse failed');
      const data = await response.json();
      if (!data.canceled && data.path) {
        setSourceDir(data.path);
      }
    } catch (err) {
      console.error('Error browsing source folder:', err);
    }
  };

  const handleBrowseOutput = async () => {
    try {
      const response = await fetch('/api/browse?prompt=Select Custom Output Folder');
      if (!response.ok) throw new Error('Browse failed');
      const data = await response.json();
      if (!data.canceled && data.path) {
        setCustomOutputDir(data.path);
      }
    } catch (err) {
      console.error('Error browsing output folder:', err);
    }
  };

  const handleScan = async () => {
    setScanning(true);
    setScanError('');
    setDays([]);
    setSelectedHours(new Set());
    
    try {
      const response = await fetch('/api/scan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sourceDir })
      });
      
      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error || 'Failed to scan directory');
      }
      
      setDays(data.days);
      
      // Auto-expand first day if available
      if (data.days.length > 0) {
        setExpandedDays(new Set([data.days[0].day]));
      }
    } catch (err) {
      setScanError(err.message);
    } finally {
      setScanning(false);
    }
  };

  const toggleDay = (day) => {
    const next = new Set(expandedDays);
    if (next.has(day)) {
      next.delete(day);
    } else {
      next.add(day);
    }
    setExpandedDays(next);
  };

  const toggleHour = (day, hour) => {
    const key = `${day}_${hour}`;
    const next = new Set(selectedHours);
    if (next.has(key)) {
      next.delete(key);
    } else {
      next.add(key);
    }
    setSelectedHours(next);
  };

  const handleDaySelectAll = (dayObj, e) => {
    e.stopPropagation();
    const next = new Set(selectedHours);
    dayObj.hours.forEach(h => {
      next.add(`${dayObj.day}_${h.hour}`);
    });
    setSelectedHours(next);
  };

  const handleDaySelectNone = (dayObj, e) => {
    e.stopPropagation();
    const next = new Set(selectedHours);
    dayObj.hours.forEach(h => {
      next.delete(`${dayObj.day}_${h.hour}`);
    });
    setSelectedHours(next);
  };

  const handleDaySelectGaps = (dayObj, e) => {
    e.stopPropagation();
    const next = new Set(selectedHours);
    dayObj.hours.forEach(h => {
      if (h.missing.length > 0) {
        next.add(`${dayObj.day}_${h.hour}`);
      } else {
        next.delete(`${dayObj.day}_${h.hour}`);
      }
    });
    setSelectedHours(next);
  };

  const handleStitch = async () => {
    if (selectedHours.size === 0) return;

    if (deleteAfterCompile) {
      const confirmDelete = window.confirm("WARNING: 'Delete source clips after successful compile' is enabled. This will PERMANENTLY remove original files on your SD card once compiled. Are you sure you want to proceed?");
      if (!confirmDelete) return;
    }
    
    // Parse selection set back to structure
    const hoursArray = Array.from(selectedHours).map(key => {
      const [day, hour] = key.split('_');
      return { day, hour };
    });

    setStitching(true);
    setStatus(prev => ({
      ...prev,
      running: true,
      total: hoursArray.length,
      current: 0,
      currentItem: 'Initializing...',
      logs: ['[System] Submitting compile jobs to queue...'],
      errors: []
    }));

    try {
      const response = await fetch('/api/stitch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sourceDir,
          outputDir: useSameFolder ? '' : customOutputDir,
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
      
      // Clear selections on success
      setSelectedHours(new Set());
      
      // Start polling status
      fetchStatus();
    } catch (err) {
      setStitching(false);
      setStatus(prev => ({
        ...prev,
        running: false,
        logs: [...prev.logs, `[System] Job Submission Error: ${err.message}`],
        errors: [...prev.errors, err.message]
      }));
    }
  };

  const handleStitchCustomSelection = async () => {
    if (!inspectingDay || !inspectingHour || inspectorClips.size === 0) return;
    
    if (deleteAfterCompile) {
      const confirmDelete = window.confirm("WARNING: 'Delete source clips after successful compile' is enabled. This will PERMANENTLY remove the selected source clips once compiled. Are you sure you want to proceed?");
      if (!confirmDelete) return;
    }
    
    const hoursArray = [{
      day: inspectingDay,
      hour: inspectingHour.hour,
      clips: Array.from(inspectorClips)
    }];
    
    setStitching(true);
    handleCloseInspector();
    
    try {
      const response = await fetch('/api/stitch', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sourceDir,
          outputDir: useSameFolder ? '' : customOutputDir,
          hours: hoursArray,
          overwrite,
          useSameFolder,
          deleteAfterCompile
        })
      });
      
      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error || 'Failed to submit custom stitching job');
      }
      
      fetchStatus();
    } catch (err) {
      setStitching(false);
      alert(`Error starting custom compile: ${err.message}`);
    }
  };

  // Cancel pending/active job
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

  // Clear completed/failed history
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

  // Inspector handlers
  const handleOpenInspector = (day, hourObj, e) => {
    e.stopPropagation();
    setInspectingDay(day);
    setInspectingHour(hourObj);
    setInspectorClips(new Set(hourObj.clips));
    
    const dialog = document.getElementById('inspect-dialog');
    if (dialog) {
      dialog.showModal();
    }
  };

  const handleCloseInspector = () => {
    const dialog = document.getElementById('inspect-dialog');
    if (dialog) {
      dialog.close();
    }
    setInspectingDay(null);
    setInspectingHour(null);
    setInspectorClips(new Set());
  };

  const toggleInspectorClip = (filename) => {
    const next = new Set(inspectorClips);
    if (next.has(filename)) {
      next.delete(filename);
    } else {
      next.add(filename);
    }
    setInspectorClips(next);
  };

  const selectAllInspectorClips = () => {
    if (inspectingHour) {
      setInspectorClips(new Set(inspectingHour.clips));
    }
  };

  const selectNoneInspectorClips = () => {
    setInspectorClips(new Set());
  };

  const handleDialogClick = (e) => {
    const dialog = e.currentTarget;
    const rect = dialog.getBoundingClientRect();
    const isInDialog = (
      rect.top <= e.clientY &&
      e.clientY <= rect.top + rect.height &&
      rect.left <= e.clientX &&
      e.clientX <= rect.left + rect.width
    );
    if (!isInDialog) {
      handleCloseInspector();
    }
  };

  // Rendering Helper Components

  // Renders a visual 24h timeline gap heatmap
  const renderTimeline = (dayObj) => {
    const hoursMap = new Map(dayObj.hours.map(h => [parseInt(h.hour, 10), h]));
    const blocks = [];
    
    for (let h = 0; h < 24; h++) {
      const hourObj = hoursMap.get(h);
      const hourStr = h.toString().padStart(2, '0');
      let statusClass = 'empty';
      let tooltip = `${formatHour(hourStr)}: No footage`;
      
      if (hourObj) {
        const count = hourObj.clipCount;
        if (count === 60) {
          statusClass = 'full';
          tooltip = `${formatHour(hourStr)}: 60/60 clips (Complete)`;
        } else if (count >= 30) {
          statusClass = 'partial-high';
          tooltip = `${formatHour(hourStr)}: ${count}/60 clips (Minor Gaps)`;
        } else if (count > 0) {
          statusClass = 'partial-low';
          tooltip = `${formatHour(hourStr)}: ${count}/60 clips (Severe Gaps)`;
        }
      }
      
      blocks.push(
        <div 
          key={h} 
          className={`timeline-block ${statusClass}`}
          title={tooltip}
          onClick={(e) => {
            e.stopPropagation();
            if (hourObj) {
              toggleHour(dayObj.day, hourObj.hour);
            }
          }}
        />
      );
    }
    
    return (
      <div className="day-timeline-container" onClick={(e) => e.stopPropagation()}>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', color: 'var(--text-secondary)', marginBottom: '6px' }}>
          <span>24-Hour Footage Timeline (12 AM - 11 PM)</span>
          <span style={{ display: 'flex', gap: '8px' }}>
            <span className="dot dot-full"></span> Complete
            <span className="dot dot-gaps"></span> Gaps
            <span className="dot dot-empty"></span> Empty
          </span>
        </div>
        <div className="day-timeline-bar">
          {blocks}
        </div>
      </div>
    );
  };

  // Renders the Clip Inspector dialog
  const renderInspectorDialog = () => {
    if (!inspectingDay || !inspectingHour) return null;
    
    const formattedDay = `${inspectingDay.slice(0, 4)}-${inspectingDay.slice(4, 6)}-${inspectingDay.slice(6, 8)}`;
    const clipSet = new Set(inspectingHour.clips);
    const minuteGridItems = [];
    
    for (let m = 0; m < 60; m++) {
      const minStr = m.toString().padStart(2, '0');
      const filename = `${minStr}.mp4`;
      const exists = clipSet.has(filename);
      const isChecked = inspectorClips.has(filename);
      
      minuteGridItems.push(
        <label 
          key={m} 
          className={`inspector-minute-tile ${exists ? 'exists' : 'missing'} ${isChecked ? 'checked' : ''}`}
        >
          <input 
            type="checkbox" 
            checked={isChecked}
            disabled={!exists}
            onChange={() => toggleInspectorClip(filename)}
            style={{ display: 'none' }}
          />
          <span className="minute-checkbox-indicator">
            {exists ? (isChecked ? '✓' : '✕') : '✕'}
          </span>
          <span className="minute-num">{minStr}m</span>
        </label>
      );
    }
    
    return (
      <dialog id="inspect-dialog" className="glass-card inspect-modal" onClick={handleDialogClick}>
        <div className="modal-content" onClick={(e) => e.stopPropagation()}>
          <div className="modal-header">
            <div>
              <h3>Inspect Footage: {formattedDay} Hour {formatHour(inspectingHour.hour)}</h3>
              <p style={{ margin: '4px 0 0 0', fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                {inspectingHour.clipCount} of 60 minutes present. Uncheck minute clips you wish to skip from compilation.
              </p>
            </div>
            <button className="btn-close" onClick={handleCloseInspector}>&times;</button>
          </div>
          
          <div className="modal-actions-bar">
            <div style={{ display: 'flex', gap: '8px' }}>
              <button className="btn btn-secondary btn-small" onClick={selectAllInspectorClips}>Select All Available</button>
              <button className="btn btn-secondary btn-small" onClick={selectNoneInspectorClips}>Clear All</button>
            </div>
            <span style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', fontWeight: 500 }}>
              {inspectorClips.size} / {inspectingHour.clipCount} clips selected
            </span>
          </div>
          
          <div className="inspector-minutes-grid">
            {minuteGridItems}
          </div>
          
          <div className="modal-footer">
            <button className="btn btn-secondary" onClick={handleCloseInspector}>Close</button>
            <button 
              className="btn btn-primary" 
              onClick={handleStitchCustomSelection}
              disabled={inspectorClips.size === 0 || stitching}
            >
              Stitch Custom Selection ({inspectorClips.size} Mins)
            </button>
          </div>
        </div>
      </dialog>
    );
  };

  // Renders the integrated floating Video Player
  const renderVideoPlayer = () => {
    if (!activeVideoPath) return null;
    
    return (
      <div className="floating-player-overlay" onClick={() => setActiveVideoPath(null)}>
        <div className="floating-player-card glass-card" onClick={(e) => e.stopPropagation()}>
          <div className="player-header">
            <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
              <h3 style={{ fontSize: '1.05rem', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
                <Video size={18} color="#0ea5e9" />
                Footage Playback: {activeVideoTitle}
              </h3>
              <span className="player-file-path" title={activeVideoPath}>
                {activeVideoPath.length > 50 ? '...' + activeVideoPath.slice(-47) : activeVideoPath}
              </span>
            </div>
            <button className="btn-close" onClick={() => setActiveVideoPath(null)}>&times;</button>
          </div>
          <div className="player-body">
            <video 
              key={activeVideoPath}
              src={`/api/video-stream?path=${encodeURIComponent(activeVideoPath)}`}
              controls 
              autoPlay 
              className="player-video-element"
            />
          </div>
        </div>
      </div>
    );
  };

  // Renders the Multi-Job history board
  const renderJobBoard = () => {
    const jobs = status.jobs || [];
    if (jobs.length === 0) return null;
    
    return (
      <section className="glass-card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h2 style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Layers size={22} color="#0ea5e9" />
            Compilation Jobs & History
          </h2>
          <button 
            className="btn btn-secondary" 
            style={{ padding: '6px 12px', fontSize: '0.8rem' }}
            onClick={handleClearHistory}
            disabled={stitching}
          >
            Clear History
          </button>
        </div>
        
        <div className="jobs-list">
          {jobs.map(job => {
            const isRunning = job.status === 'running';
            const isPending = job.status === 'pending';
            const isCompleted = job.status === 'completed';
            const isFailed = job.status === 'failed';
            
            let statusBadgeClass = 'job-badge ';
            if (isRunning) statusBadgeClass += 'running';
            else if (isPending) statusBadgeClass += 'pending';
            else if (isCompleted) statusBadgeClass += 'completed';
            else if (isFailed) statusBadgeClass += 'failed';
            
            const progress = job.totalClips > 0 
              ? Math.round((job.currentClipIndex / job.totalClips) * 100) 
              : 0;

            const formattedSize = job.fileSize 
              ? `${(job.fileSize / (1024 * 1024)).toFixed(1)} MB` 
              : 'N/A';
              
            return (
              <div key={job.id} className={`job-row ${isRunning ? 'active' : ''}`}>
                <div className="job-info-grid">
                  <div className="job-main-desc">
                    <span className={statusBadgeClass}>{job.status.toUpperCase()}</span>
                    <strong>{job.day.slice(0,4)}-{job.day.slice(4,6)}-{job.day.slice(6,8)}</strong>
                    <span>Hour {formatHour(job.hour)}</span>
                  </div>
                  
                  <div className="job-metrics">
                    {isCompleted && (
                      <>
                        <span>Size: {formattedSize}</span>
                        <span>Duration: {((job.durationMs || 0)/1000).toFixed(1)}s</span>
                      </>
                    )}
                    {(isRunning || isPending) && (
                      <span>Clips: {job.currentClipIndex || 0} / {job.totalClips}</span>
                    )}
                    {isFailed && (
                      <span style={{ color: 'var(--color-danger)' }}>Failed</span>
                    )}
                  </div>
                  
                  <div className="job-actions-col">
                    {isRunning && (
                      <button 
                        className="btn btn-secondary btn-small danger-hover"
                        onClick={() => handleCancelJob(job.id)}
                      >
                        Cancel
                      </button>
                    )}
                    {isPending && (
                      <button 
                        className="btn btn-secondary btn-small danger-hover"
                        onClick={() => handleCancelJob(job.id)}
                      >
                        Remove
                      </button>
                    )}
                    {isCompleted && job.outputPath && (
                      <div style={{ display: 'flex', gap: '8px' }}>
                        <button 
                          className="btn btn-primary btn-small"
                          style={{ padding: '6px 12px', fontSize: '0.8rem' }}
                          onClick={() => {
                            setActiveVideoPath(job.outputPath);
                            setActiveVideoTitle(`${job.day.slice(0,4)}-${job.day.slice(4,6)}-${job.day.slice(6,8)} Hour ${formatHour(job.hour)}`);
                          }}
                        >
                          Play
                        </button>
                        <button 
                          className="btn btn-secondary btn-small"
                          style={{ padding: '6px 12px', fontSize: '0.8rem' }}
                          onClick={() => handleOpenFolder(
                            job.useSameFolder 
                              ? `${job.sourceDir}/${job.day}` 
                              : job.outputDir
                          )}
                        >
                          Reveal
                        </button>
                      </div>
                    )}
                  </div>
                </div>
                
                {/* Granular Clip Progress Bar */}
                {isRunning && (
                  <div className="job-progress-wrapper" style={{ marginTop: '8px' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.78rem', color: 'var(--text-secondary)', marginBottom: '4px' }}>
                      <span>Appending clip: {job.currentClipName || 'Initializing FFmpeg stream...'}</span>
                      <span>{progress}%</span>
                    </div>
                    <div className="job-progress-bg">
                      <div className="job-progress-fill" style={{ width: `${progress}%` }}></div>
                    </div>
                  </div>
                )}
                
                {isFailed && job.error && (
                  <div className="job-error-msg">
                    <AlertTriangle size={14} />
                    {job.error}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </section>
    );
  };

  const progressPercentage = status.total > 0 
    ? Math.round((status.current / status.total) * 100) 
    : 0;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '30px', width: '100%' }}>
      
      {/* Title & Badge */}
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <h1>
            <Video size={40} color="#0ea5e9" /> 
            Wyze SD Card Video Stitcher
          </h1>
          <p style={{ marginTop: '6px' }}>Concatenate 1-minute camera recordings into lossless 1-hour files instantly using FFmpeg.</p>
        </div>
        <div className="header-badge">
          <Sparkles size={16} /> Lossless Stream Copy
        </div>
      </header>

      {/* Directory Settings Card */}
      <section className="glass-card">
        <h2 style={{ marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '8px' }}>
          <FolderOpen size={22} color="#0ea5e9" />
          Directory Configuration
        </h2>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          
          <div className="form-row">
            <div className="form-group">
              <label>Wyze Record Folder (Source)</label>
              <div style={{ display: 'flex', gap: '10px' }}>
                <input 
                  type="text" 
                  value={sourceDir} 
                  onChange={(e) => setSourceDir(e.target.value)} 
                  placeholder="e.g. /Volumes/SD_CARD/record"
                />
                <button 
                  type="button"
                  className="btn btn-secondary"
                  onClick={handleBrowseSource}
                  disabled={scanning || stitching}
                  style={{ minWidth: '100px' }}
                >
                  Browse...
                </button>
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', borderTop: '1px solid var(--border-color)', paddingTop: '20px' }}>
            <label className="checkbox-container">
              <input 
                type="checkbox" 
                checked={useSameFolder} 
                onChange={(e) => setUseSameFolder(e.target.checked)} 
              />
              <div className="checkmark"></div>
              <span style={{ fontSize: '0.95rem', fontWeight: 500 }}>
                Save compiled videos directly inside their original day folders (e.g. record/YYYYMMDD/HH.mp4)
              </span>
            </label>

            {!useSameFolder && (
              <div className="form-group" style={{ animation: 'fadeIn 0.25s ease' }}>
                <label>Custom Destination Directory</label>
                <div style={{ display: 'flex', gap: '10px' }}>
                  <input 
                    type="text" 
                    value={customOutputDir} 
                    onChange={(e) => setCustomOutputDir(e.target.value)} 
                    placeholder="e.g. /Users/jd/Desktop/Stitched"
                  />
                  <button 
                    type="button"
                    className="btn btn-secondary"
                    onClick={handleBrowseOutput}
                    disabled={stitching}
                    style={{ minWidth: '100px' }}
                  >
                    Browse...
                  </button>
                </div>
              </div>
            )}
            
            {/* Automation Options Toggles */}
            <div className="settings-options-grid">
              <label className="checkbox-container">
                <input 
                  type="checkbox" 
                  checked={autoOpenFolder} 
                  onChange={(e) => setAutoOpenFolder(e.target.checked)} 
                />
                <div className="checkmark"></div>
                <span style={{ fontSize: '0.95rem', fontWeight: 500 }}>
                  Auto-open output folder on success
                </span>
              </label>

              <label className="checkbox-container">
                <input 
                  type="checkbox" 
                  checked={sendNotification} 
                  onChange={(e) => {
                    setSendNotification(e.target.checked);
                    if (e.target.checked) {
                      Notification.requestPermission();
                    }
                  }} 
                />
                <div className="checkmark"></div>
                <span style={{ fontSize: '0.95rem', fontWeight: 500 }}>
                  Send system notification when job finishes
                </span>
              </label>

              <label className="checkbox-container danger-label">
                <input 
                  type="checkbox" 
                  checked={deleteAfterCompile} 
                  onChange={(e) => setDeleteAfterCompile(e.target.checked)} 
                />
                <div className="checkmark"></div>
                <span style={{ fontSize: '0.95rem', fontWeight: 500, color: 'var(--color-danger)' }}>
                  Delete source clips after successful compile (Destructive)
                </span>
              </label>
            </div>
          </div>
          
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px', marginTop: '10px' }}>
            <button 
              className="btn btn-primary" 
              onClick={handleScan} 
              disabled={scanning || stitching}
            >
              {scanning ? (
                <>
                  <RefreshCw className="accordion-arrow" style={{ animation: 'spin 1.5s linear infinite' }} size={18} />
                  Scanning...
                </>
              ) : 'Scan Source Directory'}
            </button>
            
            {scanError && (
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: '#ef4444', fontSize: '0.9rem' }}>
                <AlertCircle size={18} />
                {scanError}
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Day Accordions & Hour Selection Grid */}
      <section style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2>Select Footage to Stitch</h2>
          <span style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', fontWeight: 500 }}>
            {selectedHours.size} hours selected
          </span>
        </div>

        {days.length === 0 ? (
          <div className="glass-card empty-state">
            <Layers size={48} style={{ opacity: 0.3 }} />
            <p>No directories scanned yet. Configure paths above and click "Scan Source Directory".</p>
          </div>
        ) : (
          days.map(dayObj => {
            const isOpen = expandedDays.has(dayObj.day);
            return (
              <div key={dayObj.day} className="day-accordion">
                <div className="day-header" onClick={() => toggleDay(dayObj.day)}>
                  <div className="day-info">
                    <ChevronRight 
                      className={`accordion-arrow ${isOpen ? 'open' : ''}`} 
                      size={20} 
                      color="var(--text-secondary)"
                    />
                    <h3 style={{ margin: 0 }}>{dayObj.formattedDay}</h3>
                    <span style={{ fontSize: '0.85rem', background: 'rgba(255,255,255,0.05)', padding: '2px 8px', borderRadius: '12px', color: 'var(--text-secondary)' }}>
                      {dayObj.hours.length} hours recorded
                    </span>
                  </div>
                  
                  {isOpen && (
                    <div className="day-actions">
                      <button 
                        className="btn btn-secondary btn-small" 
                        onClick={(e) => handleDaySelectAll(dayObj, e)}
                      >
                        Select All
                      </button>
                      <button 
                        className="btn btn-secondary btn-small" 
                        onClick={(e) => handleDaySelectGaps(dayObj, e)}
                      >
                        Select Gaps
                      </button>
                      <button 
                        className="btn btn-secondary btn-small" 
                        onClick={(e) => handleDaySelectNone(dayObj, e)}
                      >
                        Clear
                      </button>
                    </div>
                  )}
                </div>

                {isOpen && (
                  <div className="day-content">
                    {/* Visual 24h Heatmap Timeline */}
                    {renderTimeline(dayObj)}

                    {/* Hour Blocks Grid */}
                    <div className="hour-grid">
                      {dayObj.hours.map(hourObj => {
                        const isSel = selectedHours.has(`${dayObj.day}_${hourObj.hour}`);
                        const hasGaps = hourObj.missing.length > 0;
                        const severeGaps = hourObj.clipCount < 30;
                        return (
                          <div 
                            key={hourObj.hour} 
                            className={`hour-tile ${isSel ? 'selected' : ''}`}
                            onClick={() => toggleHour(dayObj.day, hourObj.hour)}
                          >
                            {hasGaps && (
                              <div 
                                className={`warning-badge ${severeGaps ? 'severe' : ''}`}
                                title={`Missing ${hourObj.missing.length} clips`}
                              />
                            )}
                            <div className="hour-number">{formatHour(hourObj.hour)}</div>
                            <div className="hour-stats">{hourObj.clipCount}/60 clips</div>
                            
                            <button
                              className="btn-inspect-tile"
                              title="Inspect and exclude individual clips"
                              onClick={(e) => handleOpenInspector(dayObj.day, hourObj, e)}
                            >
                              Inspect
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>
            );
          })
        )}
      </section>

      {/* Control Actions & Stitch Execution */}
      <section className="glass-card" style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '20px' }}>
          
          <label className="checkbox-container">
            <input 
              type="checkbox" 
              checked={overwrite} 
              onChange={(e) => setOverwrite(e.target.checked)} 
            />
            <div className="checkmark"></div>
            <span>Overwrite existing output files</span>
          </label>

          <button 
            className="btn btn-primary" 
            style={{ padding: '14px 32px', fontSize: '1.05rem', minWidth: '240px' }}
            disabled={selectedHours.size === 0 || stitching}
            onClick={handleStitch}
          >
            <Play size={18} fill="#000" />
            Stitch Selected ({selectedHours.size} Hours)
          </button>
        </div>

        {/* Global Progress Bar for legacy / fallback status UI */}
        {(stitching || (status.logs && status.logs.length > 0 && !status.jobs?.length)) && (
          <div className="progress-container" style={{ marginTop: '10px' }}>
            <div className="progress-header-info">
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                {status.running ? (
                  <RefreshCw className="accordion-arrow" style={{ animation: 'spin 1.5s linear infinite' }} size={16} color="#0ea5e9" />
                ) : (
                  <Check size={18} color="#10b981" />
                )}
                <span>
                  {status.running 
                    ? `Compiling: ${formatCurrentItem(status.currentItem)}` 
                    : status.errors.length > 0 
                      ? 'Compiles Finished with Warnings/Errors' 
                      : 'All Compiles Completed Successfully'}
                </span>
              </div>
              <span>{status.current} / {status.total} Folders ({progressPercentage}%)</span>
            </div>

            <div className="progress-bar-bg">
              <div className="progress-bar-fill" style={{ width: `${progressPercentage}%` }}></div>
            </div>

            <div style={{ marginTop: '10px', display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <label>Real-Time Activity Log</label>
              <div className="log-console">
                {status.logs.map((log, index) => {
                  let logClass = 'log-line';
                  if (log.includes('ERROR:')) logClass += ' error';
                  else if (log.includes('WARNING:') || log.includes('Skipped:')) logClass += ' warning';
                  return (
                    <div key={index} className={logClass}>
                      {log}
                    </div>
                  );
                })}
                <div ref={consoleEndRef} />
              </div>
            </div>
          </div>
        )}
      </section>

      {/* Modern Multi-Job Queue & History Log */}
      {renderJobBoard()}

      {/* Overlays / Modals */}
      {renderInspectorDialog()}
      {renderVideoPlayer()}

      {/* Embedded Animation Keyframes */}
      <style>{`
        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
        @keyframes fadeIn {
          from { opacity: 0; transform: translateY(-4px); }
          to { opacity: 1; transform: translateY(0); }
        }
      `}</style>

    </div>
  );
}

export default App;

