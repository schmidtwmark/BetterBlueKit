//
//  main.swift
//  BBCLI - BetterBlueKit Command Line Interface
//
//  A CLI tool for testing BetterBlueKit API functionality.
//

import BetterBlueKit
import Foundation

// MARK: - CLI State

// Use a simple class for state since we're single-threaded CLI
@MainActor
final class CLIState {
    var client: (any APIClientProtocol)?
    var authToken: AuthToken?
    var vehicles: [Vehicle] = []
    var username: String = ""
    var password: String = ""
    var pin: String = ""

    var brand: Brand = .hyundai
    var region: Region = .usa
}

@MainActor
let state = CLIState()

// MARK: - Helpers

func printHeader(_ text: String) {
    print("\n" + String(repeating: "=", count: 60))
    print(" \(text)")
    print(String(repeating: "=", count: 60))
}

func printSubheader(_ text: String) {
    print("\n--- \(text) ---")
}

func printError(_ text: String) {
    print("❌ ERROR: \(text)")
}

func printSuccess(_ text: String) {
    print("✅ \(text)")
}

func prompt(_ message: String) -> String {
    print(message, terminator: "")
    fflush(stdout)
    return readLine() ?? ""
}

// MARK: - Argument Parsing

@MainActor
func parseArguments() {
    let args = CommandLine.arguments
    var argIndex = 1

    while argIndex < args.count {
        switch args[argIndex] {
        case "-u", "--username":
            if argIndex + 1 < args.count {
                state.username = args[argIndex + 1]
                argIndex += 1
            }
        case "-p", "--password":
            if argIndex + 1 < args.count {
                state.password = args[argIndex + 1]
                argIndex += 1
            }
        case "--pin":
            if argIndex + 1 < args.count {
                state.pin = args[argIndex + 1]
                argIndex += 1
            }
        case "-b", "--brand":
            if argIndex + 1 < args.count {
                let brandArg = args[argIndex + 1].lowercased()
                if let brand = Brand(rawValue: brandArg) {
                    state.brand = brand
                } else {
                    printError("Unknown brand: \(args[argIndex + 1]). Use 'hyundai' or 'kia'.")
                    exit(1)
                }
                argIndex += 1
            }
        case "-r", "--region":
            if argIndex + 1 < args.count {
                let regionArg = args[argIndex + 1]
                print("Region arg: '\(regionArg)'")
                if let parsedRegion = Region(rawValue: regionArg.uppercased()) {
                    state.region = parsedRegion
                } else {
                    printError("Unknown region: \(args[argIndex + 1]). Use \(Region.allCases.map { $0.rawValue }).")
                    exit(1)
                }
                argIndex += 1
            }
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            break
        }
        argIndex += 1
    }
}

func printUsage() {
    print("""
    BetterBlueKit CLI - Test tool for Hyundai/Kia API

    Usage: bbcli [OPTIONS]

    Options:
      -u, --username <email>    Account username/email
      -p, --password <pass>     Account password
      --pin <pin>               Vehicle PIN (required for Hyundai)
      -b, --brand <brand>       Brand: 'hyundai' or 'kia' (default: hyundai)
      -r, --region <region>     Region: 'USA', 'Canada', 'Europe' (default: USA)
      -h, --help                Show this help message

    If credentials are not provided via arguments, you will be prompted.

    Examples:
      bbcli -u user@email.com -p password --pin 1234 -b hyundai
      bbcli -b kia -u user@email.com -p password
    """)
}

// MARK: - Login Flow

@MainActor
func performLogin() async throws {
    let brand = state.brand
    let region = state.region
    let username = state.username
    let password = state.password
    let pin = state.pin

    printHeader("Login")
    print("Brand: \(brand.displayName)")
    print("Region: \(region.rawValue)")
    print("Username: \(username)")
    print("")

    let config = APIClientConfiguration(
        region: region,
        brand: brand,
        username: username,
        password: password,
        pin: pin,
        accountId: UUID()
    )

    let client: any APIClientProtocol
    if brand == .kia {
        let endpointProvider = KiaAPIEndpointProviderUSA(configuration: config)
        client = KiaAPIClientUSA(configuration: config, endpointProvider: endpointProvider)
    } else {
        let endpointProvider = HyundaiAPIEndpointProviderUSA(configuration: config)
        client = HyundaiAPIClientUSA(configuration: config, endpointProvider: endpointProvider)
    }

    state.client = client

    do {
        print("Attempting login...")
        let token = try await client.login()
        state.authToken = token
        printSuccess("Login successful!")
        print("Auth token received (expires: \(token.expiresAt))")
    } catch let error as APIError {
        if error.errorType == .requiresMFA, client.supportsMFA() {
            try await handleMFA(client: client, error: error)
        } else {
            throw error
        }
    }
}

