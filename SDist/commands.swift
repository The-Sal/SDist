//
//  commands.swift
//  SDist
//
//  Created by Sal Faris on 27/02/2024.
//

import Foundation

enum Errors: Error {
    case noMoreParams
    case fileNotFound(String)
}

fileprivate let special = "XS@#$%"
fileprivate var paramIdsCalls: [String: Int] = [:]
typealias dynamicParams = [String: String]

extension dynamicParams {
    private static var orderedKeys: [String: [String]] = [:]
    
    func getKey(_ string: String, alternative_method: () -> (String)) -> String {
        let specialId = Array(self.keys).sorted().joined()
        
        do {
            if self.keys.contains(string) {
                return self[string]!
            } else {
                // Get the ordered keys for this params instance
                guard let orderedKeys = dynamicParams.orderedKeys[specialId] else {
                    return alternative_method()
                }
                
                // Check if using indexed special keys (format: "0", "1", "2", etc.)
                let indexedKeys = orderedKeys.enumerated().map { String($0.offset) }
                if let firstIndexKey = indexedKeys.first, self[firstIndexKey] == special {
                    if let pos = paramIdsCalls[specialId] {
                        paramIdsCalls[specialId] = pos + 1
                        if orderedKeys.count <= (pos + 1) {
                            throw Errors.noMoreParams
                        }
                        return orderedKeys[pos + 1]
                    } else {
                        paramIdsCalls[specialId] = 0
                        return orderedKeys[0]
                    }
                }
            }
        } catch {
            if arguments.contains(.errorOnNoParamsError) {
                print("Error: \(error). Interactive mode is disabled.")
                exit(EXIT_FAILURE)
            } else {
                print("Error: \(error). Falling back to interactive mode.")
            }
        }
        
        return alternative_method()
    }
    
    init(fromArray: [String]) {
        self.init()
        let specialId = fromArray.enumerated().map { String($0.offset) }.sorted().joined()
        dynamicParams.orderedKeys[specialId] = fromArray // Store the original order!
        // Use indices as keys instead of the actual values
        for (index, _) in fromArray.enumerated() {
            self[String(index)] = special
        }
    }
}

let tempDir = URL(filePath: NSTemporaryDirectory())
let fm = FileManager.default

func askUser(question: String) -> String{
    print(question)
    return readLine()!
}

func askUserWrapper(question: String) -> () -> String{
    func wrapper() -> String{
        print(question)
        return readLine()!
    }
    
    return wrapper
}

func get_location(_ params: dynamicParams) throws{
    let key = params.getKey("key", alternative_method: askUserWrapper(question: "Enter Asset Key:"))
    let response = GET(url: .init(format: Endpoints.location, key, PASSWORD))
    if try _check_response(response){
        print("URL:", response!)
    }
}

func download_asset(_ params: dynamicParams) throws {
    let key = params.getKey("key", alternative_method: askUserWrapper(question: "Asset Key:"))
    let saveName = params.getKey("saveName", alternative_method: askUserWrapper(question: "What would you like to save the file as?:"))
    let response = GET(url: .init(format: Endpoints.location, key, PASSWORD))
    if try !_check_response(response){
        return
    }
    
    
    print("Downloading asset...")
    print("Downloading from:", response!)
    
    downloadFile(url: response!, saveName: saveName)
    let finalDestination = URL(filePath: FileManager.default.currentDirectoryPath).appending(path: saveName).path(percentEncoded: false)
    print("Asset downloaded, file: \(finalDestination)")
    
    if saveName.contains(".enc"){
        print(".enc file detected, would you like to decrypt the file")
        let decrypt_file_user = params.getKey("decryptFile", alternative_method: askUserWrapper(question: "Would you like to decrypt this file (y/n):"))
        if decrypt_file_user.lowercased() == "y"{
            print("Decryption is done via openssl, there is no support for command line mode.")
            decrypt_file(finalDestination, file: finalDestination.replacingOccurrences(of: ".enc", with: ""))
        }
    }
}

func encrypt_asset(_ params: dynamicParams) throws{
    let fp = params.getKey("path", alternative_method: askUserWrapper(question: "Filepath:")).replacingOccurrences(of: "\\ ", with: " ")
    var dst = params.getKey("dest", alternative_method: askUserWrapper(question: "Destination:"))
    if !dst.contains(".enc"){
        print("Warning, per SDist encryption spec, the file will be saved with a .enc extension.")
        dst.append(".enc")
    }
    openssl_encrypt(fp, outputFile: dst)
}

