import SwiftUI
import AppKit

// MARK: - Models

struct DockerContainer: Identifiable, Hashable {
    let id: String        // short container ID
    let name: String
    let image: String
    let status: String
}

struct K8sPod: Identifiable, Hashable {
    var id: String { "\(namespace)/\(name)" }
    let namespace: String
    let name: String
    let phase: String        // Running, Pending, CrashLoopBackOff, …
    let containers: [String]

    var isRunning: Bool { phase == "Running" }
}

// MARK: - Service (login-shell shell-out)

/// Lists Docker containers / Kubernetes pods and builds the `exec` command that
/// attaches an interactive shell. Commands run through the user's LOGIN shell so
/// `docker` / `kubectl` resolve on the same PATH they would in a normal terminal
/// (Docker Desktop and kubectl usually live in /usr/local/bin or Homebrew).
enum ContainerAttachService {
    /// Run `command` via `$SHELL -lc`, returning stdout, stderr, and exit code.
    static func run(_ command: String) async -> (out: String, err: String, code: Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-lc", command]
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    cont.resume(returning: ("", error.localizedDescription, -1))
                    return
                }
                // Read before waiting so a large output can't deadlock the pipe.
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                cont.resume(returning: (
                    String(data: outData, encoding: .utf8) ?? "",
                    String(data: errData, encoding: .utf8) ?? "",
                    process.terminationStatus
                ))
            }
        }
    }

    static func listDocker() async -> (items: [DockerContainer], error: String?) {
        let r = await run("docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}'")
        guard r.code == 0 else {
            return ([], dockerUnavailableReason(stderr: r.err, needsSudo: false, hostLabel: "this Mac"))
        }
        return (parseDocker(r.out), nil)
    }

    static func listPods() async -> (items: [K8sPod], error: String?) {
        // Gate kubectl on its existence so a server without it fails instantly
        // (no wasted round-trip / misleading error).
        let r = await run("if command -v kubectl >/dev/null 2>&1; then kubectl get pods --all-namespaces -o json; fi")
        guard r.code == 0 else {
            return ([], cleanError(r.err, fallback: "kubectl isn't available."))
        }
        return (parsePods(r.out), nil)
    }

    // MARK: Remote (over SSH to a saved host)

    static func run(host: SavedHost, command: String, stdin: String? = nil) async -> (out: String, err: String, code: Int32) {
        let res = await RemoteCommand.run(host: host, command: command, stdin: stdin)
        return (res.stdout, res.stderr, res.status)
    }

    /// List containers ON the remote host. Runs as the saved SSH user — no root
    /// required. If the user isn't in the docker group, retries with `sudo -n`
    /// (passwordless sudo); if that also fails, reports the permission problem
    /// with the fix hint.
    static func listDocker(host: SavedHost) async -> (items: [DockerContainer], error: String?, needsSudo: Bool) {
        var needsSudo = false
        var r = await run(host: host, command: "docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}'")
        if r.code != 0, RemoteCommand.isPermissionDenied(r.err) {
            needsSudo = true
            // The SSH and sudo passwords are the same account: feed the saved
            // password to `sudo -S` via ssh's stdin. Falls back to passwordless
            // `sudo -n` for hosts without a stored password.
            if !host.password.isEmpty {
                r = await run(host: host, command: "sudo -S docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}'",
                              stdin: host.password + "\n")
            } else {
                r = await run(host: host, command: "sudo -n docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}'")
            }
        }
        guard r.code == 0 else {
            return ([], dockerUnavailableReason(stderr: r.err, needsSudo: needsSudo, hostLabel: host.displayLabel), needsSudo)
        }
        return (parseDocker(r.out), nil, needsSudo)
    }

    static func listPods(host: SavedHost) async -> (items: [K8sPod], error: String?) {
        let r = await run(host: host,
                          command: "if command -v kubectl >/dev/null 2>&1; then kubectl get pods --all-namespaces -o json; fi")
        guard r.code == 0 else {
            return ([], cleanError(r.err, fallback: "kubectl isn't available on \(host.displayLabel)."))
        }
        return (parsePods(r.out), nil)
    }

    /// The bare docker/kubectl command typed into an ALREADY-connected terminal
    /// ("run in current tab" while the user is on the host). Interactive `sudo`
    /// prompts for the password in the terminal. Prefers `bash`.
    static func dockerAttachTyped(needsSudo: Bool, _ c: DockerContainer) -> String {
        dockerExec(needsSudo: needsSudo, name: c.name, binary: "docker")
    }

    /// `<binary> exec -it <name> bash` — prefers bash (nicer interactive shell);
    /// a `bash` fallback to `sh` exists in most images. `binary` is `docker`, or
    /// its absolute path for a directly-spawned tab/split.
    static func dockerAttachCommand(binary: String, _ c: DockerContainer) -> String {
        dockerExec(needsSudo: false, name: c.name, binary: binary)
    }

    /// `[sudo] docker exec -it <name> bash`.
    private static func dockerExec(needsSudo: Bool, name: String, binary: String) -> String {
        "\(needsSudo ? "sudo " : "")\(binary) exec -it \(name) bash"
    }

    static func k8sAttachTyped(_ pod: K8sPod, container: String?) -> String {
        var cmd = "kubectl exec -it -n \(pod.namespace) \(pod.name)"
        if let container, !container.isEmpty { cmd += " -c \(container)" }
        cmd += " -- bash"
        return cmd
    }

    // MARK: Parsing (shared local/remote)

    private static func parseDocker(_ out: String) -> [DockerContainer] {
        var result: [DockerContainer] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4, !parts[1].isEmpty else { continue }
            result.append(DockerContainer(
                id: parts[0],
                name: parts[1],
                image: parts[2],
                status: parts[3]
            ))
        }
        return result
    }

    private static func parsePods(_ out: String) -> [K8sPod] {
        guard let data = out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else { return [] }
        var pods: [K8sPod] = []
        for item in items {
            let meta = item["metadata"] as? [String: Any]
            let spec = item["spec"] as? [String: Any]
            let status = item["status"] as? [String: Any]
            guard let name = meta?["name"] as? String, !name.isEmpty else { continue }
            let containers = (spec?["containers"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String } ?? []
            pods.append(K8sPod(
                namespace: (meta?["namespace"] as? String) ?? "default",
                name: name,
                phase: (status?["phase"] as? String) ?? "",
                containers: containers
            ))
        }
        return pods
    }

    /// Human-readable reason docker can't list containers, with the fix hint —
    /// shown inline in the panel so a failure is never a mystery.
    static func dockerUnavailableReason(stderr: String, needsSudo: Bool, hostLabel: String) -> String {
        let lower = stderr.lowercased()
        if lower.contains("command not found") || lower.contains("no such file") {
            return loc(.docker_not_installed_reason, hostLabel)
        }
        if lower.contains("permission denied")
            || lower.contains("cannot connect to the docker daemon")
            || lower.contains("a password is required")
            || lower.contains("not in the sudoers") {
            return loc(.docker_permission_reason, hostLabel)
        }
        if lower.contains("connection refused")
            || lower.contains("is the docker daemon running")
            || lower.contains("daemon not running") {
            return loc(.docker_daemon_down_reason, hostLabel)
        }
        // Unknown — surface the raw ssh/docker error (cleaned), not a guess.
        return cleanError(stderr, fallback: loc(.docker_unknown_reason, hostLabel))
    }

    /// Absolute path of a CLI (docker/kubectl) as an interactive login shell
    /// would resolve it — needed because a directly-spawned process (Ghostty's
    /// `command`) doesn't inherit the Homebrew / /usr/local PATH.
    static func resolve(_ tool: String) async -> String? {
        let r = await run("command -v \(tool)")
        let path = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.code == 0 && !path.isEmpty) ? path : nil
    }

    /// `<binary> exec -it -n <ns> <pod> [-c container] -- bash`.
    static func k8sAttachCommand(binary: String, _ pod: K8sPod, container: String?) -> String {
        // Namespace / pod / container names are DNS-1123 safe (no quoting needed).
        var cmd = "\(binary) exec -it -n \(pod.namespace) \(pod.name)"
        if let container, !container.isEmpty { cmd += " -c \(container)" }
        cmd += " -- bash"
        return cmd
    }

    private static func cleanError(_ err: String, fallback: String) -> String {
        let lower = err.lowercased()
        if lower.contains("command not found") || lower.contains("no such file") {
            return fallback  // e.g. "Docker isn't available." / "kubectl isn't available."
        }
        if lower.contains("connection refused") || lower.contains("was refused")
            || lower.contains("couldn't get current server")
            || lower.contains("unable to connect")
            || lower.contains("cannot connect to the docker daemon") {
            return "Not reachable — is it running?"
        }
        // docker/kubectl are chatty on stderr (log-prefixed lines). Pick the last
        // line that reads like the actual error, else the last non-empty line.
        let lines = err.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let pick = lines.last(where: { $0.lowercased().contains("error") }) ?? lines.last ?? ""
        if pick.isEmpty { return fallback }
        return pick.count > 140 ? String(pick.prefix(140)) + "…" : pick
    }
}

