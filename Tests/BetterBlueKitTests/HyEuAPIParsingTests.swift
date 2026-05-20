//
//  KiaSampleJSON.swift
//  BetterBlueKit
//
//  Created by Martin Böhm on 19.05.26.
//


//
//  KiaAPIParsingTests.swift
//  BetterBlueKit
//
//  Tests for Kia API client functionality
//
//  Note: Parsing tests have been removed as the parsing methods are now
//  private implementation details of KiaUSAAPIClient. This file retains
//  sample JSON data for documentation and integration testing reference.
//

import Foundation
import Testing
@testable import BetterBlueKit

// MARK: - Sample JSON Data

/// Sample Kia API JSON responses for documentation and testing reference
enum HyEuSampleJSON {

    /// Sample vehicle status response from Hyundai EU API for Gen5W
    static let vehicleStatusGen5W = """
    {
      "resMsg": {
        "vehicleStatusInfo": {
          "vehicleLocation": {
            "coord": {
              "lat": 51.181234,
              "lon": 5.541234,
              "alt": 0,
              "type": 0
            },
            "head": 181,
            "speed": {
              "value": 0,
              "unit": 0
            },
            "accuracy": {
              "hdop": 0,
              "pdop": 0
            },
            "time": "20260517161030"
          },
          "vehicleStatus": {
            "airCtrlOn": false,
            "engine": true,
            "doorLock": true,
            "doorOpen": {
              "frontLeft": 0,
              "frontRight": 0,
              "backLeft": 0,
              "backRight": 0
            },
            "trunkOpen": false,
            "airTemp": {
              "value": "02H",
              "unit": 0,
              "hvacTempType": 1
            },
            "defrost": false,
            "acc": false,
            "evStatus": {
              "batteryCharge": true,
              "batteryStatus": 34,
              "batteryPlugin": 2,
              "remainTime2": {
                "etc1": {
                  "value": 20,
                  "unit": 1
                },
                "etc2": {
                  "value": 1180,
                  "unit": 1
                },
                "etc3": {
                  "value": 275,
                  "unit": 1
                },
                "atc": {
                  "value": 275,
                  "unit": 1
                }
              },
              "drvDistance": [
                {
                  "rangeByFuel": {
                    "evModeRange": {
                      "value": 140,
                      "unit": 1
                    },
                    "totalAvailableRange": {
                      "value": 140,
                      "unit": 1
                    }
                  },
                  "type": 2
                }
              ],
              "reservChargeInfos": {
                "reservChargeInfo": {
                  "reservChargeInfoDetail": {
                    "reservInfo": {
                      "day": [9],
                      "time": {
                        "time": "1200",
                        "timeSection": 0
                      }
                    },
                    "reservChargeSet": false,
                    "reservFatcSet": {
                      "defrost": false,
                      "airTemp": {
                        "value": "00H",
                        "unit": 0,
                        "hvacTempType": 1
                      },
                      "airCtrl": 0,
                      "heating1": 0
                    }
                  }
                },
                "offpeakPowerInfo": {
                  "offPeakPowerTime1": {
                    "starttime": {
                      "time": "1200",
                      "timeSection": 0
                    },
                    "endtime": {
                      "time": "1200",
                      "timeSection": 0
                    }
                  },
                  "offPeakPowerFlag": 0
                },
                "reserveChargeInfo2": {
                  "reservChargeInfoDetail": {
                    "reservInfo": {
                      "day": [9],
                      "time": {
                        "time": "1200",
                        "timeSection": 0
                      }
                    },
                    "reservChargeSet": false,
                    "reservFatcSet": {
                      "defrost": false,
                      "airTemp": {
                        "value": "00H",
                        "unit": 0,
                        "hvacTempType": 0
                      },
                      "airCtrl": 0,
                      "heating1": 0
                    }
                  }
                },
                "reservFlag": 0,
                "ect": {
                  "start": {
                    "day": 9,
                    "time": {
                      "time": "1959",
                      "timeSection": 1
                    }
                  },
                  "end": {
                    "day": 9,
                    "time": {
                      "time": "1959",
                      "timeSection": 1
                    }
                  }
                },
                "targetSOClist": [
                  {
                    "targetSOClevel": 80,
                    "dte": {
                      "rangeByFuel": {
                        "evModeRange": {
                          "value": 343,
                          "unit": 1
                        },
                        "totalAvailableRange": {
                          "value": 343,
                          "unit": 1
                        }
                      },
                      "type": 2
                    },
                    "plugType": 0
                  },
                  {
                    "targetSOClevel": 100,
                    "dte": {
                      "rangeByFuel": {
                        "evModeRange": {
                          "value": 439,
                          "unit": 1
                        },
                        "totalAvailableRange": {
                          "value": 439,
                          "unit": 1
                        }
                      },
                      "type": 2
                    },
                    "plugType": 1
                  }
                ]
              },
              "chargePortDoorOpenStatus": 2,
              "batteryPreconditioning": false,
              "batterySoh": 0,
              "batteryPower": {
                "batteryFstChrgPower": 0,
                "batteryStndChrgPower": 0,
                "batteryDischrgPower": 0
              }
            },
            "ign3": false,
            "hoodOpen": false,
            "transCond": true,
            "steerWheelHeat": 0,
            "sideBackWindowHeat": 0,
            "tirePressureLamp": {
              "tirePressureLampAll": 0,
              "tirePressureLampFL": 1,
              "tirePressureLampFR": 0,
              "tirePressureLampRL": 0,
              "tirePressureLampRR": 0
            },
            "battery": {
              "batSoc": 87,
              "batState": 0,
              "sjbDeliveryMode": 1,
              "batSignalReferenceValue": {
                "batWarning": 65
              },
              "powerAutoCutMode": 2
            },
            "lampWireStatus": {
              "stopLamp": {
                "leftLamp": false,
                "rightLamp": false
              },
              "headLamp": {
                "headLampStatus": false,
                "leftLowLamp": false,
                "rightLowLamp": false,
                "leftHighLamp": false,
                "rightHighLamp": false,
                "leftBifuncLamp": false,
                "rightBifuncLamp": false
              },
              "turnSignalLamp": {
                "leftFrontLamp": false,
                "rightFrontLamp": false,
                "leftRearLamp": false,
                "rightRearLamp": false
              }
            },
            "smartKeyBatteryWarning": false,
            "washerFluidStatus": false,
            "breakOilStatus": false,
            "sleepModeCheck": true,
            "time": "20260517161031",
            "remoteWaitingTimeAlert": {
              "remoteControlAvailable": 1,
              "remoteControlWaitingTime": 168,
              "elapsedTime": "00:03:13"
            },
            "systemCutOffAlert": 0,
            "tailLampStatus": 0,
            "hazardStatus": 0
          },
          "odometer": {
            "value": 59970.5,
            "unit": 1
          }
        }
      }
    }
    """