@MainActor
func handleMFA(client: any APIClientProtocol, error: APIError) async throws {
    printSubheader("MFA Required")

    guard let userInfo = error.userInfo else {
        throw APIError(message: "MFA required but no user info provided")
    }

    let xid = userInfo["xid"] ?? ""
    let otpKey = userInfo["otpKey"] ?? ""
    let email = userInfo["email"]
    let phone = userInfo["phone"]

    print("Available MFA methods:")
    if let email = email {
        print("  1. Email: \(email)")
    }
    if let phone = phone {
        print("  2. Phone: \(phone)")
    }

    let methodChoice = prompt("Select method (1 for email, 2 for phone): ")
    let notifyType = methodChoice == "2" ? "SMS" : "EMAIL"

    print("Sending MFA code via \(notifyType)...")
    try await client.sendMFACode(otpKey: otpKey, xid: xid, notifyType: notifyType)
    printSuccess("MFA code sent!")

    let rawCode = prompt("Enter verification code: ")
    // Filter to digits only - OTP codes are always numeric, and terminal escape sequences
    // can sometimes be captured by readLine()
    let code = rawCode.filter { $0.isNumber }

    if code.isEmpty {
        throw APIError(message: "No verification code entered")
    }

    if code != rawCode {
        print("Note: Cleaned input from '\\(rawCode)' to '\\(code)'")
    }

    print("Verifying MFA code...")
    let (rmToken, sid) = try await client.verifyMFACode(otpKey: otpKey, xid: xid, otp: code)
    printSuccess("MFA verification successful!")

    print("Completing login...")
    let token = try await client.completeMFALogin(sid: sid, rmToken: rmToken)
    state.authToken = token
    printSuccess("Login completed!")
    print("Auth token received (expires: \(token.expiresAt))")
}

// MARK: - API Commands

@MainActor
func fetchVehicles() async throws {
    printSubheader("Fetching Vehicles")

    guard let token = state.authToken else {
        throw APIError(message: "Not logged in")
    }

    guard let client = state.client else {
        throw APIError(message: "No API client initialized")
    }

    let vehicles = try await client.fetchVehicles(authToken: token)
    state.vehicles = vehicles

    printSuccess("Found \(vehicles.count) vehicle(s)")

    for (index, vehicle) in vehicles.enumerated() {
        print("\n[\(index + 1)] \(vehicle.model)")
        print("    VIN: \(vehicle.vin)")
        print("    Model: \(vehicle.model)")
        print("    Electric: \(vehicle.isElectric)")
        print("    Generation: \(vehicle.generation)")
        if let key = vehicle.vehicleKey {
            print("    Vehicle Key: \(key)")
        }

        // Print as JSON
        printSubheader("Vehicle \(index + 1) JSON")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let jsonData = try? encoder.encode(vehicle),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
}

@MainActor
func selectVehicle() -> Vehicle? {
    let vehicles = state.vehicles

    if vehicles.isEmpty {
        printError("No vehicles loaded. Fetch vehicles first.")
        return nil
    }

    if vehicles.count == 1 {
        return vehicles[0]
    }

    print("\nSelect a vehicle:")
    for (index, vehicle) in vehicles.enumerated() {
        print("  \(index + 1). \(vehicle.model) (\(vehicle.vin))")
    }

    let choice = prompt("Vehicle number: ")
    if let index = Int(choice), index > 0, index <= vehicles.count {
        return vehicles[index - 1]
    }

    printError("Invalid selection")
    return nil
}

@MainActor
func fetchVehicleStatus() async throws {
    guard let vehicle = selectVehicle() else { return }
    guard let token = state.authToken else {
        throw APIError(message: "Not logged in")
    }

    guard let client = state.client else {
        throw APIError(message: "No API client initialized")
    }

    printSubheader("Fetching Status for \(vehicle.model)")

    let status = try await client.fetchVehicleStatus(for: vehicle, authToken: token)

    printSuccess("Status fetched successfully")

    // Print summary
    print("\n📊 Status Summary:")
    print("  Lock Status: \(status.lockStatus)")
    print("  Climate On: \(status.climateStatus.airControlOn)")
    print("  Climate Temp: \(status.climateStatus.temperature.value)°\(status.climateStatus.temperature.units == .celsius ? "C" : "F")")

    if let evStatus = status.evStatus {
        print("  🔋 EV Status:")
        print("     Battery: \(Int(evStatus.evRange.percentage))%")
        print("     Range: \(Int(evStatus.evRange.range.length)) \(evStatus.evRange.range.units == .miles ? "mi" : "km")")
        print("     Plugged In: \(evStatus.pluggedIn)")
        print("     Charging: \(evStatus.charging)")
        if let targetAC = evStatus.targetSocAC {
            print("     Target SOC (AC): \(Int(targetAC))%")
        }
        if let targetDC = evStatus.targetSocDC {
            print("     Target SOC (DC): \(Int(targetDC))%")
        }
    }

    if let gasRange = status.gasRange {
        print("  ⛽ Fuel Status:")
        print("     Fuel: \(Int(gasRange.percentage))%")
        print("     Range: \(Int(gasRange.range.length)) \(gasRange.range.units == .miles ? "mi" : "km")")
    }

    // Print as JSON
    printSubheader("Status JSON")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let jsonData = try? encoder.encode(status),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print(jsonString)
    }
}

