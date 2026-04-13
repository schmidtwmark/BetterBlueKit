//
//  main.swift
//  BBCLI - BetterBlueKit Command Line Interface
//
//  A CLI tool for testing BetterBlueKit API functionality.
//

import BetterBlueKit
import Dispatch
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
    var redactPII: Bool = false
}

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

func prettyPrintJSON(_ jsonString: String) -> String {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data),
          let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
          let prettyString = String(data: prettyData, encoding: .utf8) else {
        return jsonString
    }
    return prettyString
}

func redactVIN(_ vin: String) -> String {
    guard vin.count > 6 else { return "[REDACTED]" }
    return String(vin.prefix(3)) + String(repeating: "*", count: vin.count - 6) + String(vin.suffix(3))
}

// MARK: - Argument Parsing

@MainActor
func parseArguments(state: CLIState) {
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
                if let parsedRegion = Region(rawValue: regionArg.uppercased()) {
                    state.region = parsedRegion
                } else {
                    printError("Unknown region: \(args[argIndex + 1]). Use \(Region.allCases.map { $0.rawValue }).")
                    exit(1)
                }
                argIndex += 1
            }
        case "--no-redaction":
            state.redactPII = false
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
           bbcli parse [OPTIONS] <json-string-or-file>

    Interactive Mode Options:
      -u, --username <email>    Account username/email
      -p, --password <pass>     Account password
      --pin <pin>               Vehicle PIN (required for Hyundai)
      -b, --brand <brand>       Brand: 'hyundai' or 'kia' (default: hyundai)
      -r, --region <region>     Region: 'USA', 'Canada', 'Europe' (default: USA)
      --no-redaction            Disable PII redaction in HTTP logs
      -h, --help                Show this help message

    Parse Mode:
      bbcli parse -b <brand> -r <region> -t <type> [--vin <vin>] [--electric] <json>

      Parses a raw API response JSON and outputs the parsed BetterBlueKit struct.

      -t, --type <type>         Parse type: 'vehicles' or 'vehicleStatus'
      --vin <vin>               VIN for vehicleStatus parsing (default: TESTVIN0000000000)
      --electric                Mark vehicle as electric for parsing (auto-detected from
                                evStatus field in vehicles response if not specified)
      <json>                    JSON string or path to a JSON file (last argument)

      If the JSON contains a top-level "responseBody" key, it will be automatically
      unwrapped before parsing.

    Examples:
      bbcli -u user@email.com -p password --pin 1234 -b hyundai
      bbcli -b kia -u user@email.com -p password
      bbcli parse -b hyundai -r US -t vehicleStatus response.json
      bbcli parse -b hyundai -r US -t vehicleStatus '{"vehicleStatus": {...}}'
      bbcli parse -b kia -r US -t vehicles --electric response.json
    """)
}

// MARK: - Login Flow

@MainActor
func performLogin(state: CLIState) async throws {
    let brand = state.brand
    let region = state.region
    let username = state.username
    let password = state.password
    let pin = state.pin

    printHeader("Login")
    print("Brand: \(brand.displayName)")
    print("Region: \(region.rawValue)")
    print("Username: \(username)")
    if state.redactPII == false {
        print("⚠️  PII redaction disabled - sensitive data will be visible in logs")
    }
    print("")

    // Create HTTP log sink for console output
    let logSink: HTTPLogSink = { log in
        printSubheader("HTTP \(log.requestType.displayName)")
        print("[\(log.preciseTimestamp)] \(log.method) \(log.url)")
        print("Duration: \(log.formattedDuration)")
        if let status = log.responseStatus {
            print("Status: \(status)")
        }
        if let error = log.error {
            print("Error: \(error)")
        }
        if let apiError = log.apiError {
            print("API Error: \(apiError)")
        }
        if let body = log.requestBody {
            let formatted = prettyPrintJSON(body)
            print("Request Body:\n\(formatted)")
        }
        if let body = log.responseBody {
            let formatted = prettyPrintJSON(body)
            let truncated = formatted.count > 4000
                ? String(formatted.prefix(4000)) + "\n... (truncated)"
                : formatted
            print("Response Body:\n\(truncated)")
        }
    }

    let config = APIClientConfiguration(
        region: region,
        brand: brand,
        username: username,
        password: password,
        pin: pin,
        accountId: UUID(),
        logSink: logSink,
        redactPII: state.redactPII
    )

    let client: any APIClientProtocol
    do {
        client = try createBetterBlueKitAPIClient(configuration: config)
    } catch let error as APIError {
        printError("\(error.errorType): \(error.message)")
        exit(1)
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
            try await handleMFA(client: client, error: error, state: state)
        } else {
            throw error
        }
    }
}

@MainActor
func handleMFA(client: any APIClientProtocol, error: APIError, state: CLIState) async throws {
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
    let method: MFAMethod = methodChoice == "2" ? .sms : .email

    print("Sending MFA code via \(method)...")
    try await client.sendMFACode(xid: xid, otpKey: otpKey, method: method)
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
    let (rmToken, sid) = try await client.verifyMFACode(xid: xid, otpKey: otpKey, code: code)
    printSuccess("MFA verification successful!")

    print("Completing login...")
    let token = try await client.completeMFALogin(sid: sid, rmToken: rmToken)
    state.authToken = token
    printSuccess("Login completed!")
    print("Auth token received (expires: \(token.expiresAt))")
}

// MARK: - API Commands

@MainActor
func fetchVehicles(state: CLIState) async throws {
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
        let displayVIN = state.redactPII ? redactVIN(vehicle.vin) : vehicle.vin
        print("\n[\(index + 1)] \(vehicle.model)")
        print("    VIN: \(displayVIN)")
        print("    Model: \(vehicle.model)")
        print("    Fuel Type: \(vehicle.fuelType.rawValue)")
        print("    Generation: \(vehicle.generation)")
        if let key = vehicle.vehicleKey {
            let displayKey = state.redactPII ? "[REDACTED]" : key
            print("    Vehicle Key: \(displayKey)")
        }
    }
}

@MainActor
func selectVehicle(state: CLIState) -> Vehicle? {
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
        let displayVIN = state.redactPII ? redactVIN(vehicle.vin) : vehicle.vin
        print("  \(index + 1). \(vehicle.model) (\(displayVIN))")
    }

    let choice = prompt("Vehicle number: ")
    if let index = Int(choice), index > 0, index <= vehicles.count {
        return vehicles[index - 1]
    }

    printError("Invalid selection")
    return nil
}

@MainActor
func fetchVehicleStatus(state: CLIState) async throws {
    guard let vehicle = selectVehicle(state: state) else { return }
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
}

@MainActor
func sendCommand(_ command: VehicleCommand, description: String, state: CLIState) async throws {
    guard let vehicle = selectVehicle(state: state) else { return }
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
func fetchEVTripDetails(state: CLIState) async throws {
    guard let vehicle = selectVehicle(state: state) else { return }
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
func runInteractiveLoop(state: CLIState) async {
    while true {
        showMenu()
        let choice = prompt("Enter command number: ")

        do {
            switch choice {
            case "1":
                try await fetchVehicles(state: state)
            case "2":
                try await fetchVehicleStatus(state: state)
            case "3":
                try await sendCommand(.lock, description: "Lock", state: state)
            case "4":
                try await sendCommand(.unlock, description: "Unlock", state: state)
            case "5":
                print("Climate options (press Enter for defaults):")
                let tempStr = prompt("Temperature (default 72°F): ")
                let temp = Double(tempStr) ?? 72.0
                var options = ClimateOptions()
                options.temperature = Temperature(value: temp, units: .fahrenheit)
                try await sendCommand(.startClimate(options), description: "Start Climate", state: state)
            case "6":
                try await sendCommand(.stopClimate, description: "Stop Climate", state: state)
            case "7":
                try await sendCommand(.startCharge, description: "Start Charge", state: state)
            case "8":
                try await sendCommand(.stopCharge, description: "Stop Charge", state: state)
            case "9":
                let acStr = prompt("AC Charge Limit (50-100): ")
                let dcStr = prompt("DC Charge Limit (50-100): ")
                let acLimit = Int(acStr) ?? 80
                let dcLimit = Int(dcStr) ?? 80
                try await sendCommand(
                    .setTargetSOC(acLevel: acLimit, dcLevel: dcLimit),
                    description: "Set Charge Limits",
                    state: state
                )
            case "10":
                try await fetchEVTripDetails(state: state)
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

// MARK: - Parse Mode

enum ParseType: String {
    case vehicles
    case vehicleStatus
}

struct ParseOptions {
    var brand: Brand = .hyundai
    var region: Region = .usa
    var parseType: ParseType?
    var vin: String = "TESTVIN0000000000"
    var fuelType: FuelType?  // nil = auto-detect
    var jsonInput: String?
}

func parseParseArguments() -> ParseOptions {
    let args = CommandLine.arguments
    var options = ParseOptions()
    var argIndex = 2  // Skip "bbcli" and "parse"

    while argIndex < args.count {
        switch args[argIndex] {
        case "-b", "--brand":
            if argIndex + 1 < args.count {
                let brandArg = args[argIndex + 1].lowercased()
                if let brand = Brand(rawValue: brandArg) {
                    options.brand = brand
                } else {
                    printError("Unknown brand: \(args[argIndex + 1]). Use 'hyundai' or 'kia'.")
                    exit(1)
                }
                argIndex += 1
            }
        case "-r", "--region":
            if argIndex + 1 < args.count {
                let regionArg = args[argIndex + 1]
                if let parsedRegion = Region(rawValue: regionArg.uppercased()) {
                    options.region = parsedRegion
                } else {
                    printError("Unknown region: \(args[argIndex + 1]). Use \(Region.allCases.map { $0.rawValue }).")
                    exit(1)
                }
                argIndex += 1
            }
        case "-t", "--type":
            if argIndex + 1 < args.count {
                let typeArg = args[argIndex + 1]
                switch typeArg.lowercased() {
                case "vehicles":
                    options.parseType = .vehicles
                case "vehiclestatus", "status":
                    options.parseType = .vehicleStatus
                default:
                    printError("Unknown parse type: \(typeArg). Use 'vehicles' or 'vehicleStatus'.")
                    exit(1)
                }
                argIndex += 1
            }
        case "--vin":
            if argIndex + 1 < args.count {
                options.vin = args[argIndex + 1]
                argIndex += 1
            }
        case "--electric":
            options.fuelType = .electric
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            // Last unknown argument is the JSON input
            options.jsonInput = args[argIndex]
        }
        argIndex += 1
    }

    return options
}

func loadJSONData(from input: String) throws -> Data {
    // Check if it's a file path
    let fileManager = FileManager.default
    let path = (input as NSString).expandingTildeInPath
    if fileManager.fileExists(atPath: path) {
        print("Reading JSON from file: \(path)")
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    // Try as raw JSON string
    guard let data = input.data(using: .utf8) else {
        throw APIError(message: "Could not convert input to data")
    }

    // Validate it's actually JSON
    guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
        throw APIError(message: "Input is neither a valid file path nor valid JSON")
    }

    return data
}

/// Unwraps a `{"responseBody": {...}}` wrapper if present, returning the inner data.
func unwrapResponseBody(_ data: Data) -> Data {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let responseBody = json["responseBody"],
          json.count <= 2  // responseBody + maybe one other key like "responseHeader"
    else {
        return data
    }

    if let unwrapped = try? JSONSerialization.data(withJSONObject: responseBody) {
        print("Auto-unwrapped 'responseBody' wrapper")
        return unwrapped
    }
    return data
}

func encodePrettyJSON<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "\(value)"
    }
    return string
}

@MainActor
func runParseMode() async -> Int32 {
    let options = parseParseArguments()

    guard let parseType = options.parseType else {
        printError("Parse type is required. Use -t vehicles or -t vehicleStatus")
        return 1
    }

    guard let jsonInput = options.jsonInput else {
        printError("JSON input is required (JSON string or path to file)")
        return 1
    }

    do {
        let rawData = try loadJSONData(from: jsonInput)
        let data = unwrapResponseBody(rawData)

        // Create a dummy API client for parsing
        let config = APIClientConfiguration(
            region: options.region,
            brand: options.brand,
            username: "parse-mode",
            password: "",
            pin: "",
            accountId: UUID()
        )

        let client = try createBetterBlueKitAPIClient(configuration: config)

        printHeader("Parsing \(parseType.rawValue) (\(options.brand.displayName) \(options.region.rawValue))")

        switch parseType {
        case .vehicles:
            let vehicles = try parseVehicles(client: client, data: data, options: options)
            printSuccess("Parsed \(vehicles.count) vehicle(s)")
            print(encodePrettyJSON(vehicles))

        case .vehicleStatus:
            let fuelType = options.fuelType ?? .gas
            let vehicle = Vehicle(
                vin: options.vin,
                regId: "parse-mode",
                model: "parse-mode",
                accountId: UUID(),
                fuelType: fuelType,
                generation: 2,
                odometer: Distance(length: 0, units: .miles)
            )
            let status = try parseVehicleStatus(client: client, data: data, vehicle: vehicle)
            printSuccess("Parsed vehicle status")
            print(encodePrettyJSON(status))
        }

        return 0
    } catch let error as APIError {
        printError("\(error.errorType): \(error.message)")
        return 1
    } catch {
        printError(error.localizedDescription)
        return 1
    }
}

@MainActor
func parseVehicles(client: any APIClientProtocol, data: Data, options: ParseOptions) throws -> [Vehicle] {
    if let hyundaiUSA = client as? HyundaiUSAAPIClient {
        return try hyundaiUSA.parseVehiclesResponse(data)
    } else if let hyundaiCanada = client as? HyundaiCanadaAPIClient {
        return try hyundaiCanada.parseCanadaVehiclesResponse(data)
    } else if let hyundaiEurope = client as? HyundaiEuropeAPIClient {
        return try hyundaiEurope.parseVehiclesResponse(data)
    } else if let kiaUSA = client as? KiaUSAAPIClient {
        return try kiaUSA.parseVehiclesResponse(data)
    } else {
        throw APIError(message: "Unsupported client type for vehicle parsing")
    }
}

@MainActor
func parseVehicleStatus(client: any APIClientProtocol, data: Data, vehicle: Vehicle) throws -> VehicleStatus {
    if let hyundaiUSA = client as? HyundaiUSAAPIClient {
        return try hyundaiUSA.parseVehicleStatusResponse(data, for: vehicle)
    } else if let hyundaiCanada = client as? HyundaiCanadaAPIClient {
        return try hyundaiCanada.parseCanadaVehicleStatusResponse(data, for: vehicle)
    } else if let hyundaiEurope = client as? HyundaiEuropeAPIClient {
        return try hyundaiEurope.parseVehicleStatusResponse(data, for: vehicle)
    } else if let kiaUSA = client as? KiaUSAAPIClient {
        return try kiaUSA.parseVehicleStatusResponse(data, for: vehicle)
    } else {
        throw APIError(message: "Unsupported client type for status parsing")
    }
}

// MARK: - Main

@MainActor
func runCLI() async -> Int32 {
    let state = CLIState()
    parseArguments(state: state)

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
        try await performLogin(state: state)
        await runInteractiveLoop(state: state)
        return 0
    } catch let error as APIError {
        printError("\(error.errorType): \(error.message)")
        if let userInfo = error.userInfo {
            print("User Info: \(userInfo)")
        }
        return 1
    } catch {
        printError(error.localizedDescription)
        return 1
    }
}

Task { @MainActor in
    // Check if first argument is "parse" subcommand
    let exitCode: Int32
    if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "parse" {
        exitCode = await runParseMode()
    } else {
        exitCode = await runCLI()
    }
    exit(exitCode)
}

dispatchMain()
