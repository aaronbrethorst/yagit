import AppKit
import GitCore
import SwiftUI

@main
struct YAGitApp: App {
    var body: some Scene {
        WindowGroup(for: URL.self) { $url in
            if let url {
                RepositoryWindow(url: url)
            } else {
                WelcomeView()
            }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenRepositoryButton()
            }
            RepositoryCommands()
        }
    }
}

/// Where the app remembers the last opened repository.
enum RecentRepositories {
    private static let key = "lastRepositoryPath"

    static var last: URL? {
        get { UserDefaults.standard.string(forKey: key).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: key) }
    }
}

/// Runs the open panel and opens a window for the chosen directory.
struct OpenRepositoryButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Repository…") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Open"
            panel.message = "Choose a Git repository."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            RecentRepositories.last = url
            openWindow(value: url)
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}

/// Shown when no repository is open. Reopens the last repository automatically.
struct WelcomeView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No repository open")
                .font(.system(size: 15, weight: .semibold))
            Text("Open a folder that contains a Git repository.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            OpenRepositoryButton()
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(minWidth: 420, minHeight: 280)
        .task {
            guard let last = RecentRepositories.last,
                  FileManager.default.fileExists(atPath: last.path) else { return }
            openWindow(value: last)
            dismissWindow()
        }
    }
}

/// Menu commands that act on the frontmost repository window.
struct RepositoryCommands: Commands {
    @FocusedValue(\.repositoryStore) private var store

    var body: some Commands {
        CommandMenu("Changes") {
            // A bare Space, like Quick Look in Finder. `canToggleSelectedFile` keeps the item
            // disabled while text is being typed, so a space still types a space.
            Button(store?.selectedChange?.side == .staged ? "Unstage File" : "Stage File") {
                store?.toggleSelectedFile()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(store?.canToggleSelectedFile != true)
        }
        CommandMenu("Repository") {
            Button("Fetch") { store?.fetch() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store == nil || store?.isFetching == true)
            Button("New Branch…") { store?.isPresentingNewBranch = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store == nil)
            Divider()
            Button("Commit") { store?.commit() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store?.canCommit != true)
        }
    }
}

extension FocusedValues {
    @Entry var repositoryStore: RepositoryStore?
}