// MARK: - Model

/// Backs the container-attach side panel. Lists Docker containers and K8s pods,
/// and opens an `exec` shell in a new terminal tab on click.
@MainActor
final class ContainerAttachModel: ObservableObject {
    static let shared = ContainerAttachModel()

    /// Where to look for containers.
    enum Scope: Equatable {
        /// The SSH server the user is currently connected to; falls back to the
        /// local Mac when no SSH session is focused. The default.
        case auto
        /// Explicitly the local Mac.
        case local
        /// A specific saved host.
        case host(SavedHost)
    }

    @Published private(set) var dockerContainers: [DockerContainer] = []
    @Published private(set) var pods: [K8sPod] = []
    @Published private(set) var dockerError: String?
    @Published private(set) var k8sError: String?
    @Published private(set) var loading = false
    @Published private(set) var loadedOnce = false
    /// Where to look for containers (defaults to the active SSH server).
    @Published var scope: Scope = .auto

    /// Absolute binary paths (login-shell PATH), used for directly-spawned tabs.
    private var dockerPath: String?
    private var kubectlPath: String?
    /// Whether sudo (`sudo -n`) was required to talk to docker on the remote host.
    private var dockerNeedsSudo = false

    /// The host to query, or nil for the local Mac.
    var resolvedHost: SavedHost? {
        switch scope {
        case .auto:  return VaultsTabsModel.shared.activeSSHHost
        case .local: return nil
        case .host(let h): return h
        }
    }

