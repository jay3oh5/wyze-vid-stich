🛑 STATIC CONTEXT (Do not update unless architecture changes)
<tech_stack>
Language: JavaScript (Node.js) / HTML / CSS
Framework: React (Vite)
Backend: Express.js (Node.js)
Tools: FFmpeg (system binary), AppleScript (for native file picker)
Package Manager: npm
Key Dependencies: express, cors, concurrently, lucide-react (for UI icons)
</tech_stack>
<run_commands>
Install all dependencies:
`npm install`
Run application (both React frontend & Express backend in parallel):
`npm run dev`
</run_commands>
<project_architecture>
- ACTIVE_CONTEXT.md: This file, holding static context and dynamic state.
- package.json: Monorepo/combined config for dev scripts and dependencies.
- server.js: Express.js backend serving API endpoints (scanning folders, running FFmpeg, tracking progress).
- index.html: Entrypoint for the Vite React frontend.
- src/:
  - main.jsx: React mount point.
  - App.jsx: Main dashboard interface (design system, selection grids, logs).
  - index.css: Premium CSS design system (dark mode, glassmorphism, responsive styles).
</project_architecture>

🏃‍♂️ DYNAMIC STATE (Overwrite this every session)
<current_objective>
Deliver advanced video player, job queue, visual timeline, and clip-level inspector features.
</current_objective>
<acceptance_criteria>
- Provide an intuitive GUI in the browser.
- Allow sequential background job queues with detailed cancel/clear controllers.
- Support real-time clip-level progress tracking.
- Display visual timelines indicating footage density/gaps.
- Enable manual clip selection/exclusion modal inspector.
- Embed a range-capable video player in the web interface.
- Support system notifications and post-compile auto-open directory actions.
</acceptance_criteria>
<completed_tasks>
- Implemented task queue system and sequentially processed jobs on backend.
- Added range-based streaming video player on frontend and video stream API.
- Integrated spawn-based FFmpeg stream parser for real-time clip progress updates.
- Designed 24h visual timeline heatmap for footage density.
- Engineered detailed minute-by-minute clip inspector using native `<dialog>` and light dismiss.
- Added Settings checkboxes for destructive file deletion, Finder auto-open, and browser notification alerts.
- Verified compilation and lint rules (`npm run build`, `npm run lint`).
</completed_tasks>
<key_files_modified>
- server.js
- src/App.jsx
- src/index.css
- ACTIVE_CONTEXT.md
</key_files_modified>
<next_steps>
1. Launch the local web server by running `npm run dev`.
2. Open [http://localhost:5173](http://localhost:5173) in your browser.
3. Stitch single hour clips, watch real-time clip progress, exclude clips using the inspector, and play back merged surveillance clips directly from the job history table!
</next_steps>
<known_blockers>
None.
</known_blockers>
<session_summary>
Successfully built and integrated a complete, surveillance-grade footage compiler suite. Discussed cross-platform packaging options (Electron, Tauri, Portable ZIP) to share the app across macOS, Windows, and Linux without hosting.
</session_summary>


