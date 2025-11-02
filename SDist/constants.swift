//
//  constants.swift
//  SDist
//
//  Created by Sal Faris on 27/02/2024.
//

import Foundation

fileprivate let URL = "https://thesal.pythonanywhere.com"
fileprivate let DC = URL + "/dc" // DC is for Distribution Center

class Endpoints{
    static let location = DC + "/location?l=%@&p=%@"
    static let setLocation = DC + "/location/set?k=%@&v=%@&p=%@"
    static let allLocation = DC + "/location/all?p=%@"
}

enum CommandLineArgs: String {
    case commandLineMode = "-c"
    case passwordArg = "-p"
    case functionArg = "-f"
    case argumentsArg = "-a" // everything after this is an argument
    case helpArg = "-h"
}

let documentationForFlags: [String: String] = [
    CommandLineArgs.commandLineMode.rawValue: "Run the CLI in command line mode",
    CommandLineArgs.passwordArg.rawValue: "The password to use",
    CommandLineArgs.functionArg.rawValue: "The function to run",
    CommandLineArgs.argumentsArg.rawValue: "The arguments for the function, everything after this is an argument",
    CommandLineArgs.helpArg.rawValue: "Show this help message"
]



let WELCOME_MSG = "Welcome to Salman's Distribution Center CLI"
let HELP_MSG = "This CLI Tool allows you to interact with the distribution center assets."

let CONSTANT_MSGS_DIST_C_SERVER: [String: String] = [
    "ERROR_MSG": "INVALID",
    "INVALID_PASSWORD": "Invalid password",
    "MISSING_PARAMETER": "Missing parameter",
    "OK": "OK"
]


enum CLIExceptions: Error{
    case BadPassword
    case MissingArguments
    case UnableToCastFunction
}


func _check_response(_ response: String?) throws -> Bool{
    if let response = response{
        if response == CONSTANT_MSGS_DIST_C_SERVER["INVALID_PASSWORD"]{
            throw CLIExceptions.BadPassword
        }else if response.startswith(CONSTANT_MSGS_DIST_C_SERVER["ERROR_MSG"]!){
            print("An error occurred, server response:", response)
            return false
        }
    }
    return true
}
