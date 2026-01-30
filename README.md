# BetterBlueKit

A Swift package for interacting with Hyundai BlueLink and Kia Connect services. This package provides a modern, type-safe interface for controlling your Hyundai or Kia vehicle using Swift's async/await pattern.

This is used by the [BetterBlue app](https://github.com/schmidtwmark/BetterBlue)

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.5+
- Xcode 13.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/schmidtwmark/BetterBlueKit.git", from: "1.0.0")
]
```

Or add it directly in Xcode:
1. Go to File > Add Packages...
2. Enter the repository URL
3. Select the version you want to use
4. Click Add Package

## Usage

```swift
import BetterBlueKit

// Create a configuration
let config = APIClientConfiguration(
    region: .usa,
    brand: .hyundai,
    username: "your.email@example.com",
    password: "your-password",
    pin: "1234",
    accountId: UUID() // Your account identifier
)

// Initialize the appropriate API client for your region and brand
// For Hyundai USA:
let endpointProvider = HyundaiAPIEndpointProviderUSA(configuration: config)
let client = HyundaiAPIClientUSA(configuration: config, endpointProvider: endpointProvider)

// For Kia USA:
// let endpointProvider = KiaAPIEndpointProviderUSA(configuration: config)
// let client = KiaAPIClientUSA(configuration: config, endpointProvider: endpointProvider)

// Use async/await to interact with your vehicle
Task {
    do {
        // Authenticate and get token
        let authToken = try await client.login()

        // Fetch your vehicles
        let vehicles = try await client.fetchVehicles(authToken: authToken)
        guard let vehicle = vehicles.first else {
            print("No vehicles found")
            return
        }

        // Get vehicle status
        let status = try await client.fetchVehicleStatus(
            for: vehicle,
            authToken: authToken
        )
        print("Battery: \(status.evStatus?.evRange.percentage ?? 0)%")
        print("Range: \(status.evStatus?.evRange.range.length ?? 0) miles")

        // Send commands to your vehicle
        let lockCommand = VehicleCommand.lock
        try await client.sendCommand(
            for: vehicle,
            command: lockCommand,
            authToken: authToken
        )
        print("Vehicle locked successfully")

        // Start climate with custom options
        let climateOptions = ClimateOptions(
            climate: true,
            temperature: Temperature(value: 72, units: .fahrenheit),
            defrost: false,
            heating: false,
            duration: 10,
            frontLeftSeat: .off,
            frontRightSeat: .off,
            rearLeftSeat: .off,
            rearRightSeat: .off
        )
        let climateCommand = VehicleCommand.startClimate(climateOptions)
        try await client.sendCommand(
            for: vehicle,
            command: climateCommand,
            authToken: authToken
        )
        print("Climate control started")

    } catch {
        print("Error: \(error)")
    }
}
```

## Features

- Modern async/await API
- Type-safe configuration and models
- Support for Hyundai BlueLink and Kia Connect
- Support for both electric and gas vehicles
- Plug-in hybrid vehicle support (PHEV)
- Comprehensive HTTP request/response logging
- Detailed error handling with user-friendly messages
- Vehicle control commands:
  - Lock/Unlock doors
  - Start/Stop climate control with custom settings
  - Start/Stop charging (for electric vehicles)
  - Individual seat heating controls
  - Defrost and steering wheel heating
- Vehicle status monitoring:
  - Battery level and EV range
  - Fuel level and gas range
  - Location tracking
  - Climate status
  - Lock status
  - Charging status
- Multiple regions supported (US, Canada, Europe, Australia, China, India)
- Fake API client for testing and development

## Important Notes

- Connecting to your vehicle requires an active Hyundai BlueLink or Kia Connect subscription.
- This is an unofficial package and is not affiliated with Hyundai or Kia
- Using this package may affect your vehicle's 12V battery if used too frequently
- Make sure you have read and understood the terms of use of your Kia or Hyundai account before using this package

## License

This project is licensed under the MIT License - see the LICENSE file for details. 