    /// Sample vehicle status response from Hyundai EU API for Gen5W
    static let vehicleStatusCCNC = """
    {
      "retCode" : "S",
      "resCode" : "0000",
      "resMsg" : {
        "ServiceNo" : "RVS-K",
        "state" : {
          "Vehicle" : {
            "RemoteControl" : {
              "SleepMode" : 1
            },
            "Electronics" : {
              "Battery" : {
                "Charging" : {
                  "WarningLevel" : 65
                },
                "PowerStateAlert" : {
                  "ClassC" : 2
                },
                "SensorReliability" : 0,
                "Level" : 78,
                "Auxiliary" : {
                  "FailWarning" : 0
                }
              },
              "PowerSupply" : {
                "Accessory" : 0,
                "Ignition3" : 0,
                "Ignition1" : 0
              },
              "AutoCut" : {
                "PowerMode" : 2,
                "BatteryPreWarning" : 0,
                "DeliveryMode" : 2
              },
              "FOB" : {
                "LowBattery" : 0
              }
            },
            "Version" : "CCU2026051614214901",
            "Body" : {
              "Lights" : {
                "Hazard" : {
                  "Alert" : 0
                },
                "TailLamp" : {
                  "Alert" : 0
                },
                "Rear" : {
                  "Left" : {
                    "TurnSignal" : {
                      "Warning" : 0
                    },
                    "StopLamp" : {
                      "Warning" : 0
                    }
                  },
                  "Right" : {
                    "TurnSignal" : {
                      "Warning" : 0
                    },
                    "StopLamp" : {
                      "Warning" : 0
                    }
                  }
                },
                "Front" : {
                  "Left" : {
                    "Low" : {
                      "Warning" : 0
                    },
                    "TurnSignal" : {
                      "Warning" : 0,
                      "LampState" : 0
                    },
                    "High" : {
                      "Warning" : 0
                    }
                  },
                  "Right" : {
                    "Low" : {
                      "Warning" : 0
                    },
                    "TurnSignal" : {
                      "Warning" : 0,
                      "LampState" : 0
                    },
                    "High" : {
                      "Warning" : 0
                    }
                  },
                  "HeadLamp" : {
                    "SystemWarning" : 0
                  }
                },
                "DischargeAlert" : {
                  "State" : 0
                }
              },
              "Trunk" : {
                "Open" : 1
              },
              "Windshield" : {
                "Rear" : {
                  "Defog" : {
                    "State" : 0
                  }
                },
                "Front" : {
                  "Heat" : {
                    "State" : 0
                  },
                  "Defog" : {
                    "State" : 0
                  },
                  "WasherFluid" : {
                    "LevelLow" : 0
                  }
                }
              },
              "Hood" : {
                "Frunk" : {
                  "Fault" : 0
                },
                "Open" : 0
              }
            },
            "Location" : {
              "Offset" : 2,
              "Version" : "HU2026033012161201",
              "GeoCoord" : {
                "Latitude" : 50.803116000000002,
                "Longitude" : 10.117241000000001,
                "Type" : 0,
                "Altitude" : 0
              },
              "Date" : "20260330101612.893",
              "Heading" : 275.10000610351562,
              "Speed" : {
                "Unit" : 0,
                "Value" : 0
              },
              "TimeStamp" : {
                "Day" : 30,
                "Mon" : 3,
                "Year" : 2026,
                "Hour" : 12,
                "Min" : 16,
                "Sec" : 12
              },
              "Servicestate" : 0
            },
            "Cabin" : {
              "SteeringWheel" : {
                "Heat" : {
                  "State" : 0,
                  "RemoteControl" : {
                    "Step" : 0
                  }
                }
              },
              "HVAC" : {
                "Vent" : {
                  "FineDust" : {
                    "State" : 0,
                    "Level" : 0
                  },
                  "AirCleaning" : {
                    "Indicator" : 1,
                    "SymbolColor" : 0
                  }
                },
                "Temperature" : {
                  "RangeType" : 1
                },
                "Row1" : {
                  "Driver" : {
                    "Blower" : {
                      "SpeedLevel" : 0
                    },
                    "Temperature" : {
                      "Value" : "OFF",
                      "Unit" : 0
                    }
                  }
                }
              },
              "Window" : {
                "Row2" : {
                  "Left" : {
                    "Open" : 0,
                    "OpenLevel" : 0
                  },
                  "Right" : {
                    "Open" : 0,
                    "OpenLevel" : 0
                  }
                },
                "Row1" : {
                  "Driver" : {
                    "Open" : 0,
                    "OpenLevel" : 0
                  },
                  "Passenger" : {
                    "Open" : 0,
                    "OpenLevel" : 0
                  }
                }
              },
              "Door" : {
                "Row2" : {
                  "Left" : {
                    "Open" : 1,
                    "Lock" : 0
                  },
                  "Right" : {
                    "Open" : 0,
                    "Lock" : 0
                  }
                },
                "Row1" : {
                  "Passenger" : {
                    "Open" : 0,
                    "Lock" : 0
                  },
                  "Driver" : {
                    "Open" : 0,
                    "Lock" : 0
                  }
                }
              },
              "Seat" : {
                "Row2" : {
                  "Left" : {
                    "Climate" : {
                      "State" : 2
                    },
                    "ArmRest" : {
                      "Heat" : 0
                    }
                  },
                  "Right" : {
                    "ArmRest" : {
                      "Heat" : 0
                    },
                    "Climate" : {
                      "State" : 2
                    }
                  }
                },
                "Row1" : {
                  "Driver" : {
                    "ArmRest" : {
                      "Heat" : 0
                    },
                    "Climate" : {
                      "State" : 2
                    }
                  },
                  "Passenger" : {
                    "ArmRest" : {
                      "Heat" : 0
                    },
                    "Climate" : {
                      "State" : 2
                    }
                  }
                }
              },
              "RestMode" : {
                "State" : 0
              }
            },
            "Offset" : "1",
            "Green" : {
              "Electric" : {
                "SmartGrid" : {
                  "VehicleToLoad" : {
                    "DischargeLimitation" : {
                      "DTE" : 94,
                      "RemainTime" : 0,
                      "SoC" : 20
                    }
                  },
                  "VehicleToGrid" : {
                    "Mode" : 0
                  },
                  "RealTimePower" : 0
                }
              },
              "EnergyInformation" : {
                "DTE" : {
                  "Invalid" : 0
                }
              },
              "Reservation" : {
                "OffPeakTime" : {
                  "EndMin" : 70,
                  "StartMin" : 70,
                  "Mode" : 0,
                  "EndHour" : 31,
                  "StartHour" : 31
                },
                "Departure" : {
                  "Schedule1" : {
                    "Enable" : 0,
                    "Fri" : 0,
                    "Sat" : 1,
                    "Tue" : 0,
                    "Mon" : 0,
                    "Thu" : 0,
                    "Wed" : 0,
                    "Sun" : 0,
                    "Min" : 40,
                    "Hour" : 9
                  },
                  "Schedule2" : {
                    "Mon" : 0,
                    "Wed" : 0,
                    "Sat" : 0,
                    "Hour" : 12,
                    "Min" : 0,
                    "Thu" : 0,
                    "Tue" : 0,
                    "Climate" : {
                      "Defrost" : 0,
                      "TemperatureHex" : "14",
                      "Temperature" : "24.0"
                    },
                    "Enable" : 0,
                    "Activation" : 1,
                    "Fri" : 0,
                    "Sun" : 0
                  },
                  "Climate" : {
                    "Defrost" : 1,
                    "Activation" : 1,
                    "TemperatureHex" : "0a",
                    "Temperature" : "19.0",
                    "TemperatureUnit" : 0
                  }
                }
              },
              "PlugAndCharge" : {
                "ContractCertificate5" : {
                  "Mon" : 0,
                  "Year" : 0,
                  "CompanyMask" : 0,
                  "State" : 2,
                  "Company" : ""
                },
                "ContractCertificate1" : {
                  "Mon" : 0,
                  "Year" : 0,
                  "CompanyMask" : 0,
                  "State" : 2,
                  "Company" : ""
                },
                "ContractCertificate4" : {
                  "Mon" : 0,
                  "Year" : 0,
                  "CompanyMask" : 0,
                  "State" : 2,
                  "Company" : ""
                },
                "ContractCertificate" : {
                  "Changeable" : 1,
                  "Mode" : 1,
                  "SelectedCert" : 0
                },
                "ContractCertificate3" : {
                  "Mon" : 0,
                  "Year" : 0,
                  "CompanyMask" : 0,
                  "State" : 2,
                  "Company" : ""
                },
                "ContractCertificate2" : {
                  "Mon" : 0,
                  "Year" : 0,
                  "CompanyMask" : 0,
                  "State" : 2,
                  "Company" : ""
                }
              },
              "ChargingDoor" : {
                "State" : 2,
                "ErrorState" : 1
              },
              "DrivingHistory" : {
                "Average" : 15.699999999999999,
                "Unit" : 1
              },
              "PowerConsumption" : {
                "Prediction" : {
                  "Climate" : 0
                }
              },
              "BatteryManagement" : {
                "SoH" : {
                  "Ratio" : 100
                },
                "BatteryRemain" : {
                  "Value" : 160358.39999999999,
                  "Ratio" : 58
                },
                "BatteryCapacity" : {
                  "Value" : 302400
                },
                "BatteryConditioning" : 0,
                "BatteryPreCondition" : {
                  "TemperatureLevel" : 1,
                  "Status" : 0
                }
              },
              "DrivingReady" : 0,
              "ChargingInformation" : {
                "ExpectedTime" : {
                  "StartHour" : 31,
                  "EndMin" : 63,
                  "StartMin" : 63,
                  "EndDay" : 7,
                  "EndHour" : 31,
                  "StartDay" : 7
                },
                "ElectricCurrentLevel" : {
                  "State" : 1
                },
                "ConnectorFastening" : {
                  "State" : 2
                },
                "EstimatedTime" : {
                  "Quick" : 50,
                  "ICCB" : 900,
                  "Standard" : 210
                },
                "SequenceDetails" : 0,
                "Charging" : {
                  "RemainTime" : 30
                },
                "SequenceSubcode" : 0,
                "TargetSoC" : {
                  "Quick" : 80,
                  "Standard" : 100
                },
                "DTE" : {
                  "TargetSoC" : {
                    "Quick" : 505,
                    "Standard" : 505
                  }
                }
              }
            },
            "DrivingReady" : 1,
            "Service" : {
              "ConnectedCar" : {
                "ActiveAlert" : {
                  "Available" : 1
                },
                "RemoteControl" : {
                  "WaitingTime" : 336,
                  "Available" : 1
                }
              }
            },
            "Chassis" : {
              "DrivingMode" : {
                "State" : "Normal"
              },
              "Axle" : {
                "Tire" : {
                  "PressureUnit" : 2,
                  "PressureLow" : 0
                },
                "Row2" : {
                  "Left" : {
                    "Tire" : {
                      "Pressure" : 255,
                      "PressureLow" : 0
                    }
                  },
                  "Right" : {
                    "Tire" : {
                      "Pressure" : 255,
                      "PressureLow" : 0
                    }
                  }
                },
                "Row1" : {
                  "Left" : {
                    "Tire" : {
                      "Pressure" : 255,
                      "PressureLow" : 1
                    }
                  },
                  "Right" : {
                    "Tire" : {
                      "Pressure" : 255,
                      "PressureLow" : 0
                    }
                  }
                }
              },
              "Brake" : {
                "Fluid" : {
                  "Warning" : 0
                }
              }
            },
            "Drivetrain" : {
              "Transmission" : {
                "GearPosition" : 0,
                "ParkingPosition" : 1
              },
              "Odometer" : 10953.1,
              "FuelSystem" : {
                "LowFuelWarning" : 0,
                "DTE" : {
                  "Unit" : 1,
                  "Total" : 277
                },
                "AverageFuelEconomy" : {
                  "Unit" : 5,
                  "Drive" : 0,
                  "AfterRefuel" : 15.699999999999999,
                  "Accumulated" : 18.299999
                },
                "FuelLevel" : 0
              }
            },
            "Date" : "20260516142149.000",
            "ConnectedService" : {
              "OTA" : {
                "ControllerStatus" : 0
              }
            }
          }
        },
        "resCode" : "0000",
        "RetCode" : "S",
        "lastUpdateTime" : "1778941310471"
      },
      "msgId" : "d125a520-536h-11s1-871a-c0369d72898f"
    }
    """