func local_decrypt(_ params: dynamicParams) throws {
    let fp = params.getKey("path", alternative_method: askUserWrapper(question: "Filepath:")).replacingOccurrences(of: "\\ ", with: " ")
    let dst = params.getKey("dest", alternative_method: askUserWrapper(question: "Destination:"))
    openssl_decrypt(fp, outputFile: dst)
}

func list_all(_ params: dynamicParams) throws{
    let response = GET(url: .init(format: Endpoints.allLocation, PASSWORD))
    if try !_check_response(response){
        return
    }
    
    print("Assets:")
    
    if let jsonData = response!.data(using: .utf8) {
        if let jsonArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String] {
            for string in jsonArray{
                print("*", string)
            }
            
        } else {
            print("Failed to convert JSON string to array")
        }
    } else {
        print("Invalid JSON string")
    }
    
}

func update_locations(_ params: dynamicParams) throws{
    let key = params.getKey("key", alternative_method: askUserWrapper(question: "Asset Key:"))
    let url = params.getKey("url", alternative_method: askUserWrapper(question: "URL of the asset:")).data(using: .utf8)!.base64EncodedString()
    let response = GET(url: .init(format: Endpoints.setLocation, key, url, PASSWORD))
    
    print("Updating asset...")
    print("Server Response:")
    print(response ?? "No response")
    if try !_check_response(response){
        return
    }
}

func remove_location(_ params: dynamicParams) throws {
    let key = params.getKey("key", alternative_method: askUserWrapper(question: "Asset Key:"))
    let response = GET(url: .init(format: Endpoints.removeLocation, key, PASSWORD))
    if try _check_response(response){
        print("Server Response:", response ?? "cURL didn't return a response")
        print("Asset should be deleted.")
    }else{
        print("Something went wrong. Server Response:")
        print(response ?? "cURL didn't return a response")
    }
}

func save_password(_ params: dynamicParams) throws{
    let password = params.getKey("password", alternative_method: askUserWrapper(question: "Password:"))
    let data = password.data(using: .utf8)!
    try data.write(to: PW_location)
}

func help(_ params: dynamicParams){
    let cmds = COMMANDS.sorted(by: {
        let l1 = $0.key.count + ($0.value["description"] as! String).count
        let l2 = $1.key.count + ($1.value["description"] as! String).count
        
        return l1 < l2
    })

    print("Commands:")
    for command in cmds {
        print("\t\(command.key): \(command.value["description"]!)")
    }
}

func clearScreen(_ params: dynamicParams){
    let clearScreen = Process()
    clearScreen.launchPath = "/usr/bin/clear"
    clearScreen.arguments = []
    clearScreen.launch()
    clearScreen.waitUntilExit()
}

func listDirectory(_ params: dynamicParams) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ls")
    proc.arguments = ["-lh"]
    try? proc.run()
    proc.waitUntilExit()
}

#if os(macOS)
func encrypt_asset_se(_ params: dynamicParams) throws {
    let fp = params.getKey("path", alternative_method: askUserWrapper(question: "Filepath:")).replacingOccurrences(of: "\\ ", with: " ")
    var dst = params.getKey("dest", alternative_method: askUserWrapper(question: "Destination:"))
    if !dst.contains(".enc.se") {
        print("Warning: per SDist SE encryption spec, the file will be saved with a .enc.se extension.")
        dst.append(".enc.se")
    }
    let keyLabel = params.getKey("keyLabel", alternative_method: askUserWrapper(question: "SE Key Label (optional, press enter or ? for default):"))
    
    let finalKeyLabel: String?
    switch keyLabel {
    case "":
        finalKeyLabel = nil
    case "?":
        finalKeyLabel = nil
    default:
        finalKeyLabel = keyLabel
    }

    se_encrypt(fp, outputFile: dst, keyLabel: finalKeyLabel)
}

func decrypt_asset_se(_ params: dynamicParams) throws {
    let fp = params.getKey("path", alternative_method: askUserWrapper(question: "Filepath:")).replacingOccurrences(of: "\\ ", with: " ")
    let dst = params.getKey("dest", alternative_method: askUserWrapper(question: "Destination:"))
    se_decrypt(fp, outputFile: dst)
}

func list_se_keys(_ params: dynamicParams) throws {
    se_list_keys()
}

func cleanup_se_keys(_ params: dynamicParams) throws {
    se_cleanup_old_keys()
}