    func selectScope(_ scope: Scope) {
        guard self.scope != scope else { return }
        self.scope = scope
        refresh()
    }

    /// Last fetched results per scope — republished instantly on refresh so the
    /// list appears immediately (with a spinner) instead of a blank panel while
    /// the probe round-trip runs.
    private struct HostCache {
        var containers: [DockerContainer]
        var pods: [K8sPod]
        var dockerError: String?
        var k8sError: String?
        var needsSudo: Bool
    }
    private var caches: [String: HostCache] = [:]

    private var cacheKey: String {
        if let host = resolvedHost { return host.id.uuidString }
        return "local"
    }

    /// Bumped on every refresh; results from a superseded refresh are discarded
    /// so switching servers can't land stale data from the previous one.
    private var refreshGeneration = 0

    func refresh() {
        refreshGeneration += 1
        let gen = refreshGeneration
        loading = true
        // Publish the cached result for this scope immediately — the list shows
        // up instantly (dimmed behind the loading spinner) and only then updates
        // when the fresh probe lands.
        if let cache = caches[cacheKey] {
            self.dockerContainers = cache.containers
            self.pods = cache.pods
            self.dockerError = cache.dockerError
            self.k8sError = cache.k8sError
            self.dockerNeedsSudo = cache.needsSudo
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let host = self.resolvedHost {
                // Parallel docker + k8s over ONE multiplexed ssh connection —
                // both finish in roughly a single round-trip.
                async let dockerR = ContainerAttachService.listDocker(host: host)
                async let podsR = ContainerAttachService.listPods(host: host)
                let (docker, dErr, dSudo) = await dockerR
                let (pods, kErr) = await podsR
                guard gen == self.refreshGeneration else { return }   // stale
                self.caches[self.cacheKey] = HostCache(containers: docker, pods: pods,
                                                       dockerError: dErr, k8sError: kErr, needsSudo: dSudo)
                self.dockerContainers = docker
                self.dockerError = dErr
                self.dockerNeedsSudo = dSudo
                self.pods = pods
                self.k8sError = kErr
            } else {
                async let dockerResult = ContainerAttachService.listDocker()
                async let podResult = ContainerAttachService.listPods()
                async let dockerBin = ContainerAttachService.resolve("docker")
                async let kubectlBin = ContainerAttachService.resolve("kubectl")
                let (docker, k8s, dPath, kPath) = await (dockerResult, podResult, dockerBin, kubectlBin)
                guard gen == self.refreshGeneration else { return }   // stale
                self.caches[self.cacheKey] = HostCache(containers: docker.items, pods: k8s.items,
                                                       dockerError: docker.error, k8sError: k8s.error, needsSudo: false)
                self.dockerContainers = docker.items
                self.dockerError = docker.error
                self.pods = k8s.items
                self.k8sError = k8s.error
                self.dockerPath = dPath
                self.kubectlPath = kPath
            }
            self.loading = false
            self.loadedOnce = true
        }
    }

