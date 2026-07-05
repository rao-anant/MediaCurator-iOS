import SwiftUI

/// Preview screen for hidden months (spec §5). Picking a month PREVIEWS its items in a grid
/// while it stays hidden; the only way to unhide is the explicit "Unhide this month" button.
/// No confirmation dialogs — switching months or leaving changes nothing.
struct HiddenView: View {

    @StateObject private var vm = HiddenViewModel()

    @State private var selectedYear: Int? = nil
    @State private var selectedMonthKey: String? = nil
    @State private var didAutoPreview = false

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        Group {
            if vm.months.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Hidden Months")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.load() }
        .onChange(of: vm.months.count) { _ in autoPreviewIfNeeded() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                yearMenu
                monthMenu
            }
            .padding()

            if let key = selectedMonthKey {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(vm.items(forMonth: key)) { item in
                            MediaThumbnailView(cell: .init(mediaItem: item, monthKey: key,
                                                           indexInMonth: 0, dateLabel: nil,
                                                           structuralVersion: 0)) {}
                        }
                    }
                    .padding(.horizontal, 2)
                }
            } else {
                Spacer()
                Text("Pick a year and month above to view it.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let key = selectedMonthKey {
                stillHiddenBar(key: key)
            }
        }
    }

    private func stillHiddenBar(key: String) -> some View {
        HStack {
            Text("\(Formatters.monthLabel(from: key)) · still hidden")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button("Unhide this month") {
                vm.unhide(key)
                selectedMonthKey = nil
                if let y = selectedYear, vm.months(in: y).isEmpty { selectedYear = nil }
            }
            .buttonStyle(.borderedProminent)
            .font(.subheadline)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var yearMenu: some View {
        Menu {
            ForEach(vm.years, id: \.self) { year in
                Button(String(year)) {
                    selectedYear = year
                    selectedMonthKey = vm.months(in: year).first?.key
                }
            }
        } label: {
            dropdownLabel(title: "Year", value: selectedYear.map(String.init) ?? "Select")
        }
    }

    private var monthMenu: some View {
        Menu {
            if let year = selectedYear {
                ForEach(vm.months(in: year)) { month in
                    Button("\(month.label) · \(Formatters.countShort(month.count)) items") {
                        selectedMonthKey = month.key
                    }
                }
            }
        } label: {
            dropdownLabel(title: "Month", value: selectedMonthLabel ?? "Select")
        }
        .disabled(selectedYear == nil)
    }

    private func dropdownLabel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Text(value).font(.subheadline)
                Spacer()
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash").font(.system(size: 52)).foregroundStyle(.secondary)
            Text("Nothing Hidden").font(.title3).bold()
            Text("You haven't hidden any months yet. Months you hide will appear here to bring back.")
                .multilineTextAlignment(.center)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(40)
    }

    private var selectedMonthLabel: String? {
        guard let key = selectedMonthKey else { return nil }
        return vm.months.first { $0.key == key }?.label
    }

    /// On first entry, auto-preview the most recently hidden month (still hidden) — spec §5.
    private func autoPreviewIfNeeded() {
        guard !didAutoPreview, selectedMonthKey == nil else { return }
        didAutoPreview = true
        if let last = vm.lastHiddenMonth, let y = Int(last.prefix(4)), vm.years.contains(y) {
            selectedYear = y
            selectedMonthKey = last
        }
    }
}