func install_app(_ params: dynamicParams) throws{
    let key = params.getKey("key", alternative_method: askUserWrapper(question: "Enter Asset Key:"))
    let response = GET(url: .init(format: Endpoints.location, key, PASSWORD))
    if try !_check_response(response){
        return
    }
    
    print("Downloading App Zip file")
    print("Downloading from: \(response!)")
    let tempFile = tempDir.appending(path: "saveapp.zip")
    downloadFile(url: response!, saveName: tempFile.path(percentEncoded: false))
    print("App zip file downloaded to:", tempFile.path(percentEncoded: false))
    let random_num = (0...900000).randomElement()!
    let random_directory = tempDir.appending(path: "app_" + random_num.description)
    let current_directory = FileManager.default.currentDirectoryPath
    try FileManager.default.createDirectory(at: random_directory, withIntermediateDirectories: false)
    FileManager.default.changeCurrentDirectoryPath(random_directory.path(percentEncoded: false))
    print("Extracting app from zip file")
    unzip(tempFilePath: tempFile.path(percentEncoded: false))
    
    let cmds = [
        ["xattr", "-d", "com.apple.quarantine"],
        ["chmod", "+x"],
        ["xattr", "-cr"]
    ]
    
    rm(random_directory.appending(path: "__MACOSX").path(percentEncoded: false))
    
    if let app_real_name = try FileManager.default.contentsOfDirectory(atPath: random_directory.path(percentEncoded: false)).first{
        let app_name = random_directory.appending(path: app_real_name)
        let app_file_destination = URL(filePath: current_directory).appending(path: app_real_name)
        print("Setting Permissions")
        for var cmd in cmds {
            let process = Process()
            process.executableURL = .init(filePath: "/usr/bin/env")
            cmd.append(app_name.path(percentEncoded: false))
            process.arguments = cmd
            do{
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Failed: \(cmd), error: \(error)")
            }
        }
        
        
        print("Cleaning up....")
        FileManager.default.changeCurrentDirectoryPath(current_directory)
        mv(app_name.path(percentEncoded: false), destination: app_file_destination.path(percentEncoded: false))
        
        print("App available at: \(app_file_destination.path(percentEncoded: false))")
        rm(tempFile.path(percentEncoded: false))
        rm(tempDir.path(percentEncoded: false))
        print("Install Completed")
    }else{
        print("The downloaded asset does not support the install command. Please use 'download' instead.")
        rm(tempFile.path(percentEncoded: false))
        rm(tempDir.path(percentEncoded: false))
    }
    
   
}

func install_app_from_encrypted_zip(_ params: dynamicParams) throws {
    let encryptedPath = params.getKey("path", alternative_method: askUserWrapper(question: "Encrypted Path"))
    var appName = params.getKey("appName", alternative_method: askUserWrapper(question: "App Name"))
    if !appName.hasSuffix(".app"){
        appName += ".app"
    }
    let dest = fm.currentDirectoryPath.appending("/" + appName + ".zip")
    decrypt_file(encryptedPath, file: dest)
    
    let random_num = (0...900000).randomElement()!
    let random_directory = tempDir.appending(path: "app_" + random_num.description)
    let cwd = fm.currentDirectoryPath
    try fm.createDirectory(at: random_directory, withIntermediateDirectories: true)
    fm.changeCurrentDirectoryPath(random_directory.path(percentEncoded: false))
    print("Temporary Directory: \(random_directory.path(percentEncoded: false))")
    unzip(tempFilePath: dest)
    if fm.fileExists(atPath: "./__MACOSX"){
        try fm.removeItem(atPath: "./__MACOSX")
    }
    let files = try fm.contentsOfDirectory(atPath: ".")
    print("Available Files: \(files)")
    let tempApp = fm.currentDirectoryPath.appending("/" + (try fm.contentsOfDirectory(atPath: ".").first!))
    try fixApplication(appURL: .init(filePath: tempApp))
    try fm.copyItem(at: URL(fileURLWithPath: tempApp), to: URL(fileURLWithPath: cwd).appendingPathComponent(appName))
    fm.changeCurrentDirectoryPath(cwd)
    try fm.removeItem(at: random_directory)
    try fm.removeItem(at: URL(fileURLWithPath: dest))
}

func install_app_encrypted(_ params: dynamicParams) throws {
    let key = params.getKey("key", alternative_method: askUserWrapper(question: "Asset Key: "))
    let appName = params.getKey("appName", alternative_method: askUserWrapper(question: "App Name: "))
    let tempEncZipName = appName + ".zip.enc"
    
    try download_asset([
        "key": key,
        "saveName": tempEncZipName,
        "decryptFile": "n"
    ])
    
    guard fm.fileExists(atPath: tempEncZipName) else {
        throw Errors.fileNotFound("Unable to find: \(tempEncZipName)")
    }
    
    try install_app_from_encrypted_zip([
        "path": tempEncZipName,
        "appName": appName,
    ])
    
}

#endif

