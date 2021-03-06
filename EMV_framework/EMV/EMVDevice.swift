//
//  IDT_VP3300.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 28/10/2018.
//  Copyright © 2018 Beachy. All rights reserved.
//

import Foundation

enum EmvError: Error {
    case deviceIsNotConnected
    case cannotStartTransaction(message: String)
    case cannotParseCardData(message: String)
}

class EmvDevice: NSObject {
    
    var onEmvConnected: (() -> Void)?
    var onEmvDisconnected: (() -> Void)?
    var onEmvTimeout: (() -> Void)?
    var onEmvSendMessage: ((_ message: String) -> Void)?
    var onEmvDataParseError: ((_ errorMessage: String) -> Void)?
    var onEmvDataReceived: ((_ data: String) -> Void)?
    
    override init() {
        super.init()
        
        IDT_VP3300
            .sharedController()
            .delegate = self
    }
    
    func setReaderSleepAndPowerOffTime(
        sleepTimeInSec: Int = 60,
        powerOffTimeInSec: Int = 30) -> UInt32 {
        
        var response: NSData?
        let sleep = String(format:"%02X", sleepTimeInSec)
        let powerOff = String(format: "%02X", powerOffTimeInSec)
        let dataAsHex = sleep + powerOff
        
        return IDT_VP3300
            .sharedController()
            .device_sendIDGCommand(UInt8(240), //f0
                subCommand: UInt8(0), //00
                data: IDTUtility.hex(toData:dataAsHex),
                response: &response)
            .rawValue
    }
    
    func cancelTransaction() -> Void {
        /**
         * Make sure we cancel any outgoing transaction
         */
        IDT_VP3300
            .sharedController()?
            .device_cancelTransaction()
    }
    
    /// Enable Transaction Request
    /// Enables CLTS and MSR, waiting for swipe or tap to occur.
    /// Returns IDTEMVData to deviceDelegate::emvTransactionData:()
    ///
    /// - Parameters:
    ///   - amount: amount
    ///   - timeout: timeout
    /// - Throws: cannot start transaction error or device not connected
    func readCC(_ amount: Double, timeout: Int32 = 60) throws -> Void {
        
        if (IDT_VP3300
            .sharedController()
            .device_isConnected(IDT_DEVICE_VP3300_IOS)) {
            
            let cancelReturnCode = IDT_VP3300
                .sharedController()?
                .device_cancelTransaction()
            
            if RETURN_CODE_DO_SUCCESS == cancelReturnCode {
                
                let rt = IDT_VP3300
                    .sharedController()
                    .device_startTransaction(amount,
                                             amtOther: 0,
                                             type: 0,
                                             timeout: timeout,
                                             tags: nil,
                                             forceOnline: false,
                                             fallback: true)
                if RETURN_CODE_DO_SUCCESS != rt {
                    throw EmvError.cannotStartTransaction(message: String(rt.rawValue, radix: 16))
                }
            } else {
                throw EmvError.cannotStartTransaction(message: "Cannot cancel previous transaction")
            }
        } else {
            throw EmvError.deviceIsNotConnected
        }
    }
    
    func connect(friendlyName: String) -> Bool {
        
        if IDT_VP3300.sharedController()?.isConnected() ?? false {
            return true
        }
        
        IDT_VP3300
            .sharedController()
            .device_setBLEFriendlyName(friendlyName)
        
        return IDT_VP3300
            .sharedController()
            .device_enableBLEDeviceSearch(nil)
    }
    
    func connect(uuid: UUID) -> Bool {
        if IDT_VP3300.sharedController()?.isConnected() ?? false {
            return true
        }
        
        return IDT_VP3300
            .sharedController()
            .device_enableBLEDeviceSearch(uuid)
    }
}

extension EmvDevice: IDT_VP3300_Delegate {
    private func parse(
        encryptedData: String,
        key: String) throws -> String {
        
        let bytesDate: [UInt8] = [UInt8](hexString: encryptedData)
        let ksn = key.replacingOccurrences(of: " ", with: "")
        
        let iv = [UInt8](hexString: "00000000000000000000000000000000")
        let bdk = "0123456789ABCDEFFEDCBA9876543210"
        let sessionKey = try DecryptionUtility.getKey(bdkHex: bdk,
                                                      ksnHex: ksn)
        let keyData = [UInt8](hexString: sessionKey)
        let decrypted = try DecryptionUtility.aesDecrypt(data: bytesDate,
                                                         keyData: keyData,
                                                         iv: iv)!
        
        return decrypted.toHexString().hexToAscii()
    }
    
    func deviceConnected() {
        onEmvConnected?()
    }
    
    func deviceDisconnected() {
        onEmvDisconnected?()
    }
    
    func lcdDisplay(_ mode: Int32, lines: [Any]!) {
        onEmvSendMessage?(lines.description)
    }
    
    func deviceMessage(_ message: String!) {
        onEmvSendMessage?(message)
    }
    
    func emvTransactionData(_ emvData: IDTEMVData!,
                            errorCode error: Int32) {
        if emvData == nil {
            onEmvDataParseError?("Emv data empty")
            
            return
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_TIME_OUT {
            onEmvTimeout?()
            
            return
        }
        
        // Swipe
        if emvData.cardData != nil {
            do {
                let data = emvData.cardData!.encTrack2
                    .hexEncodedString()
                    .replacingOccurrences(of: " ", with: "")
                let key = emvData.cardData!.ksn
                    .hexEncodedString()
                    .replacingOccurrences(of: " ", with: "")
                
                let decryptedData = try parse(
                    encryptedData: data,
                    key: key)
                
                onEmvDataReceived?(decryptedData)
            } catch {
                onEmvDataParseError?("Cannot parse card data")
            }
            
            return
        }
        
        if emvData.unencryptedTags != nil {
            // Unencrypted tags + empty card data
            // means contactless
            if emvData.cardData == nil {
                let ksnData = emvData.unencryptedTags["FFEE12"] as? Data
                
                if ksnData != nil {
                    let track2DataCandidate = emvData.unencryptedTags["DFEF4D"] as? Data
                    if track2DataCandidate != nil {
                        let dataHex = track2DataCandidate!
                            .hexEncodedString()
                            .replacingOccurrences(of: " ", with: "")
                        let keyHex = ksnData!
                            .hexEncodedString()
                            .replacingOccurrences(of: " ", with: "")
                        do {
                            let decryptedData = try parse(
                                encryptedData: dataHex,
                                key: keyHex)
                            onEmvDataReceived?(decryptedData)
                        } catch {
                            onEmvDataParseError?("Cannot parse card data")
                        }
                    } else {
                        onEmvDataParseError?("Missing Tracka Data")
                    }
                } else {
                    onEmvDataParseError?("Missing KSN")
                }
                
                return
            }
        }
    }
}