    func attach(_ c: DockerContainer, target: AttachTarget) {
        guard let host = resolvedHost else {
            // Local Mac: a directly-spawned process (new tab / split) needs the
            // absolute path (docker isn't on Ghostty's minimal spawn PATH). The
            // current tab types into an interactive shell that has the PATH.
            let binary = target == .currentTab ? "docker" : (dockerPath ?? "docker")
            open(ContainerAttachService.dockerAttachCommand(binary: binary, c), name: c.name, target: target)
            return
        }
        // Remote: "copy the current session" — open a new tab/split that
        // auto-connects to `host` with the saved password, then runs the docker
        // command in the remote shell. When sudo is needed, hand over the saved
        // password so the app can answer the sudo prompt automatically.
        let cmd = ContainerAttachService.dockerAttachTyped(needsSudo: dockerNeedsSudo, c)
        let sudoPassword = dockerNeedsSudo ? host.password : nil
        switch target {
        case .newTab:
            _ = VaultsTabsModel.shared.openSSHTab(host: host, name: c.name,
                                                  startupCommand: cmd, sudoPassword: sudoPassword)
        case .split:
            _ = VaultsTabsModel.shared.openSSHSplit(host: host, name: c.name,
                                                    startupCommand: cmd, sudoPassword: sudoPassword)
        case .currentTab:
            _ = VaultsTabsModel.shared.runInTargetTerminal(cmd)
        }
    }

    /// Open the SFTP side panel rooted INSIDE `c` — a container-aware file
    /// browser (`docker exec`/`docker cp`) for uploading files into it without
    /// guessing the attached shell's cwd.
    func openContainerFiles(_ c: DockerContainer) {
        guard let host = resolvedHost else { return }
        let location = FileLocation.container(host: host, name: c.name, needsSudo: dockerNeedsSudo)
        VaultsTabsModel.shared.openSftpPanel(for: location)
        HostManagerController.shared.show()
    }

    func attach(_ pod: K8sPod, container: String?, target: AttachTarget) {
        guard let host = resolvedHost else {
            let binary = target == .currentTab ? "kubectl" : (kubectlPath ?? "kubectl")
            open(ContainerAttachService.k8sAttachCommand(binary: binary, pod, container: container),
                 name: pod.name, target: target)
            return
        }
        let cmd = ContainerAttachService.k8sAttachTyped(pod, container: container)
        switch target {
        case .newTab:
            _ = VaultsTabsModel.shared.openSSHTab(host: host, name: pod.name, startupCommand: cmd)
        case .split:
            _ = VaultsTabsModel.shared.openSSHSplit(host: host, name: pod.name, startupCommand: cmd)
        case .currentTab:
            _ = VaultsTabsModel.shared.runInTargetTerminal(cmd)
        }
    }

    /// Whether a "current tab" target exists right now (drives the menu item).
    var hasActiveTerminal: Bool { VaultsTabsModel.shared.hasActiveTerminal }

    private func open(_ command: String, name: String, target: AttachTarget) {
        switch target {
        case .newTab:
            _ = VaultsTabsModel.shared.newCommandTerminal(command: command, name: name)
        case .split:
            _ = VaultsTabsModel.shared.splitCommand(command: command, name: name)
        case .currentTab:
            _ = VaultsTabsModel.shared.runInTargetTerminal(command)
        }
    }
}

/// Where an attach shell opens.
enum AttachTarget { case newTab, split, currentTab }

// MARK: - Sidebar tab

