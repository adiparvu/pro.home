import SwiftUI

// MARK: - Work session UI (Start ▸ / Pause ⏸ / Finish ⏹)
//
// Both views read WorkSessionStore.shared directly — the @Observable authority
// the phone context menu and the Apple Watch drive — so the clock is identical
// on the row, the banner, the Dynamic Island and the wrist. A TimelineView
// ticks the display each second; the value itself is always derived from dates,
// so a pause freezes it exactly and it survives the app being killed.

// MARK: Row timer — the compact clock exactly where it was requested

struct SessionRowTimer: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let s = WorkSessionStore.shared.active {
                Button {
                    WorkSessionStore.shared.togglePause()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: s.isPaused ? "pause.fill" : "timer")
                            .font(AppFont.scaled(10, weight: .bold))
                        Text(verbatim: s.elapsed(at: context.date).workSessionClock)
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(s.isPaused ? Color.brandWarning : Color.brandSuccess)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .glassCapsule()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(s.isPaused ? "session_resume" : "session_pause"))
            }
        }
    }
}

// MARK: Pinned banner — the always-visible session with full controls

struct SessionBanner: View {
    @Environment(TaskService.self) private var taskService

    var body: some View {
        if let s = WorkSessionStore.shared.active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                banner(s, now: context.date)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xs)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func banner(_ s: WorkSessionStore.Active, now: Date) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: s.isPaused ? "pause.fill" : "timer")
                .font(AppFont.scaled(15, weight: .bold))
                .foregroundStyle(s.isPaused ? Color.brandWarning : Color.brandSuccess)
                .frame(width: 38, height: 38)
                .glassCircle()

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: s.title)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(verbatim: s.elapsed(at: now).workSessionClock)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(s.isPaused ? Color.brandWarning : Color.brandSuccess)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 4)

            // Pause / Resume
            Button {
                WorkSessionStore.shared.togglePause()
            } label: {
                Image(systemName: s.isPaused ? "play.fill" : "pause.fill")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(s.isPaused ? "session_resume" : "session_pause"))

            // Finish — stops, banks the time, marks the task done.
            Button {
                finish()
            } label: {
                Image(systemName: "stop.fill")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.brandDanger)
                    .frame(width: 40, height: 40)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("session_finish"))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.sm)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private func finish() {
        guard let done = WorkSessionStore.shared.finish() else { return }
        // Confirmed behaviour: Finish also marks the task complete.
        if let task = taskService.tasks.first(where: { $0.id == done.taskId }), !task.isCompleted {
            Task { await taskService.toggleComplete(task) }
        }
    }
}
