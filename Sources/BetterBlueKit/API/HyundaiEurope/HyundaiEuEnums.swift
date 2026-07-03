//
//  HyundaiEuResponseKeys.swift
//  BetterBlueKit
//
//  Created by Martin Böhm on 29.04.26.
//

import Foundation

public enum HyEuResponseKeys: String, CaseIterable, Sendable {
    case vehicleState, syncDate, odo, soc, battery12v, chargeTime, isCharging, pluggedIn, engineOn
    case rangeTotal, rangeUnit, targetAC, targetDC, targetSocList, chargePowerStd, chargePowerFst
    case lock1L, lock1R, lock2L, lock2R, lockStatus
    case doorFrontLeft, doorFrontRight, doorRearLeft, doorRearRight
    case locationDate, trunk, hood, parkDate, locationLat, locationLon, parkLat, parkLon
    case airconSpeed, defrostOn, steeringWheelHeatOn, airTemp, tempUnit, airControlOn
    case tpmsFrontLeft, tpmsFrontRight, tpmsRearLeft, tpmsRearRight, tpmsStatus
}

public struct HyEuResponseKeyPathMap {
    public let apiProfile: HyEuAPIProfile

    public init(profile: HyEuAPIProfile) {
        self.apiProfile = profile
    }

    public subscript(key: HyEuResponseKeys) -> String? {
        HyEuResponseKeyPath.path(for: key, profile: apiProfile)
    }
}

public enum HyEuResponseKeyPath {
    private static let ccs2: [HyEuResponseKeys: String?] = [
        .vehicleState: "state.Vehicle",
        .syncDate: "lastUpdateTime",
        .odo: "Drivetrain.Odometer",
        .soc: "Green.BatteryManagement.BatteryRemain.Ratio",
        .battery12v: "Electronics.Battery.Level",
        .engineOn: "DrivingReady",
        .chargeTime: "Green.ChargingInformation.Charging.RemainTime",
        .isCharging: "Green.ChargingInformation.Charging.RemainTime",
        .pluggedIn: "Green.ChargingInformation.ConnectorFastening.State",
        .rangeTotal: "Drivetrain.FuelSystem.DTE.Total",
        .rangeUnit: "Drivetrain.FuelSystem.DTE.Unit",
        .targetAC: "Green.ChargingInformation.TargetSoC.Standard",
        .targetDC: "Green.ChargingInformation.TargetSoC.Quick",
        .chargePowerStd: "Green.Electric.SmartGrid.RealTimePower",
        .chargePowerFst: "Green.Electric.SmartGrid.RealTimePower",
        .lock1L: "Cabin.Door.Row1.Driver.Lock",
        .lock1R: "Cabin.Door.Row1.Passenger.Lock",
        .lock2L: "Cabin.Door.Row2.Left.Lock",
        .lock2R: "Cabin.Door.Row2.Right.Lock",
        .doorFrontLeft: "Cabin.Door.Row1.Driver.Open",
        .doorFrontRight: "Cabin.Door.Row1.Passenger.Open",
        .doorRearLeft: "Cabin.Door.Row2.Left.Open",
        .doorRearRight: "Cabin.Door.Row2.Right.Open",
        .trunk: "Body.Trunk.Open",
        .hood: "Body.Hood.Open",
        .locationDate: "Location.Date",
        .parkDate: "time",
        .locationLat: "Location.GeoCoord.Latitude",
        .locationLon: "Location.GeoCoord.Longitude",
        .parkLat: "coord.lat",
        .parkLon: "coord.lon",
        .airconSpeed: "Cabin.HVAC.Row1.Driver.Blower.SpeedLevel",
        .defrostOn: "Body.Windshield.Front.Defog.State",
        .steeringWheelHeatOn: "Cabin.SteeringWheel.Heat.State",
        .airTemp: "Cabin.HVAC.Row1.Driver.Temperature.Value",
        .tempUnit: "Cabin.HVAC.Row1.Driver.Temperature.Unit",
        .tpmsFrontLeft: "Chassis.Axle.Row1.Left.Tire.PressureLow",
        .tpmsFrontRight: "Chassis.Axle.Row1.Right.Tire.PressureLow",
        .tpmsRearLeft: "Chassis.Axle.Row2.Left.Tire.PressureLow",
        .tpmsRearRight: "Chassis.Axle.Row2.Right.Tire.PressureLow",
        .tpmsStatus: "Chassis.Axle.Tire.PressureLow"
    ]