    /// Sample vehicles list response
    static let vehiclesList = """
    {
      "resMsg": {
        "vehicles": [
          {
            "vin": "KNDJ23AU1N7000000",
            "vehicleId": "REG123456",
            "vehicleName": "IONIQ 5",
            "type": "EV",
            "tmuNum": "-",
            "nickname": "IONIQ 5",
            "year": "2022",
            "master": true,
            "carShare": 0,
            "regDate": "2021-07-09 11:53:18.788",
            "detailInfo": {
                "inColor": "NNB",
                "outColor": "M9U",
                "bodyType": "2",
                "prodCarmdlCd": "GI",
                "saleCarmdlCd": "GI",
                "saleCarmdlEnNm": "IONIQ 5"
            },
            "protocolType": 0,
            "ccuCCS2ProtocolSupport": 0
          },
          {
            "regDate" : "2025-06-13 18:16:26.951",
            "protocolType" : 1,
            "vin" : "KNDJ23AU1N7000001",
            "master" : true,
            "ccuCCS2ProtocolSupport" : 1,
            "type" : "EV",
            "carShare" : 0,
            "tmuNum" : "-",
            "vehicleId" : "REG123457",
            "year" : "2025",
            "nickname" : "IONIQ 5",
            "vehicleName" : "IONIQ 5",
            "personalFlag" : "4",
            "detailInfo" : {
              "saleCarmdlCd" : "GI",
              "inColor" : "NNB",
              "outColor" : "R2P",
              "saleCarmdlEnNm" : "IONIQ 5",
              "bodyType" : "2",
              "prodCarmdlCd" : "GI"
            }
          }                   
        ]
      }
    }
    """

