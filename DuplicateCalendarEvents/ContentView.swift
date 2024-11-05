//
//  ContentView.swift
//  DuplicateCalendarEvents
//
//  Created by cy on 2024/10/10.
//

import SwiftUI
import EventKit

struct EventWrapper: Identifiable, Hashable {
    let id = UUID()
    let event: EKEvent
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: EventWrapper, rhs: EventWrapper) -> Bool {
        lhs.id == rhs.id
    }
}

enum DuplicateSearchMode {
    case exact
    case sameDay
}

struct ContentView: View {
    @State private var events: [EventWrapper] = []
    @State private var selectedEvents = Set<EventWrapper>()
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isAllSelected = false
    @State private var includeBirthdayEvents = false
    @State private var searchMode: DuplicateSearchMode = .exact
    @State private var showingBirthdayInfo = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Settings")) {
                    Toggle("Include Birthday Events", isOn: $includeBirthdayEvents)
                    Picker("Search Mode", selection: $searchMode) {
                        Text("Exact Match").tag(DuplicateSearchMode.exact)
                        Text("Same Day").tag(DuplicateSearchMode.sameDay)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section(header: Text("Regular Events")) {
                    ForEach(events.filter { !isBirthdayEvent($0.event) }) { wrapper in
                        EventRow(event: wrapper.event, isSelected: selectedEvents.contains(wrapper))
                            .onTapGesture {
                                toggleSelection(for: wrapper)
                            }
                    }
                }

                if includeBirthdayEvents {
                    Section(header: Text("Birthday Events")) {
                        ForEach(events.filter { isBirthdayEvent($0.event) }) { wrapper in
                            EventRow(event: wrapper.event, isSelected: selectedEvents.contains(wrapper))
                                .onTapGesture {
                                    toggleSelection(for: wrapper)
                                }
                        }
                        
                        Text("Tip: Duplicate birthday events may occur if a contact appears in multiple groups.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top)
                        
                        Button(action: { showingBirthdayInfo = true }) {
                            Label("Why are there duplicate birthday events?", systemImage: "info.circle")
                        }
                    }
                }
            }
            .modifier(ListStyleModifier())
            .navigationTitle("Duplicate Events")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Find Duplicates") {
                        findDuplicates()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isAllSelected ? "Deselect All" : "Select All") {
                        selectAll()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete Selected") {
                        deleteSelectedEvents()
                    }
                    .disabled(selectedEvents.isEmpty)
                }
                 ToolbarItem(placement: .bottomBar) {
                    Button("Delete Selected") {
                        deleteSelectedEvents()
                    }
                    .disabled(selectedEvents.isEmpty)
                }
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Notice"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $showingBirthdayInfo) {
            BirthdayInfoView()
        }
    }

    func findDuplicates() {
        let eventStore = EKEventStore()
        
        eventStore.requestAccess(to: .event) { granted, error in
            if granted && error == nil {
                let calendars = eventStore.calendars(for: .event).filter { calendar in
                    if !self.includeBirthdayEvents && calendar.type == .birthday {
                        return false
                    }
                    return true
                }
                
                var allEvents: [EKEvent] = []
                
                let now = Date()
                let calendar = Calendar.current
                let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: now)!
                let twoYearsFromNow = calendar.date(byAdding: .year, value: 2, to: now)!
                
                for calendarItem in calendars {
                    let predicate = eventStore.predicateForEvents(withStart: twoYearsAgo, end: twoYearsFromNow, calendars: [calendarItem])
                    allEvents.append(contentsOf: eventStore.events(matching: predicate))
                }
                
                var duplicates: [EKEvent] = []
                
                // 处理事件查找重复的逻辑
                switch self.searchMode {
                case .exact:
                    // 精确匹配逻辑
                    for i in 0..<allEvents.count {
                        for j in (i+1)..<allEvents.count {
                            if allEvents[i].title == allEvents[j].title &&
                               allEvents[i].startDate == allEvents[j].startDate &&
                               allEvents[i].endDate == allEvents[j].endDate {
                                duplicates.append(allEvents[j])
                            }
                        }
                    }
                case .sameDay:
                    // 同一天匹配逻辑
                    var eventDict: [String: [EKEvent]] = [:]
                    for event in allEvents {
                        let key = "\(event.title ?? "")_\(calendar.startOfDay(for: event.startDate))"
                        if eventDict[key] == nil {
                            eventDict[key] = [event]
                        } else {
                            eventDict[key]?.append(event)
                            duplicates.append(contentsOf: eventDict[key]!)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.events = duplicates.map { EventWrapper(event: $0) }
                    let totalDuplicates = duplicates.count
                    let birthdayDuplicatesCount = duplicates.filter { isBirthdayEvent($0) }.count
                    self.alertMessage = "Found \(totalDuplicates) duplicate events (including \(birthdayDuplicatesCount) birthday events)"
                    self.showingAlert = true
                }
            } else {
                DispatchQueue.main.async {
                    self.alertMessage = "Unable to access calendar: \(error?.localizedDescription ?? "Unknown error")"
                    self.showingAlert = true
                }
            }
        }
    }

    func selectAll() {
        if isAllSelected {
            selectedEvents.removeAll()
        } else {
            selectedEvents = Set(events)
        }
        isAllSelected.toggle()
    }
    
    func toggleSelection(for wrapper: EventWrapper) {
        if selectedEvents.contains(wrapper) {
            selectedEvents.remove(wrapper)
        } else {
            selectedEvents.insert(wrapper)
        }
    }
    
    func deleteSelectedEvents() {
        let eventStore = EKEventStore()
        
        eventStore.requestAccess(to: .event) { granted, error in
            if granted && error == nil {
                var deletedCount = 0
                var failedDeletions = 0
                var birthdayEventsCount = 0
                
                for wrapper in self.selectedEvents {
                    if isBirthdayEvent(wrapper.event) {
                        birthdayEventsCount += 1
                        continue  // 跳过生日事件
                    }
                    
                    if let eventToDelete = eventStore.event(withIdentifier: wrapper.event.eventIdentifier ?? "") {
                        do {
                            try eventStore.remove(eventToDelete, span: .thisEvent)
                            deletedCount += 1
                        } catch {
                            print("Failed to delete event: \(error.localizedDescription)")
                            failedDeletions += 1
                        }
                    } else {
                        failedDeletions += 1
                    }
                }
                
                DispatchQueue.main.async {
                    self.events.removeAll { self.selectedEvents.contains($0) }
                    self.selectedEvents.removeAll()
                    
                    var message = "Deleted \(deletedCount) events. Failed to delete \(failedDeletions) events."
                    if birthdayEventsCount > 0 {
                        message += "\n\nNote: \(birthdayEventsCount) birthday events were not deleted as they are managed by the Contacts app."
                    }
                    self.alertMessage = message
                    self.showingAlert = true
                }
            } else {
                DispatchQueue.main.async {
                    self.alertMessage = "Unable to access calendar for deletion: \(error?.localizedDescription ?? "Unknown error")"
                    self.showingAlert = true
                }
            }
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct EventRow: View {
    let event: EKEvent
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(event.title ?? "Untitled Event")
                    .font(.headline)
                Text("\(formatDate(event.startDate)) - \(formatDate(event.endDate))")
                    .font(.subheadline)
                if isBirthdayEvent(event) {
                    Text("Cannot be deleted")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                if event.calendar == nil {
                    Text("Warning: No associated calendar")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
calendarInfoView()
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
    
    @ViewBuilder
    func calendarInfoView() -> some View {
        if let calendar = event.calendar {
            Text("Calendar: \(calendar.title.isEmpty ? "Untitled" : calendar.title) (\(calendarTypeString(calendar)))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Source: \(calendar.source?.title ?? "Unknown")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else {
            Text("Calendar: Not Available")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func printEventDetails() {
        print("Event Details:")
        print("  Title: \(event.title)")
        print("  Start: \(event.startDate)")
        print("  End: \(event.endDate)")
        print("  Calendar: \(event.calendar?.title ?? "N/A")")
        print("  Calendar Type: \(event.calendar?.type.rawValue ?? -1)")
        print("  Event Identifier: \(event.eventIdentifier ?? "N/A")")
        print("  Is Detached: \(event.isDetached)")
    }
    
    func calendarTypeString(_ calendar: EKCalendar) -> String {
        switch calendar.type {
        case .local:
            return "Local"
        case .calDAV:
            return "CalDAV"
        case .exchange:
            return "Exchange"
        case .subscription:
            return "Subscription"
        case .birthday:
            return "Birthdays"
        @unknown default:
            return "Unknown"
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

func isBirthdayEvent(_ event: EKEvent) -> Bool {
    guard let calendar = event.calendar else {
        return false // 如果日历为 nil，我们假设它不是生日事件
    }
    return calendar.type == .birthday
}

struct ListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.listStyle(SidebarListStyle())
        } else {
            content.listStyle(InsetGroupedListStyle())
        }
        #else
        content.listStyle(SidebarListStyle())
        #endif
    }
}


struct BirthdayInfoView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Birthday events are automatically created by the system based on your contact information. Duplicate birthday events may be caused by:")
                        .font(.body)
                    
                    Group {
                        Text("1. Duplicate contacts")
                        Text("2. The same contact appearing in multiple groups")
                        Text("3. Multiple birthday fields in contact information")
                    }
                    .font(.headline)
                    
                    Text("Steps to resolve:")
                        .font(.title2)
                    
                    Group {
                        Text("1. Open the Contacts app:")
                        Text("   - Find and tap the 'Contacts' icon on the home screen")
                        Text("   - Or open the 'Phone' app and tap the 'Contacts' tab at the bottom")
                        Text("   - You can also swipe down on the home screen to open Spotlight search and type 'Contacts'")
                        Text("   - Or open the 'Settings' app and scroll down to find 'Contacts'")
                        Text("2. Check for duplicate contacts and merge or delete any extras")
                        Text("3. Review the contact's group memberships:")
                        Text("   - Tap 'Groups' or 'Lists' at the top")
                        Text("   - Check if the same contact appears in multiple groups")
                        Text("   - Remove the contact from unnecessary groups if not needed")
                        Text("4. Edit contact information to ensure there is only one correct birthday date")
                        Text("5. After completing these steps, return to this app and recheck for duplicate events")
                    }
                    .font(.body)
                    
                    Spacer()
                    
                    Text("Note: Changes to contact information may take some time to update in the calendar. If you don't see changes immediately, please check again later.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("About Birthday Events")
        }
    }
}
