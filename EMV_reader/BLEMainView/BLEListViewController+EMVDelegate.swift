//
//  BLEListViewController+EMVDelegate.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 19/10/2018.
//  Copyright © 2018 Beachy. All rights reserved.
//

import Foundation

extension BLEListViewController: IDT_VP3300_Delegate {
    @objc func completeEMV() {
        NotificationCenter.default.post(name: Notification.Name(rawValue: "completeEMV"), object: nil)
        
        print("COMPLETE  EMV!")
    }
    
    @objc func startEMV() {
        NotificationCenter.default.post(name: Notification.Name(rawValue: "startEMV"), object: nil)
        
        print("START  EMV!");
        let TLVstring = "DFEE12"
        let TLV = IDTUtility.hex(toData: TLVstring)
        
        var data: NSDictionary?
        let ret2 = IDT_VP3300
            .sharedController()
            .emv_retrieveTransactionResult(TLV, retrievedTags: &data)
        
        printDebugMessage("\(ret2)")
        
//        let ret = IDT_VP3300
//            .sharedController()
//            .emv_completeOnlineEMVTransaction(true,
//                                              hostResponseTags: Data(bytes: [0xDF, 0xEE, 0x1B] as [UInt8]))
//        print(ret, ret2)
//        if RETURN_CODE_DO_SUCCESS == ret || RETURN_CODE_DO_SUCCESS == ret2{
//            print (" FINE!")
//        }
    }
    
    func lcdDisplay(_ mode: Int32, lines: [Any]!) {
        printDebugMessage("LCD DISPLAY: \(String(describing: lines))")
    }
    
    func deviceMessage(_ message: String!) {
        printDebugMessage("MESSAGE: \(message ?? String())");
    }
    
    func swipeMSRData(_ cardData: IDTMSRData!) {
        printDebugMessage("---- DATA SWIPED ---")
        
        if cardData.unencryptedTags != nil {
            printDebugMessage("Unencrypted Tags: \( cardData.unencryptedTags.description)")
        }
        
        if cardData.encryptedTags != nil {
            printDebugMessage("Encrypted Tags: \(cardData.encryptedTags.description)")
        }
        
        if cardData.maskedTags != nil {
            printDebugMessage("Masked Tags: \(cardData.maskedTags.description)")
        }
    }
    
