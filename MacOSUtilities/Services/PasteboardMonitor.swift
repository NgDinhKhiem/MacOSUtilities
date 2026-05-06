import Foundation

@MainActor
final class PasteboardMonitor {
    private var timer: Timer?
    private var lastChangeCount = 0
    private var reader: PasteboardReading?

    func start(store: ClipboardHistoryStore, interval: TimeInterval = 0.6) {
        start(store: store, reader: SystemPasteboard(), interval: interval)
    }

    func start(
        store: ClipboardHistoryStore,
        reader: PasteboardReading,
        interval: TimeInterval = 0.6
    ) {
        stop()

        self.reader = reader
        lastChangeCount = reader.changeCount
        store.capture(from: reader)

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self, weak store] _ in
            Task { @MainActor in
                guard let self, let store else {
                    return
                }

                self.poll(store: store)
            }
        }
        timer.tolerance = interval / 2
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reader = nil
    }

    private func poll(store: ClipboardHistoryStore) {
        guard let reader else {
            return
        }

        let currentChangeCount = reader.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        lastChangeCount = currentChangeCount
        store.capture(from: reader)
    }
}