    private static let legacy: [HyEuResponseKeys: String?] = [
        .vehicleState: "vehicleStatusInfo",
        .syncDate: "vehicleStatusInfo.vehicleStatus.time",
        .odo: "odometer.value",
        .soc: "vehicleStatus.evStatus.batteryStatus",
        .battery12v: "vehicleStatus.battery.batSoc",
        .engineOn: "vehicleStatus.engine",
        .chargeTime: "vehicleStatus.evStatus.remainTime2.atc.value",
        .isCharging: "vehicleStatus.evStatus.batteryCharge",
        .pluggedIn: "vehicleStatus.evStatus.batteryPlugin",
        .rangeTotal: "vehicleStatus.evStatus.drvDistance.0.rangeByFuel.evModeRange.value",
        .rangeUnit: "vehicleStatus.evStatus.drvDistance.0.rangeByFuel.evModeRange.unit",
        .targetSocList: "vehicleStatus.evStatus.reservChargeInfos.targetSOClist",
        .chargePowerStd: "vehicleStatus.evStatus.batteryPower.batteryStndChrgPower",
        .chargePowerFst: "vehicleStatus.evStatus.batteryPower.batteryFstChrgPower",
        .lockStatus: "vehicleStatus.doorLock",
        .doorFrontLeft: "vehicleStatus.doorOpen.frontLeft",
        .doorFrontRight: "vehicleStatus.doorOpen.frontRight",
        .doorRearLeft: "vehicleStatus.doorOpen.backLeft",
        .doorRearRight: "vehicleStatus.doorOpen.backRight",
        .trunk: "vehicleStatus.trunkOpen",
        .hood: "vehicleStatus.hoodOpen",
        .locationDate: "vehicleLocation.time",
        // Legacy /location/park nests everything under gpsDetail (observed
        // on a 2021 e-Niro), unlike CCS2 where coord/time sit at the root.
        // These were previously missing entirely, so the park branch of
        // parseLocation always produced (0, 0).
        .parkDate: "gpsDetail.time",
        .parkLat: "gpsDetail.coord.lat",
        .parkLon: "gpsDetail.coord.lon",
        .locationLat: "vehicleLocation.coord.lat",
        .locationLon: "vehicleLocation.coord.lon",
        .airControlOn: "vehicleStatus.airCtrlOn",
        .defrostOn: "vehicleStatus.defrost",
        .steeringWheelHeatOn: "vehicleStatus.steerWheelHeat",
        .airTemp: "vehicleStatus.airTemp.value",
        .tempUnit: "vehicleStatus.airTemp.unit",
        .tpmsFrontLeft: "vehicleStatus.tirePressureLamp.tirePressureLampFL",
        .tpmsFrontRight: "vehicleStatus.tirePressureLamp.tirePressureLampFR",
        .tpmsRearLeft: "vehicleStatus.tirePressureLamp.tirePressureLampRL",
        .tpmsRearRight: "vehicleStatus.tirePressureLamp.tirePressureLampRR",
        .tpmsStatus: "vehicleStatus.tirePressureLamp.tirePressureLampAll"
    ]

    static func path(for key: HyEuResponseKeys, profile: HyEuAPIProfile) -> String? {
        let table = .ccs2 == profile ? ccs2 : legacy
        return table[key] ?? nil
    }
}

public enum HyEuAPIProfile: Sendable {
    case legacy
    case ccs2
}

enum BluelinkDateParser {
    private static let formats = [
        "yyyyMMddHHmmss",
        "yyyyMMddHHmmss.SSS"
    ]

    static func parse(_ value: String?, timeZone: TimeZone? = nil) -> Date? {
        guard let value else { return nil }
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // 1) first fixed API formats (example: 20260517161031)
        for format in formats {
            let frmt = DateFormatter()
            frmt.locale = Locale(identifier: "en_US_POSIX")
            frmt.timeZone = timeZone ?? TimeZone(secondsFromGMT: 0)
            frmt.dateFormat = format
            if let date = frmt.date(from: raw) { return date }
        }

        // 2) next epoch if not an api format
        if raw.allSatisfy(\.isNumber), let timeStamp = Double(raw) {
            if raw.count == 13 { return Date(timeIntervalSince1970: timeStamp / 1000.0) } // ms
            if raw.count == 10 { return Date(timeIntervalSince1970: timeStamp) }          // s
        }

        return nil
    }
}
