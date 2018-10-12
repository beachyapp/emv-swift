//
//  BLEListViewController.swift
//  EMV_reader
//
//  Created by Piotr Ilski on 10.10.2018.
//  Copyright © 2018 Beachy. All rights reserved.
//
import CoreBluetooth
import UIKit
import CryptoSwift

extension Collection {
    var pairs: [SubSequence] {
        var start = startIndex
        return (0...count/2).map { _ in
            let end = index(start, offsetBy: 2, limitedBy: endIndex) ?? endIndex
            defer { start = end }
            return self[start..<Swift.min(end, endIndex)]
        }
    }
}

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }
    
    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined(separator: " ")
    }
    
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hexString.index(hexString.startIndex, offsetBy: i*2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}

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
            .reduce("", { return $0 + $1 });
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
    
    func getKey(bdkHex: String, ksnHex: String) -> String {
        
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

class BLEListViewController: UIViewController {
    var devices: Set<BLEDevice> = []
    var centralManager: CBCentralManager!
    var selectedDevice: BLEDevice? = nil
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var selectedDeviceLabel: UILabel!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var listeningButton: UIButton!
    
    
    @IBAction func startListeningLoop(_ sender: UIButton) {
        
        IDT_VP3300
            .sharedController()
            .emv_disableAutoAuthenticateTransaction(false)
        
        let rt = IDT_VP3300
            .sharedController()
            .device_startTransaction(1.00,
                                     amtOther: 0,
                                     type: 0,
                                     timeout: 60,
                                     tags: nil,
                                     forceOnline: false,
                                     fallback: true)
        
        if RETURN_CODE_DO_SUCCESS == rt {
            print("Start transaction command accepted")
            print(rt)
        } else {
            print("Start EMV transaction error")
            print(rt)
        }
    }
    
    @IBAction func connect(_ sender: UIButton) {
        if (selectedDevice != nil) {
            
            IDT_VP3300
                .sharedController()
                .device_enableBLEDeviceSearch(
                    selectedDevice!.getIdentifier())
            print("connecting... \(String(describing: selectedDevice?.identifier))")
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        connectButton.isEnabled = false;
        
        IDT_VP3300.sharedController().delegate = self
        
        centralManager = CBCentralManager(delegate: self,
                                          queue: DispatchQueue.main)
        
        
        let decrypto = Decrypto()
        
        let bdk = "0123456789ABCDEFFEDCBA9876543210"
        let ksn = "62994900000000000001"
        
        let IPEK = decrypto.getKey(bdkHex: bdk, ksnHex: ksn)
        
        // expected: B5610650EBC24CA3CACDD08DDAFE8CE3
        
        print("IPEK = \(IPEK)")
    }
    
}

extension BLEListViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sortedDevices = self.devices.sorted(by: { $0.name < $1.name })
        let device = sortedDevices[indexPath.row]
        
        if (device.isSupportedEmv) {
            selectedDevice = device;
        }
        
        if (selectedDevice != nil) {
            connectButton.isEnabled = true
            selectedDeviceLabel.text = selectedDevice!.getName()
        } else {
            connectButton.isEnabled = false
            selectedDeviceLabel.text = "nothing selected"
        }
        
        print("Selected device: \(String(describing: selectedDevice?.getName()))")
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        selectedDevice = nil;
        
        print("Selected device: \(String(describing: selectedDevice))")
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.devices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "BLEDeviceTableViewCell"
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as? BLEDeviceTableViewCell  else {
            fatalError("The dequeued cell is not an instance of BLEDeviceTableViewCell.")
        }
        
        let sortedDevices = self.devices.sorted(by: { $0.name < $1.name })
        let device = sortedDevices[indexPath.row]
        
        cell.nameLabel.text = device.getName()
        cell.isEMVReader.text = device.isSupportedEmv ? "EMV" : ""
        cell.selectionStyle = .none
        if (device.isSupportedEmv) {
            cell.selectionStyle = .default
            cell.nameLabel.textColor = UIColor(displayP3Red: 46/255,
                                               green: 139/255,
                                               blue: 87/255,
                                               alpha: 0.85)
        }
        
        return cell
    }
    
}

extension BLEListViewController: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            
            self.centralManager?.scanForPeripherals(
                withServices: nil,
                options: nil)
        case .poweredOff:
            self.centralManager?.stopScan();
        default:
            print("unknown state")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let prevCount = self.devices.count;
        
        self.devices.insert(BLEDevice(
            name: peripheral.name ?? "unknown",
            identifier: peripheral.identifier))
        
        if (self.devices.count != prevCount) {
            self.tableView.reloadData()
            //            print("REFRESHING...")
        }
    }
}

extension BLEListViewController: IDT_VP3300_Delegate {
    @objc func completeEMV() {
        NotificationCenter.default.post(name: Notification.Name(rawValue: "completeEMV"), object: nil)
    }
    
    @objc func startEMV() {
        NotificationCenter.default.post(name: Notification.Name(rawValue: "startEMV"), object: nil)
    }
    
    func lcdDisplay(_ mode: Int32, lines: [Any]!) {
        print("LCD DISPLAY: \(String(describing: lines))")
    }
    
    func deviceMessage(_ message: String!) {
        print("MESSAGE: \(message ?? String())");
    }
    
