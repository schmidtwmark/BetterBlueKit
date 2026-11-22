//
//  HyundaiUSAChargingScheduleTests.swift
//  BetterBlueKit
//
//  Hyundai USA charging schedules: `reservChargeInfos` parsing, the
//  estimated charge window, and the `evc/charge/reserv/set` body. The
//  fixtures are an Ioniq 5's real payloads, trimmed to the fields read
//  here: plugged in at 6:25 PM waiting for an 11 PM off-peak start, and
//  unplugged the next evening. The expected write body is MyHyundai's
//  own, captured moving the off-peak start to 11:30 PM.
//

import Foundation
import Testing
@testable import BetterBlueKit

enum HyundaiUSAScheduleSampleJSON {

    /// Plugged in Saturday 6:25 PM CST, waiting for off-peak at 11 PM.
    /// The car estimates the charge at Sat 11:00 PM → Sun 4:30 AM
    /// ("04300" — a stray fifth digit it really sends).
    static let waitingReservChargeInfos = """
    {
      "ect": {
        "start": { "day": 6, "time": { "time": "1100", "timeSection": 1 } },
        "end": { "day": 0, "time": { "time": "04300", "timeSection": 0 } }
      },
      "offpeakPowerInfo": {
        "offPeakPowerFlag": 2,
        "offPeakPowerTime1": {
          "startTime": { "time": "1100", "timeSection": 1 },
          "endTime": { "time": "0700", "timeSection": 0 }
        },
        "offPeakPowerTime2": {
          "startTime": { "time": "0000", "timeSection": 0 },
          "endTime": { "time": "0700", "timeSection": 0 }
        }
      },
      "reservChargeInfo": {
        "dateTime": "2026/11/07T16:39:20Z",
        "reservChargeInfoDetail": {
          "reservChargeSet": true,
          "reservFatcSet": { "airCtrl": 0, "airTemp": { "unit": 1, "value": "73.0" }, "defrost": false },
          "reservInfo": { "day": [0, 1, 2, 3, 4, 5, 6], "time": { "time": "0700", "timeSection": 0 } }
        }
      },
      "reservFlag": 1,
      "reserveChargeInfo2": {
        "reservChargeInfoDetail": {
          "reservChargeSet": false,
          "reservFatcSet": { "airCtrl": 0, "airTemp": { "unit": 1, "value": "73.0" }, "defrost": false },
          "reservInfo": { "day": [0, 1, 2, 3, 4, 5, 6], "time": { "time": "0000", "timeSection": 0 } }
        }
      },
      "targetSOClist": [
        { "plugType": 0, "targetSOClevel": 90 },
        { "plugType": 1, "targetSOClevel": 90 }
      ]
    }
    """

    /// Unplugged the next day: `ect` turns to day 7 and nonsense.
    static let unpluggedEct = """
    {
      "start": { "day": 7, "time": { "timeSection": 0, "time": "0000" } },
      "end": { "day": 7, "time": { "timeSection": 1, "time": "19630" } }
    }
    """

    static func status(plugged: Bool, ect: String? = nil) -> String {
        var reserv = waitingReservChargeInfos
        if let ect,
           var dict = (try? JSONSerialization.jsonObject(with: Data(waitingReservChargeInfos.utf8))) as? [String: Any],
           let ectObject = try? JSONSerialization.jsonObject(with: Data(ect.utf8)) {
            dict["ect"] = ectObject
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                reserv = String(decoding: data, as: UTF8.self)
            }
        }
        return HyundaiUSAStatusSampleJSON.response(vehicleStatus: """
        {
          "dateTime": "2026-11-08T00:25:31Z",
          "doorLock": true,
          "evStatus": {
            "batteryCharge": \(plugged),
            "batteryPlugin": \(plugged ? 2 : 0),
            "batteryStatus": \(plugged ? 28 : 87),
            "drvDistance": [
              { "rangeByFuel": {
                  "evModeRange": { "unit": 3, "value": 117 },
                  "totalAvailableRange": { "unit": 3, "value": 117 } }, "type": 0 }
            ],
            "remainTime2": { "atc": { "unit": 1, "value": 0 } },
            "reservChargeInfos": \(reserv)
          }
        }
        """)
    }
}

@Suite("Hyundai USA Charging Schedule")
struct HyundaiUSAChargingScheduleTests {

    @MainActor private func makeClient(brand: Brand = .hyundai) -> HyundaiUSAAPIClient {
        HyundaiUSAAPIClient(configuration: APIClientConfiguration(
            region: .usa, brand: brand, username: "test@example.com",
            password: "password123", pin: "1234", accountId: UUID()
        ))
    }

