//
//  ContentView.swift
//  Shark
//
//  Created by tiscomacnb2486 on 5/8/2569 BE.
//

import SwiftUI

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
                }
            }
        } detail: {
            Text("Select an item")
        }
        .task {
            await loadItems()
        }
    }

    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await client.fetchItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addItem() {
        Task {
            do {
                let newItem = try await client.createItem(timestamp: Date())
                items.insert(newItem, at: 0)
            } catch {
                errorMessage = error.localizedDescription
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
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ContentView()
}
