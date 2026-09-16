import SwiftUI

/// Focus plumbing shared by the three lists.
///
/// SwiftUI's `List` on macOS does not move the window's first responder when a row is clicked —
/// the click lands on the row's own hosting view — so without this the emphasized ("primary")
/// selection only followed the Tab key.
extension View {
    /// Makes `pane` the focused list while `focus` points at it.
    func paneFocus(_ focus: FocusState<RepositoryStore.Pane?>.Binding,
                   _ pane: RepositoryStore.Pane) -> some View {
        focused(focus, equals: pane)
    }

    /// Claims focus for `pane` on any click inside the view.
    ///
    /// The selection binding alone is not enough: clicking the row that is already selected in an
    /// unfocused list does not change the selection, so nothing would fire. A simultaneous gesture
    /// runs alongside the list's own selection handling rather than swallowing it.
    func claimsPaneFocus(_ store: RepositoryStore, _ pane: RepositoryStore.Pane) -> some View {
        simultaneousGesture(TapGesture().onEnded { store.focusedPane = pane })
    }
}