    /// Sample error response
    static let parkResponse = """
    {
      "retCode" : "S",
      "resCode" : "0000",
      "resMsg" : {
        "coord" : {
          "lat" : "50.803116000000002",
          "alt" : 0,
          "lon" : "10.117241000000001",
          "type" : 0
        },
        "speed" : {
          "value" : 0,
          "unit" : 0
        },
        "time" : "20260516161413",
        "head" : 275
      },
      "msgId" : "51e28d30-5419-11f1-b2a4-42922fc0513d"
    }
    """
}

// MARK: - Kia API Client Tests

@Suite("Hy API Client Tests")
struct HyEuAPIClientTests {

    @Test("HyEuAPIClient initialization")
    @MainActor func testHyClientInitialization() {
        let config = APIClientConfiguration(
            region: .europe,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID(),
            deviceId: UUID().uuidString
        )

        let client = HyundaiEuropeAPIClient(configuration: config)

        #expect(client.apiName == "HyundaiEurope")
    }

}

// MARK: - JSON Format Documentation Tests

@Suite("HY JSON Format Tests")
struct HyJSONFormatTests {

    @Test("Vehicle status JSON is valid")
    func testVehicleStatusJSONValid() throws {
        let dataGen5W = Data(HyEuSampleJSON.vehicleStatusGen5W.utf8)
        let jsonGen5W = try JSONSerialization.jsonObject(with: dataGen5W) as? [String: Any]

        #expect(jsonGen5W != nil)
        #expect(jsonGen5W?["rsMsg"] != nil)
    }

