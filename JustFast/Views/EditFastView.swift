//
//  EditFastView.swift
//  JustFast
//
//  Edit an existing fast or add a missed one retroactively (§4.2). Start, end
//  and note are editable; validation errors surface with a clear message
//  identifying the conflict. Delete is available when editing.
//

import SwiftUI
import SwiftData

struct EditFastView: View {
    enum Mode {
        case edit(Fast)
        case add
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var end: Date
    @State private var isOpen: Bool
    @State private var note: String
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false

    private var store: FastStore { FastStore(context: modelContext) }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .edit(let fast):
            _start = State(initialValue: fast.start)
            _end = State(initialValue: fast.end ?? Date())
            _isOpen = State(initialValue: fast.isOpen)
            _note = State(initialValue: fast.note ?? "")
        case .add:
            let now = Date()
            _start = State(initialValue: now.addingTimeInterval(-16 * 3600))
            _end = State(initialValue: now)
            _isOpen = State(initialValue: false)
            _note = State(initialValue: "")
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    Toggle("Still in progress", isOn: $isOpen)
                    if !isOpen {
                        DatePicker("End", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if isEditing {
                    Section {
                        Button("Delete fast", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit fast" : "Add fast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .alert("Couldn’t save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog("Delete this fast?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteFast() }
            }
        }
    }

    private func save() {
        let resolvedEnd: Date? = isOpen ? nil : end
        do {
            switch mode {
            case .edit(let fast):
                try store.update(fast, start: start, end: resolvedEnd, note: note)
            case .add:
                try store.addManual(start: start, end: resolvedEnd, note: note)
            }
            dismiss()
        } catch let error as FastValidationError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFast() {
        if case .edit(let fast) = mode {
            store.delete(fast)
            dismiss()
        }
    }
}
