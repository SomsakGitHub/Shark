//
//  ContentView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 5/8/2569 BE.
//

import SwiftUI
import os

struct ContentView: View {
    @State private var items: [Item] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let client = APIClient()

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .refreshable {
                await loadItems()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Connection Error", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            Task { await loadItems() }
                        }
                    }
                } else if items.isEmpty && isLoading {
                    ProgressView("Loading…")
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("No Items", systemImage: "tray")
                    } description: {
                        Text("Tap + to add your first item.")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("\(statusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
            }
        } detail: {
            Text("Select an item")
        }
        .task {
            await loadItems()
        }
    }

    private var statusText: String {
        if isLoading {
            return "Loading…"
        }
        if let errorMessage {
            return errorMessage
        }
        return "\(items.count) item(s) · \(APIConfig.baseURL.absoluteString)"
    }

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await client.fetchItems()
            Logger.view.info("Loaded \(self.items.count, privacy: .public) items")
        } catch {
            errorMessage = error.localizedDescription
            Logger.view.error("Failed to load items: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func addItem() {
        Task {
            do {
                let newItem = try await client.createItem(timestamp: Date())
                items.insert(newItem, at: 0)
                Logger.view.info("Created item \(newItem.id, privacy: .public)")
            } catch {
                errorMessage = error.localizedDescription
                Logger.view.error("Failed to create item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        let ids = offsets.map { items[$0].id }
        Task {
            do {
                for id in ids {
                    try await client.deleteItem(id: id)
                }
                items.remove(atOffsets: offsets)
                Logger.view.info("Deleted items \(ids, privacy: .public)")
            } catch {
                errorMessage = error.localizedDescription
                Logger.view.error("Failed to delete item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

#Preview {
    ContentView()
}
