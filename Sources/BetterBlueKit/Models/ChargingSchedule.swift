//
//  ChargingSchedule.swift
//  BetterBlueKit
//
//  The off-peak charging window an EV keeps on board. Read from the
//  vehicle status; its hours are set with
//  `VehicleCommand.setChargingSchedule`.
//

import Foundation

// MARK: - Time of Day

/// A wall-clock time on the vehicle's own clock, with no date or zone.
public struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    /// 0–23.
    public var hour: Int
    /// 0–59.
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = ((hour % 24) + 24) % 24
        self.minute = ((minute % 60) + 60) % 60
    }

    public init(minutesSinceMidnight minutes: Int) {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        self.init(hour: wrapped / 60, minute: wrapped % 60)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// This time moved by `minutes`, wrapping past midnight.
    public func adding(minutes: Int) -> TimeOfDay {
        TimeOfDay(minutesSinceMidnight: minutesSinceMidnight + minutes)
    }

    /// The first moment at or after `date` showing this time.
    public func nextOccurrence(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        let components = DateComponents(hour: hour, minute: minute, second: 0)
        if let sameDay = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: date
        ), sameDay >= date {
            return sameDay
        }
        return calendar.nextDate(
            after: date, matching: components, matchingPolicy: .nextTime
        ) ?? date
    }

    /// Today's date at this time, in `calendar`'s zone.
    public func date(on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// The time in the user's locale ("11:30 PM", "23:30").
    public var localizedString: String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// The vehicle's 24-hour "HHmm" string, as schedule writes send it.
    public var hhmm: String { String(format: "%02d%02d", hour, minute) }

    /// Parses the vehicle's `{ "time": "hhmm", "timeSection": 0|1 }`
    /// shape: a 12-hour clock with `timeSection` 1 for PM. "1100" with
    /// section 1 is 11 PM, "1200" with section 0 is midnight. A value
    /// whose hour reads 13 or more is taken as 24-hour already, and
    /// "0000" is midnight either way. Some fields carry a stray fifth
    /// digit ("04300" for 4:30); only the first four count.
    public init?(vehicleTime raw: String, timeSection: Int?) {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 4,
              let hour = Int(digits.prefix(2)),
              let minute = Int(digits.dropFirst(2).prefix(2)),
              minute < 60, hour < 24 else { return nil }
        if hour >= 13 || timeSection == nil {
            self.init(hour: hour, minute: minute)
        } else {
            let base = hour % 12
            self.init(hour: timeSection == 1 ? base + 12 : base, minute: minute)
        }
    }
}

// MARK: - Charging Schedule

/// The vehicle's off-peak charging setting: the window it prefers to
/// charge in and how strictly it keeps to it. BetterBlue only changes the
/// window's hours. A client whose write covers more (Hyundai USA) reads
/// the rest from the vehicle at write time and sends it back unchanged.
public struct ChargingSchedule: Codable, Hashable, Sendable {

    /// How the vehicle treats its off-peak window.
    public enum OffPeakPreference: String, Codable, Sendable, CaseIterable {
        /// Charge in the window when it can, but outside it when that's
        /// what it takes to be ready by the departure time.
        case prioritize
        /// Charge only inside the window, even if that means leaving
        /// short of the target.
        case only
    }

    public struct OffPeakWindow: Codable, Hashable, Sendable {
        public var start: TimeOfDay
        public var end: TimeOfDay

        public init(start: TimeOfDay, end: TimeOfDay) {
            self.start = start
            self.end = end
        }
    }

    /// The window. Vehicles report it with off-peak charging off too.
    public var offPeakWindow: OffPeakWindow
    /// How the window is used, or nil when off-peak charging is off or
    /// the vehicle reported a value we don't recognize.
    public var offPeakPreference: OffPeakPreference?

    public init(offPeakWindow: OffPeakWindow, offPeakPreference: OffPeakPreference? = nil) {
        self.offPeakWindow = offPeakWindow
        self.offPeakPreference = offPeakPreference
    }

    /// Whether off-peak charging is on, i.e. the vehicle holds off for
    /// the window when plugged in outside it.
    public var offPeakEnabled: Bool { offPeakPreference != nil }

    /// When the next off-peak window opens, at or after `date`.
    public func nextOffPeakStart(onOrAfter date: Date, calendar: Calendar = .current) -> Date? {
        guard offPeakEnabled else { return nil }
        return offPeakWindow.start.nextOccurrence(onOrAfter: date, calendar: calendar)
    }
}

// MARK: - Weekday helpers

extension ChargingSchedule {
    /// Resolves a vehicle-reported weekday (0 = Sunday … 6 = Saturday)
    /// and time to the occurrence nearest `reference`, within half a week
    /// either side. Used for the estimated charge window, whose start can
    /// already be in the past once charging is under way.
    public static func nearestDate(
        weekday: Int,
        time: TimeOfDay,
        reference: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard (0...6).contains(weekday) else { return nil }
        // Calendar weekdays run 1 = Sunday … 7 = Saturday.
        let components = DateComponents(hour: time.hour, minute: time.minute, second: 0, weekday: weekday + 1)
        let searchStart = reference.addingTimeInterval(-3.5 * 86400)
        guard let candidate = calendar.nextDate(
            after: searchStart, matching: components, matchingPolicy: .nextTime
        ) else { return nil }
        // `candidate` is the first match in the week-wide window that
        // starts half a week back, so it's always the nearest one.
        return candidate
    }
}