    private func makeVehicle() -> Vehicle {
        Vehicle(
            vin: "KM8KRDDF0SU000000", regId: "REG", model: "IONIQ 5",
            accountId: UUID(), fuelType: .electric, generation: 2,
            odometer: Distance(length: 1000, units: .miles)
        )
    }

    @MainActor private func parse(_ json: String) throws -> VehicleStatus.EVStatus {
        let status = try makeClient().parseVehicleStatusResponse(Data(json.utf8), for: makeVehicle())
        return try #require(status.evStatus)
    }

    private func reservDict(_ json: String = HyundaiUSAScheduleSampleJSON.waitingReservChargeInfos) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    // MARK: Time parsing

    @Test("Vehicle times read as a 12-hour clock with timeSection for PM",
          arguments: [
            ("1100", 1, 23, 0), ("0700", 0, 7, 0), ("1200", 0, 0, 0), ("1200", 1, 12, 0),
            ("0000", 0, 0, 0), ("04300", 0, 4, 30), ("0130", 1, 13, 30)
          ])
    func vehicleTime(raw: String, section: Int, hour: Int, minute: Int) throws {
        let time = try #require(TimeOfDay(vehicleTime: raw, timeSection: section))
        #expect(time == TimeOfDay(hour: hour, minute: minute))
    }

    @Test("24-hour and garbled vehicle times")
    func vehicleTimeEdges() {
        #expect(TimeOfDay(vehicleTime: "2330", timeSection: 0) == TimeOfDay(hour: 23, minute: 30))
        #expect(TimeOfDay(vehicleTime: "2330", timeSection: nil) == TimeOfDay(hour: 23, minute: 30))
        #expect(TimeOfDay(vehicleTime: "19630", timeSection: 1) == nil)
        #expect(TimeOfDay(vehicleTime: "7", timeSection: 0) == nil)
        #expect(TimeOfDay(hour: 23, minute: 30).hhmm == "2330")
        #expect(TimeOfDay(hour: 23, minute: 30).adding(minutes: 45) == TimeOfDay(hour: 0, minute: 15))
    }

    // MARK: Schedule parsing

    @Test("The off-peak window and preference come from reservChargeInfos")
    func parsesSchedule() throws {
        let schedule = try #require(HyundaiUSAAPIClient.parseChargingSchedule(from: reservDict()))
        #expect(schedule.offPeakWindow == .init(start: TimeOfDay(hour: 23, minute: 0), end: TimeOfDay(hour: 7, minute: 0)))
        // Status flag 2 is "Prioritize charging for off-peak hours" — what
        // MyHyundai showed selected for this car.
        #expect(schedule.offPeakPreference == .prioritize)
        #expect(schedule.offPeakEnabled)
    }

    @Test("Departures are read for the write to send back")
    func parsesDepartures() throws {
        let departures = HyundaiUSAAPIClient.parseDepartures(from: try reservDict())
        #expect(departures.count == 2)
        #expect(departures[0].chargingEnabled)
        #expect(departures[0].time == TimeOfDay(hour: 7, minute: 0))
        #expect(departures[0].days == Array(0...6))
        #expect(departures[0].temperatureValue == "73.0")
        #expect(departures[0].temperatureUnit == 1)
        #expect(!departures[0].climateOn)
        #expect(!departures[1].chargingEnabled)
        #expect(departures[1].time == TimeOfDay(hour: 0, minute: 0))
    }

