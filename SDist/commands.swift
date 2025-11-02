//
//  commands.swift
//  SDist
//
//  Created by Sal Faris on 27/02/2024.
//

import Foundation

fileprivate let special = "XS@#$%"
fileprivate var paramIdsCalls: [
    String: Int
] = [:]

typealias dynamicParams = [String: String]


extension dynamicParams{
    
    func getKey(_ string: String, alternative_method: () -> (String)) -> String{
        
        let specialId = Array(self.keys).description
        
        
        if Array(self.keys).contains(string){
            return self[string]!
        }else{
            if let firstKey = self.keys.first{
                if let value = self[firstKey]{
                    if value == special{
                        if let pos = paramIdsCalls[specialId]{
                            paramIdsCalls[specialId] = pos + 1
                            return Array(self.keys)[pos + 1]
                        }else{
                            paramIdsCalls[specialId] = 0
                            return Array(self.keys)[0]
                        }
                    }
                }
            }
            
        }
        
        return alternative_method()
    }
    
    init(fromArray: [String]){
        
        self.init()
        for item in fromArray{
            self[item] = special
        }
        
        
    }
}




let tempDir = URL(filePath: NSTemporaryDirectory())


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

func download_asset(_ params: dynamicParams) throws{
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
    print("Asset downloade, file: \(finalDestination)")
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


let COMMANDS = [
    "get": [
        "function": get_location,
        "description": "Get the URL of an asset"
    ],
    "install": [
        "function": install_app,
        "description": "Install an application"
    ],
    "download": [
        "function": download_asset,
        "description": "Download an asset"
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
]


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
