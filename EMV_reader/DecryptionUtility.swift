//
//  DecryptionUtility.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 18/10/2018.
//  Copyright © 2018 Beachy. All rights reserved.
//

import Foundation
import CryptoSwift

class Decrypto {
    
    func expand3DESKey(hex: String) -> String{
        if (hex.count == 48) {
            return hex
        }
        
        let expandBy = 48 - hex.count
        return hex + hex.prefix(expandBy)
    }
    
    func extendBDK(bdk: String) -> String {
        /**
         * 24bit long key is in fact a hex with lenght of 48
         */
        if (bdk.count == 48) {
            return bdk
        }
        
        if (bdk.count < 48) {
            let offset = 48 - bdk.count
            let copy = bdk.prefix(offset)
            
            return bdk + copy
        }
        
        return bdk
    }
    
    func hexToByteArray(hex: String) -> [UInt8] {
        return hex.pairs.filter({$0 != ""}).map({ UInt8($0, radix: 16)! })
    }
    
    func hexToBinaryData(hex: String) -> String {
        return hex.pairs.filter({$0 != ""})
            .map({ String(UnicodeScalar(UInt8($0, radix: 16)!)) })
            .reduce("", { return $0 + $1 })
    }
    
    func hexToAscii(hex: String) -> String {
        let chars = hex.pairs.filter({$0 != ""})
            .map({ Character(UnicodeScalar(UInt8($0, radix: 16)!)) })
        return String(chars)
    }
    
    
    func binaryDataToHexString(bytes: [UInt8]) -> String {
        return bytes.reduce("", {
            var v = String($1, radix: 16, uppercase: true)
            if (v.count == 1) {
                v = "0" + v;
            }
            
            return $0 + v
        })
    }
    
    func binaryXOR(_ firstHex: String, _ secondHex: String) -> [UInt8] {
        var data1 = hexToByteArray(hex: firstHex)
        var data2 = hexToByteArray(hex: secondHex)
        
        if ( data1.count < data2.count) {
            while (data1.count < data2.count) {
                data1.insert(0, at: 0)
            }
        }
        
        if ( data2.count < data1.count) {
            while (data2.count < data1.count) {
                data2.insert(0, at: 0)
            }
        }
        
        var bytes = [UInt8]()
        for item in 0..<data1.count {
            bytes.insert(data1[item] ^ data2[item], at: item)
        }
        
        return bytes
    }
    
    func binaryAnd(_ firstHex: String, _ secondHex: String) -> [UInt8] {
        var data1 = hexToByteArray(hex: firstHex)
        var data2 = hexToByteArray(hex: secondHex)
        
        if ( data1.count < data2.count) {
            while (data1.count < data2.count) {
                data1.insert(0, at: 0)
            }
        }
        
        if ( data2.count < data1.count) {
            while (data2.count < data1.count) {
                data2.insert(0, at: 0)
            }
        }
        
        var bytes = [UInt8]()
        for item in 0..<data1.count {
            bytes.insert(data1[item] & data2[item], at: item)
        }
        
        return bytes
    }
    
    /**
     * Get the counter bits from your original (not masked!) 10-byte KSN
     * by ANDing its bottom three bytes with 0x1FFFFF.
     * (Recall that the bottom 21 bits of a KSN comprise the transaction counter.)
     */
    func getCounterBits(ksnHex: String) -> [UInt8] {
        let bottomThree = Array(hexToByteArray(hex: ksnHex).suffix(3))
        
        return binaryAnd(binaryDataToHexString(bytes: bottomThree), "1FFFFF")
    }
    
    func getKey(bdkHex: String, ksnHex: String) -> String {
        let IPEK = getIPEK(bdkHex: bdkHex, ksnHex: ksnHex)
        let derivedKey = deriveKey(ksnHex: ksnHex, ipekHex: IPEK)
        
        let initialVector: [UInt8] = hexToByteArray(hex: "0000000000000000")
        let dataMask = "0000000000FF00000000000000FF0000"
        let maskedKey = binaryXOR(dataMask, derivedKey)
        
        let expandedMaskedKey = hexToByteArray(hex: expand3DESKey(hex: binaryDataToHexString(bytes: maskedKey)))
        
        let left = Array(desEncrypt(data: Array(maskedKey.prefix(8)),
                                    keyData: expandedMaskedKey,
                                    iv: initialVector)!.prefix(8))
        
        let right = Array(desEncrypt(data: Array(maskedKey.suffix(8)),
                                     keyData: expandedMaskedKey,
                                     iv: initialVector)!.prefix(8))
        
        
        return binaryDataToHexString(bytes: (left + right))
    }
    
    func deriveKey(ksnHex: String, ipekHex: String) -> String {
        
        let bottomEightFromKSN = Array(hexToByteArray(hex: ksnHex).suffix(8))
        let baseKSN = binaryAnd("FFFFFFFFFFE00000", binaryDataToHexString(bytes: bottomEightFromKSN))
        
        let counter = getCounterBits(ksnHex: ksnHex)
        var currKey = ipekHex
        
        let counterInt = Int(binaryDataToHexString(bytes: counter), radix: 16)!
        var baseKSNInt = Int(binaryDataToHexString(bytes: baseKSN), radix: 16)!
        
        
        var shiftReg = 0x100000
        var pass = 0
        
        while(shiftReg > 0) {
            if ((shiftReg & counterInt) > 0) {
                baseKSNInt |= shiftReg
                currKey = binaryDataToHexString(
                    bytes: generateKey(key: currKey, ksn: String(format:"%llX", baseKSNInt)));
                
                let ksnHex = String(format:"%llX", baseKSNInt)
                let keyHex = currKey
                
                print("Pass \(pass), baseKSN:\(ksnHex) key: \(keyHex)")
                
                pass += 1
            }
            
            shiftReg >>= 1
        }
        
        return currKey
    }
    