    @Test("A targets-only reservChargeInfos has no schedule")
    func targetsOnly() throws {
        let dict = try reservDict(#"{ "targetSOClist": [{ "plugType": 1, "targetSOClevel": 90 }] }"#)
        #expect(HyundaiUSAAPIClient.parseChargingSchedule(from: dict) == nil)
    }

    @Test("Status flag 1 is off-peak only; anything else leaves the preference unknown")
    func preferenceFlags() throws {
        for (flag, expected) in [(1, ChargingSchedule.OffPeakPreference.only), (0, nil), (5, nil)] {
            let json = HyundaiUSAScheduleSampleJSON.waitingReservChargeInfos
                .replacingOccurrences(of: "\"offPeakPowerFlag\": 2", with: "\"offPeakPowerFlag\": \(flag)")
            let schedule = HyundaiUSAAPIClient.parseChargingSchedule(from: try reservDict(json))
            #expect(schedule?.offPeakPreference == expected)
        }
    }

    // MARK: Waiting + estimated window

    @Test("Plugged in waiting: flagged as waiting, with the car's estimated window")
    @MainActor func waitingStatus() throws {
        let ev = try parse(HyundaiUSAScheduleSampleJSON.status(plugged: true))
        #expect(!ev.charging)
        #expect(ev.isWaitingForScheduledCharge)
        #expect(ev.chargingSchedule?.offPeakPreference == .prioritize)

        let calendar = Calendar.current
        let reference = try #require(ISO8601DateFormatter().date(from: "2026-11-08T00:25:31Z"))
        let start = try #require(ev.estimatedChargeStart)
        let end = try #require(ev.estimatedChargeEnd)
        #expect(calendar.component(.weekday, from: start) == 7) // Saturday
        #expect(calendar.component(.hour, from: start) == 23)
        #expect(calendar.component(.weekday, from: end) == 1) // Sunday
        #expect(calendar.component(.hour, from: end) == 4)
        #expect(calendar.component(.minute, from: end) == 30)
        #expect(end > start)
        #expect(abs(start.timeIntervalSince(reference)) < 3.5 * 86400)
    }

    @Test("expectedChargeStart prefers the car's estimate, then the next off-peak start")
    @MainActor func expectedStart() throws {
        let ev = try parse(HyundaiUSAScheduleSampleJSON.status(plugged: true))
        let estimate = try #require(ev.estimatedChargeStart)
        #expect(ev.expectedChargeStart(after: estimate.addingTimeInterval(-3600)) == estimate)

        // Past the estimate, fall back to the window's next opening.
        let later = estimate.addingTimeInterval(2 * 3600)
        let next = try #require(ev.expectedChargeStart(after: later))
        #expect(next > later)
        #expect(Calendar.current.component(.hour, from: next) == 23)
    }

    @Test("Unplugged: no estimated window from the day-7 placeholder, schedule still read")
    @MainActor func unplugged() throws {
        let ev = try parse(HyundaiUSAScheduleSampleJSON.status(
            plugged: false, ect: HyundaiUSAScheduleSampleJSON.unpluggedEct
        ))
        #expect(!ev.isWaitingForScheduledCharge)
        #expect(ev.estimatedChargeStart == nil)
        #expect(ev.estimatedChargeEnd == nil)
        #expect(ev.chargingSchedule?.offPeakWindow.start == TimeOfDay(hour: 23, minute: 0))
    }

    // MARK: Write body

    @Test("Moving the window to 11:30 PM writes MyHyundai's body, minus its slip-ups")
    func writeBodyMatchesMyHyundai() throws {
        let window = ChargingSchedule.OffPeakWindow(
            start: TimeOfDay(hour: 23, minute: 30), end: TimeOfDay(hour: 7, minute: 0)
        )
        let body = try HyundaiUSAAPIClient.chargingScheduleBody(window: window, current: try reservDict())

        #expect(body["airCtrl"] as? Int == 0)
        #expect(body["alarmTime"] as? Int == 0)
        #expect(body["chargeSet"] as? Bool == true)
        #expect(body["defrost"] as? Bool == false)
        #expect(body["reservFlag"] as? Int == 1)
        #expect(body["startTime"] as? String == "0700")
        #expect(body["endTime"] as? String == "0000")
        #expect(Set(body["day"] as? [String] ?? []) == [
            "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"
        ])
        // The car's own 73°; MyHyundai sent 72 from its own settings.
        let airTemp = try #require(body["airTemp"] as? [String: Any])
        #expect(airTemp["value"] as? String == "73")
        #expect(airTemp["unit"] as? Int == 1)

