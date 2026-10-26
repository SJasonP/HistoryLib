/// History must never appear durably saved when only the recovery store exists.
enum HistoryStoragePolicy {
    static func canMutate(backend: String) -> Bool {
        backend == "cloudKit"
    }
}