    func swipeMSRData(_ cardData: IDTMSRData!) {
        print("---- DATA SWIPED ---")
        print("Track 3: \(String(describing: cardData.track3))");
        print("Encoded Track 1: \(cardData.encTrack1.description)");
        print("Encoded Track 2: \(cardData.encTrack2.description)");
        print("Encoded Track 3: \(cardData.encTrack3.description)");
        print("Hash Track 1: \(cardData.hashTrack1.description)");
        print("Hash Track 2: \(cardData.hashTrack2.description)");
        print("Hash Track 3: \(cardData.hashTrack3.description)");
        
        if cardData.unencryptedTags != nil {
            print("Unencrypted Tags: \( cardData.unencryptedTags.description)")
        }
        
        if cardData.encryptedTags != nil {
            print("Encrypted Tags: \(cardData.encryptedTags.description)")
        }
        
        if cardData.maskedTags != nil {
            print("Masked Tags: \(cardData.maskedTags.description)")
        }
    }
    
    func emvTransactionData(_ emvData: IDTEMVData!, errorCode error: Int32) {
        
        var loopData = true
        let autocompleteStatus = true
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_TIME_OUT {
            
        }
        
        if emvData.resultCodeV2 != EMV_RESULT_CODE_V2_NO_RESPONSE {
            print("EMV_RESULT_CODE_V2_RESPONSE: \(emvData.resultCodeV2.rawValue)")
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_GO_ONLINE {
            print("ONLINE REQUEST")
            loopData = false
            
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
            print("Start success: authentication required")
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_APPROVED || emvData.resultCodeV2 == EMV_RESULT_CODE_V2_APPROVED_OFFLINE {
            print("APPROVED");
        }
        
        if emvData.resultCodeV2 == EMV_RESULT_CODE_V2_MSR_SUCCESS {
            print("MSR Data Captured")
        }
        
        if emvData.cardType == 0 {
            print("CONTACT")
        }
        
        if emvData.cardType == 1 {
            print("CONTACTLESS")
        }
        
        if emvData.unencryptedTags != nil {
            print("Unencrypted Tags: \(emvData.unencryptedTags.description)")
        }
        
        if emvData.encryptedTags != nil {
            print("Encrypted Tags: \(emvData.encryptedTags.description)")
        }
        
        if emvData.maskedTags != nil {
            print("Masked Tags: \(emvData.maskedTags.description)")
        }
        
        if emvData.hasAdvise {
            print("Response has advise request")
        }
        
        if emvData.hasReversal {
            print("Response has reversal request")
        }
        
        if loopData {
            Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(startEMV), userInfo: nil, repeats: false)
        }
        
        if (emvData.cardData != nil) {
            
            
            
            print("CARD DATA: \(String(describing: emvData.cardData))")
            let ksn = emvData.cardData.ksn != nil ? emvData.cardData.ksn.hexEncodedString() : "nth"
            print("KSN:  \(ksn)")
            let ses = emvData.cardData.sessionID != nil ? emvData.cardData.sessionID.hexEncodedString() : "nth"
            print("SESSION ID:  \(ses)")
            let rsn = emvData.cardData.rsn != nil ? emvData.cardData.rsn : "nth"
            print("RSN:  \(String(describing: rsn))")
            print("STATUS:  \(emvData.cardData.readStatus)")
            
            print("-------- RAW DATA --------")
            print(emvData.cardData.cardData.hexEncodedString())
            
            
            
            print("-------- RAW DATA CMPLX --------")
            print(emvData.cardData.track1)
            print(emvData.cardData.encTrack1.hexEncodedString())
            
            print(emvData.cardData.track2)
            print(emvData.cardData.encTrack2.hexEncodedString())
            
            tryParse(encryptedData: emvData.cardData!.encTrack2.hexEncodedString(),
                     key: emvData.cardData!.ksn.hexEncodedString())
        }
    }
    
    func hexToByteArray(hex: String) -> [UInt8] {
        return hex.replacingOccurrences(of: " ", with: "")
            .pairs
            .filter({$0 != ""})
            .map({
                print($0)
                return UInt8($0, radix: 16) ?? 0
            })
    }
    
    func tryParse(encryptedData: String, key: String) {
        
        do {
            let bytesDate: [UInt8] = hexToByteArray(hex: encryptedData)
            let keyData: [UInt8] = hexToByteArray(hex: key)
            
            let d = try AES(key: keyData,
                            blockMode: CBC(iv: hexToByteArray(hex: "00000000000000000000000000000000")),
                            padding: .noPadding)
                .decrypt(bytesDate)
            
            print(hexToByteArray(hex: encryptedData))
            print(hexToByteArray(hex: key))
            
            print(d.toHexString())
        } catch {
            print(error)
        }
    }
    
    func EDE3KeyExpand(key: String ) -> String {
        switch key.count {
        case 16:
            let index = key.index(key.startIndex,
                                  offsetBy: key.count/2)
            return key + String(key[..<index])
        case 24:
            return key
        default:
            return ""
        }
    }
    
    func hexstringToData(hex: String) -> Data {
        return Data(hexString: hex)!
    }

    
    func deviceConnected() {
        print("DEVICE CONNECTED")
        
        IDT_VP3300
            .sharedController()
            .device_disableBLEDeviceSearch()
        
        
    }
    
    func deviceDisconnected() {
        print("DEVICE DISCONNECTED")
    }
    
    
}
