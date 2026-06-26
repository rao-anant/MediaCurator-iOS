import SwiftUI

/// Manage months marked done — pick a Year, then a Month, and unhide it.
/// Mirrors Android's `HiddenActivity`.
struct HiddenView: View {

    @StateObject private var vm = HiddenViewModel()

    @State private var selectedYear: Int? = nil
    @State private var selectedMonthKey: String? = nil
    @State private var lastUnhidden: String? = nil   // label of the just-unhidden month

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
        .onAppear {
            vm.load()
        }
        .onChange(of: vm.months.count) { _ in syncSelection() }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Two dropdowns: Year then Month.
            HStack(spacing: 12) {
                yearMenu
                monthMenu
            }

            // Unhide action for the selected month (stays available for the next one).
            Button {
                unhideSelected()
            } label: {
                Label("Unhide", systemImage: "eye")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedMonthKey == nil)

            if let label = lastUnhidden {
                Text("\(label) unhidden — it's back in the gallery.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            // The selected year's hidden months, auto-shown.
            if let year = selectedYear {
                List {
                    Section("Hidden in \(String(year))") {
                        ForEach(vm.months(in: year)) { month in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(month.label).font(.subheadline).bold()
                                    Text("\(Formatters.countShort(month.count)) items · \(Formatters.bytes(month.totalBytes))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedMonthKey == month.key {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedMonthKey = month.key }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            Spacer()
        }
        .padding()
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
            dropdownLabel(title: "Year",
                          value: selectedYear.map(String.init) ?? "Select")
        }
    }

    private var monthMenu: some View {
        Menu {
            if let year = selectedYear {
                ForEach(vm.months(in: year)) { month in
                    Button(month.label) { selectedMonthKey = month.key }
                }
            }
        } label: {
            dropdownLabel(title: "Month",
                          value: selectedMonthLabel ?? "Select")
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
            Text("Months you mark done in the gallery appear here, where you can bring them back.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    // MARK: - Helpers

    private var selectedMonthLabel: String? {
        guard let key = selectedMonthKey else { return nil }
        return vm.months.first { $0.key == key }?.label
    }

    private func unhideSelected() {
        guard let key = selectedMonthKey else { return }
        lastUnhidden = vm.months.first { $0.key == key }?.label
        vm.unhide(key)
        // syncSelection runs via onChange(of: months.count)
    }

    /// Keep the year/month selection valid after the month list changes.
    /// On first land, jump to the month the user most recently hid (a handy "which month did
    /// I just hide?" shortcut); afterwards keep the current selection valid.
    private func syncSelection() {
        if selectedYear == nil, let last = vm.lastHiddenMonth,
           let y = Int(last.prefix(4)), vm.years.contains(y) {
            selectedYear = y
            selectedMonthKey = last
            return
        }
        if selectedYear == nil || !vm.years.contains(selectedYear!) {
            selectedYear = vm.years.first
        }
        if let year = selectedYear {
            let monthsInYear = vm.months(in: year)
            if selectedMonthKey == nil || !monthsInYear.contains(where: { $0.key == selectedMonthKey }) {
                selectedMonthKey = monthsInYear.first?.key
            }
        } else {
            selectedMonthKey = nil
        }
    }
}
