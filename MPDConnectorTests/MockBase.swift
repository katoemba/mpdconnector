//
//  MockBase.swift
//  MPDConnector
//
//  Created by Berrie Kremers on 10-08-17.
//  Copyright © 2017 Kaotemba Software. All rights reserved.
//

import Foundation
import XCTest

class MockBase {
    /// Dictionary of calls (functionName as key) and parameters as value.
    /// Values is an array of dictionaries, where key=parameter-name, value=parameter-value
    private var calls = [String: [[String: String]]]()
    
    /// Register that a call was made.
    ///
    /// - Parameters:
    ///   - functionName: Name of the function that was called.
    ///   - parameters: Dictionary of parameters that were passed to the function.
    func registerCall(_ functionName: String, _ parameters: [String: String]) {
        if var callInfos = calls[functionName] {
            callInfos.append(parameters)
            calls[functionName] = callInfos
        }
        else {
            calls[functionName] = [parameters]
        }
    }
    
    func clearAllCalls() {
        calls = [String: [[String: String]]]()
    }
    
    func callCount(_ functionName: String) -> Int {
        if let callInfos = calls[functionName] {
            return callInfos.count
        }
        return 0
    }
    
    func assertCall(_ functionName: String, expectedCallCount: Int = 1, expectedParameters: [String: String] = [:]) {
        var callCount = 0
        if let callInfos = calls[functionName] {
            callCount = callInfos.count

            var callInfo = [String: String]()
            if callInfos.count > 0 {
                callInfo = callInfos[0]
            }
            for expectedParameter in expectedParameters.keys {
                let expectedValue = expectedParameters[expectedParameter]
                let actualValue = callInfo[expectedParameter]
                
                if actualValue != nil {
                    XCTAssert(expectedValue == actualValue, "Expected \(expectedValue!) for parameter \(expectedParameter), got \(actualValue!)")
                }
                else {
                    XCTAssert(true == false, "No value found for parameter \(expectedParameter)")
                }
            }

        }
        XCTAssert(callCount == expectedCallCount, "Expected \(expectedCallCount) calls to '\(functionName)', actual number of calls is \(callCount)")
    }
}
