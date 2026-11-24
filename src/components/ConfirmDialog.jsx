import { AlertTriangle, X } from 'lucide-react';

export function ConfirmDialog({
  title,
  message,
  confirmLabel = 'Proceed',
  cancelLabel = 'Cancel',
  destructive = false,
  onConfirm,
  onCancel
}) {
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={title}
      className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onCancel}
    >
      <div
        className="w-full max-w-md bg-[#111520] border border-white/[0.12] rounded-2xl overflow-hidden shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="p-5 flex items-start justify-between gap-3">
          <div className="flex items-start gap-3">
            <span
              className={`w-9 h-9 rounded-lg flex items-center justify-center shrink-0 ${
                destructive
                  ? 'bg-rose-500/15 text-rose-400 border border-rose-500/30'
                  : 'bg-sky-500/15 text-sky-400 border border-sky-500/30'
              }`}
            >
              <AlertTriangle className="w-4 h-4" />
            </span>
            <div>
              <h2 className="text-base font-semibold text-white">{title}</h2>
              <p className="text-sm text-slate-300 mt-1.5 leading-relaxed">{message}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onCancel}
            aria-label="Close confirmation dialog"
            className="text-slate-400 hover:text-white p-1 rounded cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="px-5 py-3.5 bg-[#0d1017] border-t border-white/[0.08] flex items-center justify-end gap-2.5">
          <button
            type="button"
            onClick={onCancel}
            className="px-4 py-2 rounded-lg text-sm font-medium bg-white/[0.05] border border-white/[0.08] text-slate-200 hover:bg-white/[0.1] cursor-pointer"
          >
            {cancelLabel}
          </button>
          <button
            type="button"
            onClick={onConfirm}
            className={`px-4 py-2 rounded-lg text-sm font-semibold cursor-pointer ${
              destructive
                ? 'bg-rose-500 text-white hover:bg-rose-400'
                : 'bg-sky-500 text-slate-950 hover:bg-sky-400'
            }`}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