@MainActor
func sendCommand(_ command: VehicleCommand, description: String) async throws {
    guard let vehicle = selectVehicle() else { return }
    guard let token = state.authToken else {
        throw APIError(message: "Not logged in")
    }

    guard let client = state.client else {
        throw APIError(message: "No API client initialized")
    }

    printSubheader("Sending \(description) to \(vehicle.model)")

    try await client.sendCommand(for: vehicle, command: command, authToken: token)

    printSuccess("\(description) command sent successfully!")
}

@MainActor
func fetchEVTripDetails() async throws {
    guard let vehicle = selectVehicle() else { return }
    guard let token = state.authToken else {
        throw APIError(message: "Not logged in")
    }

    guard let client = state.client else {
        throw APIError(message: "No API client initialized")
    }

    printSubheader("Fetching EV Trip Details for \(vehicle.model)")

    let trips = try await client.fetchEVTripDetails(for: vehicle, authToken: token) ?? []

    printSuccess("Found \(trips.count) trip(s)")

    for (index, trip) in trips.prefix(5).enumerated() {
        print("\n[\(index + 1)] Trip on \(trip.startDate)")
        print("    Distance: \(trip.distance) mi")
        print("    Duration: \(trip.formattedDuration)")
        print("    Energy Used: \(Double(trip.totalEnergyUsed) / 1000.0) kWh")
    }

    // Print first trip as JSON
    if let firstTrip = trips.first {
        printSubheader("First Trip JSON")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let jsonData = try? encoder.encode(firstTrip),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
}

// MARK: - Interactive Menu

func showMenu() {
    printHeader("BetterBlueKit CLI")

    print("""

    Commands:
      1. Fetch Vehicles
      2. Fetch Vehicle Status
      3. Lock Vehicle
      4. Unlock Vehicle
      5. Start Climate
      6. Stop Climate
      7. Start Charge
      8. Stop Charge
      9. Set Charge Limits
     10. Fetch EV Trip Details
      0. Exit

    """)
}

@MainActor
func runInteractiveLoop() async {
    while true {
        showMenu()
        let choice = prompt("Enter command number: ")

        do {
            switch choice {
            case "1":
                try await fetchVehicles()
            case "2":
                try await fetchVehicleStatus()
            case "3":
                try await sendCommand(.lock, description: "Lock")
            case "4":
                try await sendCommand(.unlock, description: "Unlock")
            case "5":
                print("Climate options (press Enter for defaults):")
                let tempStr = prompt("Temperature (default 72°F): ")
                let temp = Double(tempStr) ?? 72.0
                var options = ClimateOptions()
                options.temperature = Temperature(value: temp, units: .fahrenheit)
                try await sendCommand(.startClimate(options), description: "Start Climate")
            case "6":
                try await sendCommand(.stopClimate, description: "Stop Climate")
            case "7":
                try await sendCommand(.startCharge, description: "Start Charge")
            case "8":
                try await sendCommand(.stopCharge, description: "Stop Charge")
            case "9":
                let acStr = prompt("AC Charge Limit (50-100): ")
                let dcStr = prompt("DC Charge Limit (50-100): ")
                let acLimit = Int(acStr) ?? 80
                let dcLimit = Int(dcStr) ?? 80
                try await sendCommand(.setTargetSOC(acLevel: acLimit, dcLevel: dcLimit), description: "Set Charge Limits")
            case "10":
                try await fetchEVTripDetails()
            case "0", "q", "quit", "exit":
                print("\nGoodbye!")
                return
            default:
                printError("Invalid command")
            }
        } catch let error as APIError {
            printError("\(error.errorType): \(error.message)")
            if let userInfo = error.userInfo {
                print("User Info: \(userInfo)")
            }
        } catch {
            printError(error.localizedDescription)
        }

        print("\nPress Enter to continue...")
        _ = readLine()
    }
}

// MARK: - Main

@main
struct BBCLI {
    @MainActor
    static func main() async {
        parseArguments()

        // Prompt for missing credentials
        if state.username.isEmpty {
            state.username = prompt("Username/Email: ")
        }
        if state.password.isEmpty {
            state.password = prompt("Password: ")
        }
        if state.brand == .hyundai && state.pin.isEmpty {
            let rawPin = prompt("PIN: ")
            // Filter to digits only - PIN should be numeric
            state.pin = rawPin.filter { $0.isNumber }
        }

        // Perform login
        do {
            try await performLogin()
            await runInteractiveLoop()
        } catch let error as APIError {
            printError("\(error.errorType): \(error.message)")
            if let userInfo = error.userInfo {
                print("User Info: \(userInfo)")
            }
            exit(1)
        } catch {
            printError(error.localizedDescription)
            exit(1)
        }
    }
}
