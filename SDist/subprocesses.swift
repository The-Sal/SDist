//
//  subprocesses.swift
//  SDist
//
//  Created by Sal Faris on 27/02/2024.
//

import Foundation


/// Not Regex Supported just uses if (string) in any of ARGs
/// prevents changing the base url ADD–ONLY
struct cURLMod: Codable{
    var pattern: String // This string should be inside the arguments
    var additionalParameters: [String]
}

/// When running curl website dynamcially change content is shown, for example sometimes they want different headers
/// and other features to enable this cURL mods allow specifying a JSON which dynamically allows you to modify the cURL
/// requests on the fly for functions that use it
class CurlMods{
    let configFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".sdist_config.json")
    var mods: [cURLMod] = [
        cURLMod(pattern: "https://bt7.api.mega.co.nz",
                additionalParameters: ["-H", "Referer: https://transfer.it/", "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:145.0) Gecko/20100101 Firefox/145.0"])
    ]
    
    init(){
        print("cURL Mods: Config File=\(self.configFile.path)")
    }
    
    func loadMods(){
        do{
            let content = try JSONDecoder().decode([cURLMod].self, from: try Data(contentsOf: configFile))
            self.mods.append(contentsOf: content)
            print("cURL Mods: All Mods Found...")
            _ = self.mods.compactMap({ print($0.pattern, "->", $0.additionalParameters)})
        } catch {
            print("WARNING: Unable to load cURL Mods, Error=", error)
        }
    }
    
    func updateCurlCall(cURLCall: [String]) -> [String]{
        for param in cURLCall{
            for pattern in self.mods{
                if param.contains(pattern.pattern){
                    let result = cURLCall + pattern.additionalParameters
                    print("cURL Mods: Pattern matched, updated to cURL=\(result)")
                    return result
                }
            }
        }
        
        return cURLCall
    }
    
    static let shared = CurlMods()
    
}


func GET(url: String) -> String? {
    let task = Process()
    let pipe = Pipe()
    
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["curl", "-L", url]
    task.standardOutput = pipe
    
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        return output
    } catch {
        print("Error executing command: \(error)")
        return nil
    }
}

func downloadFile(url: String, saveName: String) {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    let arguments = ["curl", "--progress-bar", "-L", "-o", saveName, url]
    task.arguments = CurlMods.shared.updateCurlCall(cURLCall: arguments)
    task.launch()
    task.waitUntilExit()
}

func unzip(tempFilePath: String){
    let task = Process()
    task.launchPath = "/usr/bin/unzip"
    task.arguments = [tempFilePath]
    let devNull = FileHandle.nullDevice
    task.standardOutput = devNull
    task.standardError = devNull

    task.launch()
    task.waitUntilExit()
}

func mv(_ string: String, destination: String){
    let task1 = Process()
    task1.launchPath = "/bin/mv"
    task1.arguments = [string, destination]
    task1.launch()
    task1.waitUntilExit()
}

func rm(_ string: String){
    let task2 = Process()
    task2.launchPath = "/bin/rm"
    task2.arguments = ["-rf", string]
}

func getTerminalColumns() -> Int? {
    let task = Process()
    task.launchPath = "/usr/bin/tput"
    task.arguments = ["cols"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    if let output = String(data: data, encoding: .utf8),
       let columns = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return columns
    }

    return nil
}