func load_password() throws -> String?{
    if let pw = String(data: try Data(contentsOf: PW_location), encoding: .utf8){
        return pw
    }
    return nil
}
func decrypt_file(_ filePath: String, file: String){
    openssl_decrypt(filePath, outputFile: file)
}
enum AppFixErrors: Error{
    case noAppFound
}
func fixApplication(appURL: URL) throws{
    let fm = FileManager.default
    
    print("Checking if \(appURL.lastPathComponent) is available...")
    guard fm.fileExists(atPath: appURL.path) else { throw AppFixErrors.noAppFound }
    
    let executables = try fm.contentsOfDirectory(atPath: appURL.path(percentEncoded: false) + "/Contents/MacOS")
    print("Executables found:", executables)
    
    let cmds = [
        ["xattr", "-d", "com.apple.quarantine"],
        ["chmod", "+x"],
        ["xattr", "-cr"]
    ]
    
    for cmd in cmds{
        let task = Process()
        task.executableURL = .init(filePath: "/usr/bin/env")
        task.arguments = cmd + [appURL.path(percentEncoded: false)]
        try task.run()
        task.waitUntilExit()
    }
    
    for executable in executables {
        let fullPath = appURL.path(percentEncoded: false) + "/Contents/MacOS/\(executable)"
        let task = Process()
        task.executableURL = .init(filePath: "/usr/bin/env")
        task.arguments = ["chmod", "+x", fullPath]
        try task.run()
        task.waitUntilExit()
    }
    
    
}

var COMMANDS: [String: [String: Any]] = [
    "get": [
        "function": get_location,
        "description": "Get the URL of an asset"
    ],
    
    "download": [
        "function": download_asset,
        "description": "Download an asset, (optionally decrypting)"
    ],
    "list": [
        "function": list_all,
        "description": "List all available assets"
    ],
    "update": [
        "function": update_locations,
        "description": "Update the CDN with a new asset"
    ],
    "exit": [
        "function": exit,
        "description": "Exit the CLI"
    ],

    "save-password": [
        "function": save_password,
        "description": "Save a password to file"
    ],

    "rm-asset": [
        "function": remove_location,
        "description": "Remove an asset from the manifest"
    ],
    "encrypt": [
        "function": encrypt_asset,
        "description": "Locally encrypt a file using SDist encryption spec (OpenSSL)"
    ],

    "decrypt": [
        "function": local_decrypt,
        "description": "Locally Decrypt a file using SDist encryption spec (OpenSSL)"
    ],
    
    "help": [
        "function": help,
        "description": "Show this help page"
    ],
    "clear": [
        "function": clearScreen,
        "description": "Clears the screen"
    ],
    "ls": [
        "function": listDirectory,
        "description": "List the contents of a directory"
    ]
]

#if os(macOS)
// Add Secure Enclave commands (macOS only)
func addMacOSOnly() {
    COMMANDS["encrypt-se"] = [
        "function": encrypt_asset_se,
        "description": "Encrypt a file using Secure Enclave (macOS only)"
    ]
    COMMANDS["decrypt-se"] = [
        "function": decrypt_asset_se,
        "description": "Decrypt a Secure Enclave encrypted file (macOS only)"
    ]
    COMMANDS["list-se-keys"] = [
        "function": list_se_keys,
        "description": "List Secure Enclave keys in keychain (macOS only)"
    ]
    COMMANDS["cleanup-se-keys"] = [
        "function": cleanup_se_keys,
        "description": "Clean up old SE key storage (run if having issues)"
    ]
    COMMANDS["install"] = [
        "function": install_app,
        "description": "Install an application"
    ]
    
    COMMANDS["install-encrypted"] = [
        "function": install_app_encrypted,
        "description": "Install an application thats encrypted with OpenSSL"
    ]
    
    COMMANDS["install-local-encrypted"] = [
        "function": install_app_from_encrypted_zip,
        "description": "Install an application from a locally encrypted zip"
    ]
}
#endif


func showDocumentation(docs: String) {
    let task = Process()
    task.launchPath = "/usr/bin/less"
    task.arguments = [docs]
    try! task.run()
    task.waitUntilExit()
}

func generateDocs() -> String{
    var docs = "SDist – Tool that allows access to asset's stored within the distrubution network.\n\n"
    
    docs += "Flags for command line mode:\n"
    for flag in documentationForFlags{
        docs += "\(flag.key): \(flag.value)" + "\n"
    }
    
    docs += "\nYou can find the number/kind of arguments a command takes by running the command in the regular mode.\n\n"
    docs += "Commands:\n"
    
    for command in COMMANDS{
        docs += " \(command.key): \(command.value["description"]!)" + "\n"
    }
    
    docs += "\n\nExample usage:\n"
    docs += "./this_file -c -p PASSWORD -f get -a ASSET_KEY\n"
    
    
    return docs
}