        let offPeak = try #require(body["offpeakPowerInfo"] as? [String: Any])
        // Prioritize goes out as 1 even though the status said 2.
        #expect(offPeak["offPeakPowerFlag"] as? Int == 1)
        #expect(offPeak["offPeakPowerTime1"] as? [String: String] == ["startTime": "2330", "endTime": "0700"])
        // The second slot as the car reported it (MyHyundai overwrote it
        // with the first).
        #expect(offPeak["offPeakPowerTime2"] as? [String: String] == ["startTime": "0000", "endTime": "0700"])
    }

    @Test("The car's off-peak preference goes back in write numbering; an unknown one refuses the write")
    func writeKeepsPreference() throws {
        let window = ChargingSchedule.OffPeakWindow(start: TimeOfDay(hour: 22, minute: 0), end: TimeOfDay(hour: 6, minute: 0))
        for (reported, written) in [(2, 1), (1, 2), (0, 0)] {
            var current = try reservDict()
            var offPeakInfo = try #require(current["offpeakPowerInfo"] as? [String: Any])
            offPeakInfo["offPeakPowerFlag"] = reported
            current["offpeakPowerInfo"] = offPeakInfo
            let body = try HyundaiUSAAPIClient.chargingScheduleBody(window: window, current: current)
            let offPeak = body["offpeakPowerInfo"] as? [String: Any]
            #expect(offPeak?["offPeakPowerFlag"] as? Int == written)
        }

        var current = try reservDict()
        var offPeakInfo = try #require(current["offpeakPowerInfo"] as? [String: Any])
        offPeakInfo["offPeakPowerFlag"] = 5
        current["offpeakPowerInfo"] = offPeakInfo
        #expect(throws: APIError.self) {
            try HyundaiUSAAPIClient.chargingScheduleBody(window: window, current: current)
        }
    }

    @Test("Everything but the window comes from the car's current schedule")
    func writeKeepsCurrent() throws {
        let window = ChargingSchedule.OffPeakWindow(start: TimeOfDay(hour: 22, minute: 0), end: TimeOfDay(hour: 6, minute: 0))
        var current = try reservDict()
        current["reservFlag"] = 0
        let body = try HyundaiUSAAPIClient.chargingScheduleBody(window: window, current: current)
        #expect(body["reservFlag"] as? Int == 0)
        #expect(body["startTime"] as? String == "0700")
        let offPeak = try #require(body["offpeakPowerInfo"] as? [String: Any])
        #expect(offPeak["offPeakPowerTime1"] as? [String: String] == ["startTime": "2200", "endTime": "0600"])
    }

    @Test("Without a reported second slot, the new hours fill it")
    func writeFillsMissingSecondSlot() throws {
        let window = ChargingSchedule.OffPeakWindow(start: TimeOfDay(hour: 22, minute: 0), end: TimeOfDay(hour: 6, minute: 0))
        var current = try reservDict()
        var offPeakInfo = try #require(current["offpeakPowerInfo"] as? [String: Any])
        offPeakInfo.removeValue(forKey: "offPeakPowerTime2")
        current["offpeakPowerInfo"] = offPeakInfo
        let body = try HyundaiUSAAPIClient.chargingScheduleBody(window: window, current: current)
        let offPeak = try #require(body["offpeakPowerInfo"] as? [String: Any])
        #expect(offPeak["offPeakPowerTime2"] as? [String: String] == ["startTime": "2200", "endTime": "0600"])
    }

    @Test("The offset header is the local UTC offset in hours")
    func offsetHeader() throws {
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        let november = try #require(ISO8601DateFormatter().date(from: "2026-11-09T04:46:18Z"))
        #expect(HyundaiUSAAPIClient.localOffsetHeader(now: november, timeZone: chicago) == "-6")
    }

    // MARK: Support

    @Test("Hyundai USA declares the feature; Genesis USA refuses the write before any request")
    @MainActor func support() async throws {
        #expect(makeClient().supportsChargingSchedule())
        let genesis = makeClient(brand: .genesis)
        #expect(!genesis.supportsChargingSchedule())
        await #expect(throws: APIError.self) {
            try await genesis.sendCommand(
                for: makeVehicle(),
                command: .setChargingSchedule(.init(
                    start: TimeOfDay(hour: 23, minute: 0), end: TimeOfDay(hour: 7, minute: 0)
                )),
                authToken: AuthToken(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)
            )
        }
    }

    @Test("EVStatus saved before the schedule fields still decodes")
    func legacyDecode() throws {
        let ev = VehicleStatus.EVStatus(
            charging: false, chargeSpeed: 0,
            evRange: .init(range: Distance(length: 100, units: .miles), percentage: 50),
            chargeTime: .seconds(0)
        )
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ev)) as? [String: Any])
        for key in [
            "offPeakStartMinutes", "offPeakEndMinutes", "maybeOffPeakPreference",
            "waitingForScheduledCharge", "estimatedChargeStart", "estimatedChargeEnd"
        ] {
            json.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(
            VehicleStatus.EVStatus.self, from: JSONSerialization.data(withJSONObject: json)
        )
        #expect(decoded.chargingSchedule == nil)
        #expect(!decoded.isWaitingForScheduledCharge)
    }

    @Test("The schedule survives an EVStatus encode/decode round trip")
    func scheduleRoundTrip() throws {
        let schedule = try #require(HyundaiUSAAPIClient.parseChargingSchedule(from: reservDict()))
        var ev = VehicleStatus.EVStatus(
            charging: false, chargeSpeed: 0,
            evRange: .init(range: Distance(length: 100, units: .miles), percentage: 50),
            plugType: .acCharger,
            chargeTime: .seconds(0),
            chargingSchedule: schedule,
            waitingForScheduledCharge: true
        )
        let decoded = try JSONDecoder().decode(VehicleStatus.EVStatus.self, from: JSONEncoder().encode(ev))
        #expect(decoded.chargingSchedule == schedule)
        #expect(decoded == ev)
        ev.chargingSchedule = nil
        #expect(ev.chargingSchedule == nil)
    }
}