    @Test("HyEuAPIClient parsing")
    @MainActor func testHyClientParsingGen5W() throws {
        let data = Data(HyEuSampleJSON.vehicleStatusGen5W.utf8)
        let parkData = Data(HyEuSampleJSON.parkResponse.utf8)
        let vehicleData = Data(HyEuSampleJSON.vehiclesList.utf8)
        let config = APIClientConfiguration(
            region: .europe,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID(),
            deviceId: UUID().uuidString
        )

        let client = HyundaiEuropeAPIClient(configuration: config)
        let vehicles:[Vehicle] = try client.parseVehiclesResponse(vehicleData)

        let vehicleStatus = try client.parseVehicleStatusResponse(data, parkData, for: vehicles[0])
        #expect(vehicleStatus.odometer?.length == 59970.5)
        #expect(vehicleStatus.battery12V == 87)
        #expect(vehicleStatus.syncDate == Date(timeIntervalSince1970: 1779027031))
        #expect(vehicleStatus.location.latitude == 51.181234)
        #expect(vehicleStatus.location.longitude == 5.541234)
        #expect(vehicleStatus.lockStatus == .locked)
        #expect(vehicleStatus.climateStatus.airControlOn == false)
        #expect(vehicleStatus.climateStatus.defrostOn == false)
        #expect(vehicleStatus.climateStatus.steeringWheelHeatingOn == false)
        #expect(vehicleStatus.climateStatus.temperature == Temperature( value: 15.0, units: .celsius ))
        #expect(vehicleStatus.doorOpen?.anyOpen == false)
        #expect(vehicleStatus.trunkOpen == false)
        #expect(vehicleStatus.hoodOpen == false)
        #expect(vehicleStatus.tirePressureWarning?.all == false)
        #expect(vehicleStatus.tirePressureWarning?.frontLeft == true)
        #expect(vehicleStatus.evStatus?.evRange.percentage == 34.0)
        #expect(vehicleStatus.evStatus?.evRange.range == Distance(length: 140.0, units: .kilometers))
        #expect(vehicleStatus.evStatus?.targetSocAC == 100)
        #expect(vehicleStatus.evStatus?.targetSocDC == 80)
        #expect(vehicleStatus.evStatus?.currentTargetSOC == 100)
        #expect(vehicleStatus.evStatus?.pluggedIn == true)
        #expect(vehicleStatus.evStatus?.charging == true)
        #expect(vehicleStatus.evStatus?.plugType == .acCharger)
        #expect(vehicleStatus.engineOn == true)
    }

