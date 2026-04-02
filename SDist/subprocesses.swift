//
//  subprocesses.swift
//  SDist
//
//  Created by Sal Faris on 27/02/2024.
//

import Foundation


struct cURLMod: Codable{
    var pattern: String
    var additionalParameters: [String]
}

struct SDistConfig: Codable{
    var curl_mods: [cURLMod]
    var path_for_upload: String?
    var url_for_upload: String?
    
    enum CodingKeys: String, CodingKey {
        case curl_mods
        case path_for_upload
        case url_for_upload
    }
}

class CurlMods{
    let configFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".sdist_config.json")
    var mods: [cURLMod] = [
        cURLMod(pattern: "https://bt7.api.mega.co.nz",
                additionalParameters: ["-H", "Referer: https://transfer.it/", "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:145.0) Gecko/20100101 Firefox/145.0"])
    ]
    
    var pathForUpload: String? {
        return loadedConfig?.path_for_upload
    }
    
    var urlForUpload: String? {
        return loadedConfig?.url_for_upload
    }
    
    private var loadedConfig: SDistConfig?
    
    init(){
        print("cURL Mods: Config File=\(self.configFile.path)")
    }
    
    func loadMods(){
        do{
            let data = try Data(contentsOf: configFile)
            if let config = try? JSONDecoder().decode(SDistConfig.self, from: data) {
                self.loadedConfig = config
                self.mods.append(contentsOf: config.curl_mods)
                print("cURL Mods: All Mods Found...")
                _ = self.mods.compactMap({ print($0.pattern, "->", $0.additionalParameters)})
            } else {
                let content = try JSONDecoder().decode([cURLMod].self, from: data)
                self.mods.append(contentsOf: content)
                self.loadedConfig = SDistConfig(curl_mods: self.mods, path_for_upload: nil, url_for_upload: nil)
                print("cURL Mods: All Mods Found (legacy format)...")
                _ = self.mods.compactMap({ print($0.pattern, "->", $0.additionalParameters)})
            }
        } catch {
            print("WARNING: Unable to load cURL Mods, Error=", error)
        }
    }
    
    func saveConfig() throws {
        let config = SDistConfig(curl_mods: self.mods, path_for_upload: self.pathForUpload, url_for_upload: self.urlForUpload)
        let data = try JSONEncoder().encode(config)
        try data.write(to: configFile)
    }
    
    func setUploadConfig(path: String, url: String) throws {
        self.loadedConfig = SDistConfig(curl_mods: self.mods, path_for_upload: path, url_for_upload: url)
        try saveConfig()
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


func GET(url: String, silent: Bool = false) -> String? {
    let task = Process()
    let pipe = Pipe()
    
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["curl", "-L", "-s", url]
    task.standardOutput = pipe
    if silent {
        task.standardError = Pipe()
    }
    
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

func copyFile(_ source: String, destination: String){
    let task = Process()
    task.launchPath = "/bin/cp"
    task.arguments = [source, destination]
    task.launch()
    task.waitUntilExit()
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
