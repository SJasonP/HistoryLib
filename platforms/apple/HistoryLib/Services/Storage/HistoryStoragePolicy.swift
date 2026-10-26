/// Only storage initialization controls write access. Cloud account, network,
/// and transfer failures never lock the primary store. Recovery stays read-only.
enum HistoryStoragePolicy {
    static func canMutate(backend: String) -> Bool {
        backend == "primary"
    }
}