    @Test("HyEuAPIClient parsing")
    @MainActor func testHyClientParsingCCNC() throws {
        let data = Data(HyEuSampleJSON.vehicleStatusCCNC.utf8)
        let parkData = Data(HyEuSampleJSON.parkResponse.utf8)
        let vehicleData = Data(HyEuSampleJSON.vehiclesList.utf8)
        let config = APIClientConfiguration(
            region: .europe,
            brand: .hyundai,
            username: "test@example.com",
            password: "password123",
            pin: "0000",
            accountId: UUID(),
            deviceId: UUID().uuidString
        )

        let client = HyundaiEuropeAPIClient(configuration: config)
        let vehicles:[Vehicle] = try client.parseVehiclesResponse(vehicleData)

        let vehicleStatus = try client.parseVehicleStatusResponse(data, parkData, for: vehicles[1])
        #expect(vehicleStatus.odometer?.length == 10953.1)
        #expect(vehicleStatus.battery12V == 78)
        #expect(vehicleStatus.syncDate == Date(timeIntervalSince1970: 1778941310.471))
        #expect(vehicleStatus.location.latitude == 50.803116000000002)
        #expect(vehicleStatus.location.longitude == 10.117241000000001)
        #expect(vehicleStatus.lockStatus == .locked)
        #expect(vehicleStatus.climateStatus.airControlOn == false)
        #expect(vehicleStatus.climateStatus.defrostOn == false)
        #expect(vehicleStatus.climateStatus.steeringWheelHeatingOn == false)
        #expect(vehicleStatus.climateStatus.temperature == Temperature(
            value: Temperature.Units.fahrenheit.convert(Temperature.minimum, to: .celsius), units: .celsius ))
        #expect(vehicleStatus.doorOpen?.anyOpen == true)
        #expect(vehicleStatus.trunkOpen == true)
        #expect(vehicleStatus.hoodOpen == false)
        #expect(vehicleStatus.tirePressureWarning?.all == false)
        #expect(vehicleStatus.tirePressureWarning?.frontLeft == true)
        #expect(vehicleStatus.evStatus?.evRange.percentage == 58.0)
        #expect(vehicleStatus.evStatus?.evRange.range == Distance(length: 277.0, units: .kilometers))
        #expect(vehicleStatus.evStatus?.targetSocAC == 100)
        #expect(vehicleStatus.evStatus?.targetSocDC == 80)
        #expect(vehicleStatus.evStatus?.currentTargetSOC == 100)
        #expect(vehicleStatus.evStatus?.pluggedIn == true)
        #expect(vehicleStatus.evStatus?.charging == true)
        #expect(vehicleStatus.evStatus?.plugType == .acCharger)
        #expect(vehicleStatus.engineOn == true)
    }
}
