//
//  main.swift
//  SDist
//
//  Created by Sal Faris on 27/02/2024.
//

import Foundation



let VERSION = "0.11.0"

print(WELCOME_MSG)
print("Version: \(VERSION)")

extension String{
    func startswith(_ string: String) -> Bool{
        return self.hasPrefix(string)
    }
    
    
    func format(arguments: [CVarArg]) -> String{
        let string = String(format: self, arguments: arguments)
        return string
    }
}

extension [String]{
    func contains(_ string: String) -> Bool{
        return self.contains { str in
            str == string
        }
    }
    func contains(_ cliArg: CommandLineArgs) -> Bool{
        return self.contains(cliArg.rawValue)
    }
    func findArgumentValue(_ cliArgs: CommandLineArgs) throws -> String{
        if let index = self.firstIndex(of: cliArgs.rawValue){
            if (index + 1) < self.count{
                return self[index + 1]
            }else{
                print("Unable to find a value for: \(cliArgs.rawValue)")
                throw CLIExceptions.MissingArguments
            }
        }else{
            print("Unable to find index for: \(cliArgs.rawValue)")
            throw CLIExceptions.MissingArguments
        }
        
        
    }
    func findArgumentValues(_ cliArgs: CommandLineArgs) -> [String]{
        if let index = self.firstIndex(of: cliArgs.rawValue){
            if (index + 1) < self.count{
                return [String](self.suffix(from: index + 1))
            }
        }
        
        return []
    }
}



var PASSWORD: String = "NONE"
let arguments = CommandLine.arguments
let PW_location = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sdist")

// Initialize Secure Enclave commands on macOS
#if os(macOS)
//se_check_biometry()
addMacOSOnly()
#endif



func user_interface() throws{
    let linenoise = LineNoise()
    let historyFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sdist_history").path
    try? linenoise.loadHistory(fromFile: historyFile)
    linenoise.setHistoryMaxLength(1000)
    
    linenoise.setCompletionCallback { text in
        let components = text.components(separatedBy: " ").filter { !$0.isEmpty }
        
        if components.count <= 1 {
            let prefix = components.first ?? ""
            return COMMANDS.keys.filter { $0.hasPrefix(prefix) }.sorted()
        } else {
            let command = components[0]
            let prefix = components[1...].joined(separator: " ")
            let manifestKeys = getCachedManifestKeys()
            let cwdFiles = getCWDFiles()
            let allItems = Array(Set(manifestKeys + cwdFiles))
            return allItems
                .filter { $0.hasPrefix(prefix) }
                .map { command + " " + $0 }
                .sorted()
        }
    }
    
    linenoise.setHintsCallback { text in
        guard !text.isEmpty else { return (nil as String?, nil as (Int, Int, Int)?) }
        
        let components = text.components(separatedBy: " ").filter { !$0.isEmpty }
        var candidates: [String]
        
        if components.count <= 1 {
            let prefix = components.first ?? ""
            candidates = COMMANDS.keys.filter { $0.hasPrefix(prefix) && $0 != prefix }.sorted()
        } else {
            let command = components[0]
            let prefix = components[1...].joined(separator: " ")
            let manifestKeys = getCachedManifestKeys()
            let cwdFiles = getCWDFiles()
            let allItems = Array(Set(manifestKeys + cwdFiles))
            candidates = allItems
                .filter { $0.hasPrefix(prefix) && $0 != prefix }
                .map { command + " " + $0 }
                .sorted()
        }
        
        guard let first = candidates.first else { return (nil as String?, nil as (Int, Int, Int)?) }
        let hint = String(first.dropFirst(text.count))
        return (hint, (128, 128, 128))
    }
    
    help(dynamicParams())
    while true{
        let input: String
        do {
            input = try linenoise.getLine(prompt: "Enter a command: ")
        } catch LinenoiseError.EOF {
            print("")
            break
        } catch LinenoiseError.CTRL_C {
            print("")
            continue
        } catch {
            print("Error: \(error)")
            break
        }
        
        linenoise.addHistory(input)
        
        print("")
        let args = input.split(separator: " ").map(\.description)
        let cmd = args.first ?? ""
        let argsToPass = args.dropFirst().map(\.description).filter({$0 != "" })
        if cmd == "exit"{
            try? linenoise.saveHistory(toFile: historyFile)
            exit(EXIT_SUCCESS)
        }
        
        if let command = COMMANDS[cmd]{
            guard let function = command["function"]! as? (dynamicParams) throws -> Void else {
                throw CLIExceptions.UnableToCastFunction
            }
            
            let showOperation = String(repeating: "*", count: Int(Double(getTerminalColumns() ?? 100) * 0.5))
            print(showOperation)
            try function(.init(fromArray: argsToPass))
            if cmd != "clear"{ print(showOperation) }
        }
    }
    
    try? linenoise.saveHistory(toFile: historyFile)
}

func commandLineMode() throws{
    let function = try arguments.findArgumentValue(.functionArg)
    let args = arguments.findArgumentValues(.argumentsArg)
    
    print("Function: \(function)")
    print("Args: \(args)")
    
    if let cmd = COMMANDS[function]{
        guard let function = cmd["function"]! as? (dynamicParams) throws -> Void else { throw CLIExceptions.UnableToCastFunction }
        if args.count > 0{
            try function(.init(fromArray: args))
        }else{
            try function(.init())
        }
    }
}



do{
    // check if the help message arg was passed
    if arguments.contains(.helpArg){
        print("Generating docs...")
        let docs = generateDocs()
        print(docs)
        exit(EXIT_SUCCESS)
    }
    
    if arguments.contains(.cliPathArg){
        print(arguments)
    }
    
    if arguments.contains(.commandLineMode){
        if let pw = try? load_password(){
            PASSWORD = pw
        }else{
            PASSWORD = try arguments.findArgumentValue(.passwordArg)
        }
        try commandLineMode()
    }else{
        if let pw = try? load_password(){
            PASSWORD = pw
        }else{
            PASSWORD = askUser(question: "Enter Password:")
        }
        try user_interface()
    }
    
} catch {
    print("Error: \(error)")
    exit(EXIT_FAILURE)
}



