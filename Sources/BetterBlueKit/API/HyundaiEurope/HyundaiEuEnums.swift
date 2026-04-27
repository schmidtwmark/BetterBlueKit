//
//  HyundaiEuResponseKeys.swift
//  BetterBlueKit
//
//  Created by Martin Böhm on 29.04.26.
//

import Foundation

public enum HyEuResponseKeys: String, CaseIterable, Sendable {
    case vehicleState, syncDate, odo, soc, battery12v, chargeTime, isCharging, pluggedIn
    case rangeTotal, rangeUnit, targetAC, targetDC, targetSocList, chargePower
    case lock1L, lock1R, lock2L, lock2R, lockStatus
    case doorFrontLeft, doorFrontRight, doorRearLeft, doorRearRight
    case locationDate, trunk, hood, parkDate, locationLat, locationLon, parkLat, parkLon
    case airconSpeed, defrostOn, steeringWheelHeatOn, airTemp, tempUnit
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
        .chargeTime: "Green.ChargingInformation.Charging.RemainTime",
        .isCharging: "Green.ChargingInformation.Charging.RemainTime",
        .pluggedIn: "Green.ChargingInformation.ConnectorFastening.State",
        .rangeTotal: "Drivetrain.FuelSystem.DTE.Total",
        .rangeUnit: "Drivetrain.FuelSystem.DTE.Unit",
        .targetAC: "Green.ChargingInformation.TargetSoC.Standard",
        .targetDC: "Green.ChargingInformation.TargetSoC.Quick",
        .chargePower: "Green.Electric.SmartGrid.RealTimePower",
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
        .vehicleState: "vehicleStatusInfo.vehicleStatus",
        .syncDate: "time",
        .odo: "odometer.value",
        .soc: "evStatus.batteryStatus",
        .battery12v: "battery.batSoc",
        .chargeTime: "evStatus.remainTime2.atc.value",
        .isCharging: "evStatus.batteryCharge",
        .pluggedIn: "evStatus.batteryPlugin",
        .rangeTotal: "evStatus.drvDistance.0.rangeByFuel.evModeRange.value",
        .rangeUnit: "evStatus.drvDistance.0.rangeByFuel.evModeRange.unit",
        .targetSocList: "evStatus.reservChargeInfos.targetSOClist",
        .chargePower: "batteryPower.batteryStndChrgPower",
        .lockStatus: "doorLock",
        .doorFrontLeft: "doorOpen.frontLeft",
        .doorFrontRight: "doorOpen.frontRight",
        .doorRearLeft: "doorOpen.backLeft",
        .doorRearRight: "doorOpen.backRight",
        .trunk: "trunkOpen",
        .hood: "hoodOpen",
        .defrostOn: "defrost",
        .steeringWheelHeatOn: "steerWheelHeat",
        .airTemp: "airTemp.value",
        .tempUnit: "airTemp.unit",
        .tpmsFrontLeft: "tirePressureLamp.tirePressureLampFL",
        .tpmsFrontRight: "tirePressureLamp.tirePressureLampFR",
        .tpmsRearLeft: "tirePressureLamp.tirePressureLampRL",
        .tpmsRearRight: "tirePressureLamp.tirePressureLampRR",
        .tpmsStatus: "tirePressureLamp.tirePressureLampAll"
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
