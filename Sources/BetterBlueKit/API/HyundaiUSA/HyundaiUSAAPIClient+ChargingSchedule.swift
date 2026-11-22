//
//  HyundaiUSAAPIClient+ChargingSchedule.swift
//  BetterBlueKit
//
//  Hyundai USA charging schedules: read from `evStatus.reservChargeInfos`
//  in the vehicle status (`rcs/rvs/vehicleStatus`, the same response the
//  status already comes from), written whole with `evc/charge/reserv/set`.
//  BetterBlue only changes the off-peak start and stop. The write covers
//  the rest of the schedule too (preference, second off-peak slot,
//  departures), so it re-reads all of it from the cached status first and
//  sends it back as the car reported it.
//
//  No open-source client implements the US write; the shapes here come
//  from MyHyundai 5.4.5 traffic (Ioniq 5, gen 2, Nov 2026): opening the
//  Charging Schedule screen and moving the off-peak start to 11:30 PM.
//
//  The status and the write number the off-peak preference differently.
//  The car had "Prioritize charging for off-peak hours" selected the
//  whole time, reported it as `offPeakPowerFlag: 2`, and MyHyundai saved
//  it as `offPeakPowerFlag: 1`. "Charge only during off-peak hours" is
//  taken to be the other value each way, which also matches the write
//  numbering hyundai_kia_connect_api uses for Europe (1 prioritize,
//  2 only). Status times are 12-hour with a `timeSection` (1 = PM);
//  write times are 24-hour "HHmm".
//
//  The write takes the response time of the car itself: MyHyundai's took
//  13 and 31 seconds to come back, as the vehicle accepted the change.
//

import Foundation

extension HyundaiUSAAPIClient {

    // MARK: - Status → schedule

    /// The off-peak schedule in `reservChargeInfos`, or nil when the
    /// status carries no off-peak window (only `targetSOClist`, as
    /// `msa/iac/chargingStatus` does).
    nonisolated static func parseChargingSchedule(from reservChargeInfos: [String: Any]) -> ChargingSchedule? {
        guard let offPeakInfo = reservChargeInfos["offpeakPowerInfo"] as? [String: Any] else { return nil }
        let period = offPeakInfo["offPeakPowerTime1"] as? [String: Any] ?? [:]
        guard let start = vehicleTime(period["startTime"]), let end = vehicleTime(period["endTime"]) else { return nil }
        let flag: Int? = extractNumber(from: offPeakInfo["offPeakPowerFlag"])
        let preference: ChargingSchedule.OffPeakPreference? = switch flag {
        case 2: .prioritize
        case 1: .only
        default: nil
        }
        return ChargingSchedule(offPeakWindow: .init(start: start, end: end), offPeakPreference: preference)
    }

    /// The vehicle's estimate of its charge window (`ect`), resolved to
    /// dates near `reference`. `day` 7 and garbled times ("19630") show up
    /// when nothing is scheduled; those come back nil.
    nonisolated static func parseEstimatedChargeWindow(
        from reservChargeInfos: [String: Any],
        reference: Date,
        calendar: Calendar = .current
    ) -> (start: Date?, end: Date?) {
        guard let ect = reservChargeInfos["ect"] as? [String: Any] else { return (nil, nil) }
        func resolve(_ value: Any?) -> Date? {
            guard let point = value as? [String: Any],
                  let day: Int = extractNumber(from: point["day"]),
                  let time = vehicleTime(point["time"]) else { return nil }
            return ChargingSchedule.nearestDate(weekday: day, time: time, reference: reference, calendar: calendar)
        }
        let start = resolve(ect["start"])
        var end = resolve(ect["end"])
        if let startDate = start, let endDate = end, endDate <= startDate {
            end = nil
        }
        return (start, end)
    }

    /// A departure slot as the status reports it, read only to send it
    /// back unchanged in a schedule write.
    struct Departure: Equatable {
        var chargingEnabled: Bool
        var time: TimeOfDay
        /// 0 = Sunday … 6 = Saturday.
        var days: [Int]
        var climateOn: Bool
        var defrost: Bool
        /// As reported ("73.0").
        var temperatureValue: String?
        /// 1 = °F.
        var temperatureUnit: Int?
    }

    nonisolated static func parseDepartures(from reservChargeInfos: [String: Any]) -> [Departure] {
        ["reservChargeInfo", "reserveChargeInfo2"].compactMap { key in
            (reservChargeInfos[key] as? [String: Any]).flatMap(parseDeparture)
        }
    }