/// Command-sidebar tab listing Docker containers and Kubernetes pods. Clicking a
/// row opens an interactive `exec` shell in a new terminal tab. Lives in the
/// shared command sidebar (alongside Snippets / History / Themes) so it doesn't
/// add another top-bar icon.
struct ContainersTab: View {
    @ObservedObject private var model = ContainerAttachModel.shared
    @ObservedObject private var hostsStore = SavedHostsStore.shared
    @ObservedObject private var tabs = VaultsTabsModel.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dockerSection
                    k8sSection
                }
                .padding(.vertical, 12)
            }
        }
        .onAppear { if !model.loadedOnce { model.refresh() } }
        // In auto scope, follow the server the user is actually connected to.
        .onChange(of: tabs.activeSSHHost?.id) { _ in
            if model.scope == .auto { model.refresh() }
        }
    }

    /// What the header menu shows right now.
    private var scopeLabel: String {
        switch model.scope {
        case .host(let h): return h.displayLabel
        case .local:       return "Local Mac"
        case .auto:
            return tabs.activeSSHHost?.displayLabel ?? "Local Mac"
        }
    }
    private var scopeIcon: String {
        switch model.scope {
        case .local: return "desktopcomputer"
        case .auto:  return tabs.activeSSHHost == nil ? "desktopcomputer" : "server.rack"
        case .host:  return "server.rack"
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                // Auto: the server you're connected to (or local).
                if let active = tabs.activeSSHHost {
                    Button {
                        model.selectScope(.auto)
                    } label: {
                        Label("Current server: \(active.displayLabel)", systemImage: "bolt")
                    }
                }
                Button {
                    model.selectScope(.local)
                } label: {
                    Label("Local Mac", systemImage: "desktopcomputer")
                }
                Divider()
                ForEach(hostsStore.hosts) { host in
                    Button {
                        model.selectScope(.host(host))
                    } label: {
                        if case .host(let selected) = model.scope, selected.id == host.id {
                            Label(host.displayLabel, systemImage: "checkmark")
                        } else {
                            Text(host.displayLabel)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: scopeIcon).font(.system(size: 11))
                    Text(scopeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(.secondaryText)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverTipText("Where to look for containers")

            Spacer()
            Button { model.refresh() } label: {
                if model.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(model.loading)
            .hoverTipText("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Docker

    private var dockerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Docker", systemImage: "cube.box", count: model.dockerContainers.count)
            if model.loading {
                emptyNote("Loading…")
            } else if let err = model.dockerError {
                emptyNote(err)
            } else if model.dockerContainers.isEmpty {
                if let host = model.resolvedHost {
                    emptyNote("No running containers on \(host.displayLabel).")
                } else {
                    emptyNote("No running containers.")
                }
            } else {
                ForEach(model.dockerContainers) { c in
                    row(title: c.name, subtitle: subtitle(c.image, c.status)) {
                        tabTargetButtons { model.attach(c, target: $0) }
                        Divider()
                        Button {
                            model.openContainerFiles(c)
                        } label: {
                            Label("Upload files", systemImage: "arrow.up.doc")
                        }
                        .disabled(model.resolvedHost == nil)
                        .help(model.resolvedHost == nil ? "Pick a server scope to upload into a container" : "Browse & upload files into this container")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: Kubernetes

    private var k8sSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Kubernetes", systemImage: "helm", count: model.pods.count)
            if model.loading {
                emptyNote("Loading…")
            } else if let err = model.k8sError {
                emptyNote(err)
            } else if model.pods.isEmpty {
                emptyNote("No pods found.")
            } else {
                ForEach(model.pods) { pod in
                    if pod.containers.count > 1 {
                        row(title: pod.name,
                            subtitle: subtitle("\(pod.namespace) · \(pod.phase)",
                                               "\(pod.containers.count) containers")) {
                            ForEach(pod.containers, id: \.self) { name in
                                Menu(name) {
                                    tabTargetButtons { model.attach(pod, container: name, target: $0) }
                                }
                            }
                        }
                    } else {
                        row(title: pod.name, subtitle: subtitle(pod.namespace, pod.phase)) {
                            tabTargetButtons { model.attach(pod, container: pod.containers.first, target: $0) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: Row + attach menu

    /// A non-clickable info row with an attach menu anchored on the terminal
    /// icon. Only the icon is interactive — clicking anywhere else does nothing
    /// (so a stray row click never spawns a tab).
    private func row<Menu: View>(title: String,
                                 subtitle: String,
                                 @ViewBuilder menu: () -> Menu) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12)).foregroundStyle(.primary).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            SwiftUI.Menu {
                menu()
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverTipText("Open a shell here")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .listRowHover()
    }

    /// The "new tab / split / current tab" choice shown in every attach menu.
    @ViewBuilder private func tabTargetButtons(_ action: @escaping (AttachTarget) -> Void) -> some View {
        Button {
            action(.newTab)
        } label: {
            Label("Open in new tab", systemImage: "plus.rectangle.on.rectangle")
        }
        Button {
            action(.split)
        } label: {
            Label("Open in split pane", systemImage: "rectangle.split.2x1")
        }
        .disabled(!model.hasActiveTerminal)
        Button {
            action(.currentTab)
        } label: {
            Label("Run in current tab", systemImage: "return")
        }
        .disabled(!model.hasActiveTerminal)
    }

    // MARK: Bits

    private func sectionHeader(_ title: String, systemImage: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if count > 0 {
                Text("\(count)").font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func subtitle(_ a: String, _ b: String) -> String {
        [a, b].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