    func emvTransactionData(_ emvData: IDTEMVData!, errorCode error: Int32) {
        
        if emvData == nil {
            printDebugMessage("Error parsing card data: \(error)")
            
            return
        }
        
        var loopData = true
        let autocompleteStatus = true
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_TIME_OUT {
            printDebugMessage("EMV_RESULT_CODE_V2_TIME_OUT")
            return
        }
        
        if emvData.resultCodeV2 != EMV_RESULT_CODE_V2_NO_RESPONSE {
            printDebugMessage("EMV_RESULT_CODE_V2_RESPONSE: \(emvData.resultCodeV2)")
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_GO_ONLINE {
            printDebugMessage("ONLINE REQUEST")
            loopData = false
            
            
            print("ONLINE REQUEST!!!")
            
            if autocompleteStatus {
                Timer.scheduledTimer(timeInterval: 0.5,
                                     target: self,
                                     selector: #selector(completeEMV),
                                     userInfo: nil,
                                     repeats: false)
            }
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_START_TRANS_SUCCESS {
            loopData = false
            printDebugMessage("Start success: authentication required")
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_APPROVED || emvData.resultCodeV2 == EMV_RESULT_CODE_V2_APPROVED_OFFLINE {
            printDebugMessage("APPROVED");
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_MSR_SUCCESS {
            printDebugMessage("MSR Data Captured")
        }
        
        if emvData.cardType == 0 {
            printDebugMessage("CONTACT")
        }
        
        if emvData.cardType == 1 {
            printDebugMessage("CONTACTLESS")
        }
        
        if emvData.unencryptedTags != nil {
            printDebugMessage("Unencrypted Tags: \(emvData.unencryptedTags.description)")
            
            if(emvData.cardData == nil) {
                let ksnData = emvData.unencryptedTags["FFEE12"] as? Data
                
                if (ksnData != nil) {
                    let track2DataCandidate = emvData.unencryptedTags["DFEF4D"] as? Data
                    if (track2DataCandidate != nil) {
                        let dataHex = track2DataCandidate!.hexEncodedString()
                            .replacingOccurrences(of: " ", with: "")
                        let keyHex = ksnData!.hexEncodedString()
                            .replacingOccurrences(of: " ", with: "")
                        
                        tryParse(encryptedData: dataHex, key: keyHex)
                    }
                }
            }
            
        }
        
        if emvData.encryptedTags != nil {
            printDebugMessage("Encrypted Tags: \(emvData.encryptedTags.description)")
        }
        
        if emvData.maskedTags != nil {
            printDebugMessage("Masked Tags: \(emvData.maskedTags.description)")
        }
        
        if emvData.hasAdvise {
            printDebugMessage("Response has advise request")
        }
        
        if emvData.hasReversal {
            printDebugMessage("Response has reversal request")
        }
        
        if loopData {
            Timer.scheduledTimer(timeInterval: 0.5,
                                 target: self,
                                 selector: #selector(startEMV),
                                 userInfo: nil,
                                 repeats: false)
        }
        
        if (emvData.cardData != nil) {
            tryParse(encryptedData: emvData.cardData!.encTrack2.hexEncodedString(),
                     key: emvData.cardData!.ksn.hexEncodedString())
            
            let TLVstring = "DFEE12"
            let TLV = IDTUtility.hex(toData: TLVstring)
            
            
            var data: NSDictionary?
            let ret2 = IDT_VP3300
                .sharedController()
                .emv_retrieveTransactionResult(TLV, retrievedTags: &data)
            
            
            printDebugMessage("--------------------------------")
            printDebugMessage("RET VAL: \(String(ret2.rawValue,radix: 16))")
            printDebugMessage("DATA: \(data)")
            printDebugMessage("--------------------------------")
        }
    }
    
    
    func tryParse(encryptedData: String, key: String) {
        
        do {
            let bytesDate: [UInt8] = [UInt8](hexString: encryptedData)
            let ksn = key.replacingOccurrences(of: " ", with: "")
            
            let bdk = "0123456789ABCDEFFEDCBA9876543210"
            let sessionKey = try DecryptionUtility.getKey(bdkHex: bdk, ksnHex: ksn)
            let keyData = [UInt8](hexString: sessionKey)
            
//            let d = try AES(key: keyData,
//                            blockMode: CBC(iv: [UInt8](hexString: "00000000000000000000000000000000")),
//                            padding: .noPadding)
//                .decrypt(bytesDate)
//
            let d2 = try DecryptionUtility
                .aesDecrypt(data: bytesDate,
                            keyData: keyData,
                            iv: [UInt8](hexString: "00000000000000000000000000000000"))!
            
            
            let ccString = d2.toHexString().hexToAscii()
            let alert = UIAlertController(
                title: "Got it!",
                message: ccString,
                preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            
            self.present(alert, animated: true)
        } catch {
            printDebugMessage("Error parsing CC data: \(error)")
        }
    }
    
    func deviceConnected() {
        printDebugMessage("DEVICE CONNECTED")
        
        IDT_VP3300
            .sharedController()
            .device_disableBLEDeviceSearch()
        
        //        let TLVstring = "5F360102DFEF4B017f"
        //        //        "5F360102"
        //        let TLV = IDTUtility.hex(toData: TLVstring)
        //        let rt = IDT_VP3300.sharedController().emv_setTerminalData(IDTUtility.tlVtoDICT(TLV))
        //
        //        if RETURN_CODE_DO_SUCCESS == rt {
        //            printDebugMessage("GOOOD")
        //        } else {
        //            printDebugMessage("OUPS: \(String(rt.rawValue, radix: 16))")
        //        }
        
        listeningButton.isEnabled = true
    }
    
    func deviceDisconnected() {
        printDebugMessage("DEVICE DISCONNECTED")
        
        listeningButton.isEnabled = false
    }
}