    func generateKey(key: String, ksn: String) -> [UInt8] {
        let mask = "C0C0C0C000000000C0C0C0C000000000"
        let maskedKey =  binaryXOR(mask, key);
        
        let left  = encryptRegister(key: maskedKey, ksn: hexToByteArray(hex: ksn));
        let right = encryptRegister(key: hexToByteArray(hex: key), ksn: hexToByteArray(hex: ksn));
        
        return left + right
    }
    
    func encryptRegister(key: [UInt8], ksn: [UInt8]) -> [UInt8] {
        let bottomEight = Array(key.suffix(8))
        let topEight = Array(key.prefix(8))
        let initialVector: [UInt8] = hexToByteArray(hex: "0000000000000000")
        let bottomEightXORKSN = binaryXOR(binaryDataToHexString(bytes: bottomEight),
                                          binaryDataToHexString(bytes: ksn))
        let desEncrypted = Array(singleDesEncrypt(data: bottomEightXORKSN,
                                                  keyData: topEight,
                                                  iv: initialVector)!.prefix(8))
        
        return binaryXOR(binaryDataToHexString(bytes: bottomEight),
                         binaryDataToHexString(bytes: desEncrypted))
    }
    
    func getIPEK(bdkHex: String, ksnHex: String) -> String {
        
        let extendedBdk = extendBDK(bdk: bdkHex)
        let maskedKSN = binaryAnd(ksnHex, "FFFFFFFFFFFFFFE00000")
        
        let bytesDate: [UInt8] = hexToByteArray(hex: binaryDataToHexString(bytes:maskedKSN))
        let keyData: [UInt8] = hexToByteArray(hex: extendedBdk)
        let initialVector: [UInt8] = hexToByteArray(hex: "0000000000000000")
        let leftIPEK = desEncrypt(data: bytesDate,
                                  keyData: keyData,
                                  iv: initialVector)!
        //take only 8 bytes
        let leftHalfOfIPEK = Array(leftIPEK[..<8])
        
        let xorKey = binaryXOR(bdkHex, "C0C0C0C000000000C0C0C0C000000000")
        let xorExpandedKey = hexToByteArray(
            hex: expand3DESKey(hex: binaryDataToHexString(bytes: xorKey)))
        
        let rightIPEK = desEncrypt(data: maskedKSN,
                                   keyData: xorExpandedKey,
                                   iv: initialVector)!
        //take only 8 bytes
        let rightHalfOfIPEK = Array(rightIPEK[..<8])
        
        let IPEK = leftHalfOfIPEK + rightHalfOfIPEK
        
        return binaryDataToHexString(bytes: IPEK)
    }
    
    func decryptAES() {
        
        let encryptedData = ""
        let key = ""
        
        do {
            let bytesDate: [UInt8] = hexToByteArray(hex: encryptedData)
            let keyData: [UInt8] = hexToByteArray(hex: key)
            
            let d = try AES(key: keyData,
                            blockMode: CBC(iv: hexToByteArray(hex: "00000000000000000000000000000000")),
                            padding: .noPadding)
                .decrypt(bytesDate)
            
            print("D: \(d)")
            
        } catch {
            print(error)
        }
    }
    
    
    func singleDesEncrypt(data: [UInt8], keyData: [UInt8], iv: [UInt8]) -> [UInt8]? {
        let cryptData = NSMutableData(
            length: Int(data.count) + kCCBlockSizeDES)!
        let keyLength              = size_t(kCCKeySizeDES)
        let operation: CCOperation = UInt32(kCCEncrypt)
        let algoritm:  CCAlgorithm = UInt32(kCCAlgorithmDES)
        let options:   CCOptions   = UInt32(kCCOptionECBMode + kCCOptionPKCS7Padding)
        
        var numBytesEncrypted :size_t = 0
        
        let cryptStatus = CCCrypt(operation,
                                  algoritm,
                                  options,
                                  keyData,
                                  keyLength,
                                  iv,
                                  data,
                                  data.count,
                                  cryptData.mutableBytes,
                                  cryptData.length,
                                  &numBytesEncrypted)
        
        
        if UInt32(cryptStatus) == UInt32(kCCSuccess) {
            cryptData.length = Int(numBytesEncrypted)
            
            return [UInt8](cryptData as Data)
            
        } else {
            print("Error: \(cryptStatus)")
        }
        return nil
    }
    
    func desEncrypt(data: [UInt8], keyData: [UInt8], iv: [UInt8]) -> [UInt8]? {
        let cryptData = NSMutableData(
            length: Int(data.count) + kCCBlockSize3DES)!
        let keyLength              = size_t(kCCKeySize3DES)
        let operation: CCOperation = UInt32(kCCEncrypt)
        let algoritm:  CCAlgorithm = UInt32(kCCAlgorithm3DES)
        let options:   CCOptions   = UInt32(kCCOptionECBMode + kCCOptionPKCS7Padding)
        
        var numBytesEncrypted :size_t = 0
        
        let cryptStatus = CCCrypt(operation,
                                  algoritm,
                                  options,
                                  keyData,
                                  keyLength,
                                  iv,
                                  data,
                                  data.count,
                                  cryptData.mutableBytes,
                                  cryptData.length,
                                  &numBytesEncrypted)
        
        
        if UInt32(cryptStatus) == UInt32(kCCSuccess) {
            cryptData.length = Int(numBytesEncrypted)
            
            return [UInt8](cryptData as Data)
            
        } else {
            print("Error: \(cryptStatus)")
        }
        return nil
    }
}
