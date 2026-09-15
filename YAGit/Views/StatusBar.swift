import GitCore
import SwiftUI

/// Last action on the left; spinner, branch and ahead count on the right.
struct StatusBar: View {
    @Bindable var store: RepositoryStore

    var body: some View {
        HStack(spacing: 8) {
            Text(store.statusText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if store.isFetching {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(branchText)
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var branchText: String {
        guard let current = store.snapshot?.current else { return store.currentBranch }
        switch current.ahead {
        case nil: return "\(current.name) · not on origin"
        case 0: return "\(current.name) · in sync with origin"
        case let n?: return "\(current.name) · \(n) ahead of origin"
        }
    }
}