    private nonisolated static func parseDeparture(_ info: [String: Any]) -> Departure? {
        guard let detail = info["reservChargeInfoDetail"] as? [String: Any],
              let reservInfo = detail["reservInfo"] as? [String: Any],
              let time = vehicleTime(reservInfo["time"]) else { return nil }
        let climate = detail["reservFatcSet"] as? [String: Any] ?? [:]
        let airTemp = climate["airTemp"] as? [String: Any] ?? [:]
        let airCtrl: Int = extractNumber(from: climate["airCtrl"]) ?? 0
        let days = (reservInfo["day"] as? [Any] ?? []).compactMap { extractNumber(from: $0) as Int? }
        return Departure(
            chargingEnabled: detail["reservChargeSet"] as? Bool ?? false,
            time: time,
            days: days.isEmpty ? Array(0...6) : days,
            climateOn: airCtrl != 0,
            defrost: climate["defrost"] as? Bool ?? false,
            temperatureValue: airTemp["value"].map { "\($0)" },
            temperatureUnit: extractNumber(from: airTemp["unit"])
        )
    }

    /// `{ "time": "1100", "timeSection": 1 }` → 23:00.
    private nonisolated static func vehicleTime(_ value: Any?) -> TimeOfDay? {
        guard let dict = value as? [String: Any], let raw = dict["time"] else { return nil }
        return TimeOfDay(vehicleTime: "\(raw)", timeSection: extractNumber(from: dict["timeSection"]))
    }

    // MARK: - Schedule → write body

    private nonisolated static let weekdayNames = [
        "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"
    ]

    /// The `evc/charge/reserv/set` body: the new off-peak hours, and
    /// everything else as the car has it now (`current`, its
    /// `reservChargeInfos`). The write replaces the whole schedule, so the
    /// preference, the second off-peak slot and the departures go back as
    /// reported. It has room for one departure's days and climate; the
    /// second departure contributes only its time (`endTime`), which is
    /// what MyHyundai sent.
    ///
    /// Throws if the car reports an off-peak preference this doesn't
    /// recognize, rather than send a different one.
    nonisolated static func chargingScheduleBody(
        window: ChargingSchedule.OffPeakWindow,
        current: [String: Any]
    ) throws -> [String: Any] {
        let departures = parseDepartures(from: current)
        let departure = departures.first
        let second = departures.dropFirst().first
        let reservFlag: Int = extractNumber(from: current["reservFlag"]) ?? 0
        let offPeakInfo = current["offpeakPowerInfo"] as? [String: Any] ?? [:]

        // The status and the write number the preference the other way
        // round (see the header).
        let reportedFlag: Int = extractNumber(from: offPeakInfo["offPeakPowerFlag"]) ?? 0
        let offPeakFlag: Int
        switch reportedFlag {
        case 0: offPeakFlag = 0
        case 1: offPeakFlag = 2
        case 2: offPeakFlag = 1
        default:
            throw APIError.logError(
                "The vehicle reported an off-peak setting BetterBlue doesn't recognize (\(reportedFlag))",
                apiName: "HyundaiUSA"
            )
        }

        let period: [String: Any] = ["startTime": window.start.hhmm, "endTime": window.end.hhmm]
        // MyHyundai copies the one window it shows into the second slot.
        // Send the second slot back as the car has it instead, falling
        // back to the new hours if the car didn't report one.
        let secondPeriod: [String: Any] = {
            let reported = offPeakInfo["offPeakPowerTime2"] as? [String: Any] ?? [:]
            guard let start = vehicleTime(reported["startTime"]),
                  let end = vehicleTime(reported["endTime"]) else { return period }
            return ["startTime": start.hhmm, "endTime": end.hhmm]
        }()
        let temperatureValue = departure?.temperatureValue
            .flatMap(Double.init)
            .map { String(Int($0.rounded())) } ?? "72"

        return [
            "airCtrl": departure?.climateOn == true ? 1 : 0,
            "airTemp": ["value": temperatureValue, "unit": departure?.temperatureUnit ?? 1],
            "alarmTime": 0,
            "chargeSet": departure?.chargingEnabled ?? false,
            "day": (departure?.days ?? Array(0...6))
                .filter { (0...6).contains($0) }
                .map { weekdayNames[$0] },
            "defrost": departure?.defrost ?? false,
            "endTime": second?.time.hhmm ?? "0000",
            "offpeakPowerInfo": [
                "offPeakPowerFlag": offPeakFlag,
                "offPeakPowerTime1": period,
                "offPeakPowerTime2": secondPeriod
            ],
            "reservFlag": reservFlag == 1 ? 1 : 0,
            "startTime": departure?.time.hhmm ?? "0000"
        ]
    }

    /// The local UTC offset in whole hours, as MyHyundai sends it ("-6"
    /// in CST). Schedule times are wall-clock times, so the write carries
    /// the phone's offset rather than the client's fixed "-5".
    nonisolated static func localOffsetHeader(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        String(timeZone.secondsFromGMT(for: now) / 3600)
    }
}
